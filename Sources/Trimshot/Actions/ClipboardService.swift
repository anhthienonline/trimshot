import AppKit

enum ClipboardService {

    /// Writes the capture as PNG *and* TIFF.
    ///
    /// PNG is what most apps prefer and it keeps the alpha channel; TIFF is the flavour older
    /// AppKit apps look for first. Writing both means paste works everywhere from Slack to
    /// Photoshop.
    ///
    /// This deliberately ignores the image-format preference, which governs saved files only.
    /// A JPEG on the pasteboard would put compression artefacts into every pasted capture,
    /// and this is a tool people use to check colours and edges — the one place lossy is not
    /// a preference worth honouring. Settings says so next to the picker.
    /// - Returns: whether the pasteboard genuinely ended up holding the image.
    ///
    /// The return value is the point. `clearContents()` empties the pasteboard *before*
    /// anything is written, so every failure below leaves the user with a clipboard that is
    /// not merely unchanged but wiped — and the caller used to report "Copied" regardless.
    /// A copy that quietly produces nothing is indistinguishable from a copy that worked
    /// until you try to paste, which is exactly how this went unexplained for so long.
    @discardableResult
    static func copy(_ image: CGImage, scale: CGFloat = 1) -> Bool {
        let log = Diagnostics.clipboard
        log.debug("copy requested: \(Diagnostics.describe(image), privacy: .public) scale=\(scale)")

        let rep = NSBitmapImageRep(cgImage: image)
        // `size` is in points, and it is what a receiving app lays the image out by — the pixel
        // data is unaffected either way. Setting it to the pixel count declared 1pt = 1px, so a
        // 2× Retina capture pasted into anything that respects the size arrived twice as large
        // as the region selected. Dividing by the capture scale keeps every pixel while making
        // the image measure what the user actually drew.
        let denominator = scale > 0 ? scale : 1
        rep.size = NSSize(
            width: CGFloat(image.width) / denominator,
            height: CGFloat(image.height) / denominator
        )

        let png = rep.representation(using: .png, properties: [:])
        let tiff = rep.tiffRepresentation
        log.debug("encoded: png=\(png?.count ?? -1) tiff=\(tiff?.count ?? -1)")

        // Nothing encoded: say so and leave the pasteboard alone rather than clearing it for
        // no gain. Whatever the user had before is worth more than an empty clipboard.
        guard png != nil || tiff != nil else {
            log.error("both encoders returned nil — pasteboard left untouched")
            return false
        }

        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        let after = pasteboard.clearContents()
        var wrote: [String] = []
        if let png, pasteboard.setData(png, forType: .png) { wrote.append("png") }
        if let tiff, pasteboard.setData(tiff, forType: .tiff) { wrote.append("tiff") }

        // Read it back through the same door a receiving app uses. `setData` returning true
        // is not proof: the pasteboard is shared state and another process can take ownership
        // between the write and the paste.
        let readable = NSImage(pasteboard: pasteboard) != nil
        let types = (pasteboard.types ?? []).map(\.rawValue).joined(separator: ",")
        let result = "changeCount \(before)→\(after) now=\(pasteboard.changeCount) "
            + "wrote=[\(wrote.joined(separator: ","))] types=[\(types)] readBack=\(readable)"
        // `.info` rather than `.debug`: debug records are not retained, and an
        // intermittent fault has to be readable *after* it happens.
        log.info("\(result, privacy: .public)")

        if wrote.isEmpty || !readable {
            log.error("pasteboard write did not stick: wrote=\(wrote.count) readBack=\(readable)")
            return false
        }
        return true
    }

    /// An image from the pasteboard, if there is one.
    static func readImage() -> CGImage? {
        let pasteboard = NSPasteboard.general
        guard
            let image = NSImage(pasteboard: pasteboard),
            let data = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: data)
        else { return nil }
        return rep.cgImage
    }

    static func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
