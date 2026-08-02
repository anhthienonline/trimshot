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
    static func copy(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        // NSBitmapImageRep(cgImage:) reports a point size derived from the image DPI;
        // force it to the pixel size so pasted images land at full resolution.
        rep.size = NSSize(width: image.width, height: image.height)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = rep.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
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
