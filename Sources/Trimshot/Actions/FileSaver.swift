import AppKit

enum FileSaverError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "Could not encode the image."
        }
    }
}

enum FileSaver {

    /// Lifts a panel above the capture overlay.
    ///
    /// A panel defaults to level 0 while the overlay sits at `.screenSaver` (1000), so any
    /// picker opened during a capture appears *behind* it — invisible, while `runModal()`
    /// blocks the app in a modal session. The symptom is the whole toolbar going dead with
    /// nothing on screen to explain why.
    @MainActor
    private static func raiseAboveOverlay(_ panel: NSSavePanel) {
        panel.level = OverlayLevel.panel
    }

    /// Writes the capture into the configured folder and returns where it landed.
    @discardableResult
    static func save(
        _ image: CGImage,
        to directory: URL,
        format: ImageFormat
    ) throws -> URL {
        let data = try encode(image, as: format)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let url = uniqueURL(in: directory, format: format)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Shows a save panel instead of writing straight to the configured folder.
    @MainActor
    @discardableResult
    static func saveWithPanel(_ image: CGImage, format: ImageFormat) throws -> URL? {
        let data = try encode(image, as: format)

        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        raiseAboveOverlay(panel)
        panel.allowedContentTypes = format == .png ? [.png] : [.jpeg]
        panel.nameFieldStringValue = defaultFilename(format: format)
        panel.directoryURL = Settings.shared.saveDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Asks for an image file, without a modal run loop.
    ///
    /// `runModal()` cannot be used while the capture overlay is up. Measured: it returns
    /// `.cancel` immediately without ever presenting, and for as long as it runs, blocks
    /// scheduled on the main queue are never serviced — the modal loop starves them. The
    /// visible result is a button that does nothing at all.
    ///
    /// `begin(completionHandler:)` presents the same panel as an ordinary window. Measured in
    /// the same situation: visible, unoccluded, and key.
    @MainActor
    static func chooseImage(completion: @escaping (CGImage?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        raiseAboveOverlay(panel)
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image to place on the capture"

        panel.begin { response in
            // AppKit calls this on the main thread but types it as a plain closure.
            MainActor.assumeIsolated {
                guard
                    response == .OK,
                    let url = panel.url,
                    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else {
                    completion(nil)
                    return
                }
                completion(image)
            }
        }
    }

    private static func encode(_ image: CGImage, as format: ImageFormat) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        guard
            let data = rep.representation(
                using: format.bitmapType,
                properties: format.properties
            )
        else { throw FileSaverError.encodingFailed }
        return data
    }

    /// `Screenshot 2026-08-02 at 14.31.05.png`, matching macOS's own naming.
    private static func defaultFilename(format: ImageFormat) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())).\(format.fileExtension)"
    }

    /// Appends ` (2)`, ` (3)`… when two captures land in the same second.
    private static func uniqueURL(in directory: URL, format: ImageFormat) -> URL {
        let base = defaultFilename(format: format)
        var url = directory.appendingPathComponent(base)
        guard FileManager.default.fileExists(atPath: url.path) else { return url }

        let stem = (base as NSString).deletingPathExtension
        var counter = 2
        repeat {
            url = directory.appendingPathComponent("\(stem) (\(counter)).\(format.fileExtension)")
            counter += 1
        } while FileManager.default.fileExists(atPath: url.path)
        return url
    }
}
