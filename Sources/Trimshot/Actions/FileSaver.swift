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
        panel.allowedContentTypes = format == .png ? [.png] : [.jpeg]
        panel.nameFieldStringValue = defaultFilename(format: format)
        panel.directoryURL = Settings.shared.saveDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try data.write(to: url, options: .atomic)
        return url
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
