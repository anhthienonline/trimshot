import AppKit
import TrimshotCore

/// `Trimshot --render-chrome <outputDir>`
///
/// Renders the overlay's chrome — dim, selection border, handles, size label, crosshair,
/// magnifier — into PNGs against a real screen capture, without ever showing a window.
///
/// This exists so the selection UI can be inspected and iterated on directly, instead of
/// having to trigger the hotkey and screenshot the result by hand every time a colour or
/// an offset changes.
@MainActor
enum ChromePreview {

    static func run(outputDirectory: URL) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        Task { @MainActor in
            let ok = await perform(outputDirectory: outputDirectory)
            exit(ok ? 0 : 1)
        }

        app.run()
        exit(1)
    }

    private static func perform(outputDirectory: URL) async -> Bool {
        guard PermissionGate.hasScreenRecordingAccess || CGRequestScreenCaptureAccess() else {
            print("✗ no Screen Recording permission for this process")
            return false
        }

        let shots: [DisplayShot]
        do {
            shots = try await ScreenCapturer.captureAllDisplays()
        } catch {
            print("✗ capture failed: \(error.localizedDescription)")
            return false
        }

        guard let shot = shots.first(where: { $0.geometry.frame.origin == .zero }) ?? shots.first
        else {
            print("✗ nothing captured")
            return false
        }

        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let frame = shot.geometry.frame
        let selection = CGRect(
            x: frame.minX + 260,
            y: frame.midY - 90,
            width: 420,
            height: 240
        )
        // Just inside the selection's top-left, so the magnifier and the size label are
        // both in frame and can be checked for overlap.
        let pointer = CGPoint(x: selection.minX + 70, y: selection.maxY - 40)

        // A window big enough to hold the selection, its label and the loupe.
        let inspectRegion = selection.insetBy(dx: -230, dy: -170)

        // The same region with no chrome at all, as a baseline for judging the dim and
        // for spotting anything the chrome accidentally erases.
        if let raw = crop(shot.image, to: inspectRegion, shot: shot) {
            let url = outputDirectory.appendingPathComponent("chrome-raw.png")
            write(raw, to: url)
            print("  \(raw.width)×\(raw.height)  → \(url.path)  (no chrome)")
        }

        let marks = sampleAnnotations(in: selection)

        let states: [(name: String, settled: Bool, marks: [Annotation])] = [
            ("chrome-dragging", false, []),
            ("chrome-settled", true, []),
            ("chrome-annotated", true, marks),
        ]

        for state in states {
            guard
                let image = render(
                    shot: shot,
                    selection: selection,
                    pointer: pointer,
                    isSettled: state.settled,
                    annotations: state.marks
                ),
                let cropped = crop(image, to: inspectRegion, shot: shot)
            else {
                print("✗ could not render \(state.name)")
                return false
            }

            let url = outputDirectory.appendingPathComponent("\(state.name).png")
            write(cropped, to: url)
            print("  \(cropped.width)×\(cropped.height)  → \(url.path)")
        }

        guard reportToolbar(outputDirectory: outputDirectory, selection: selection) else {
            return false
        }

        return compareExportAgainstPreview(
            shot: shot,
            shots: shots,
            selection: selection,
            marks: marks,
            outputDirectory: outputDirectory
        )
    }

    /// The toolbar is the one piece that cannot be checked by looking at a capture: it is a
    /// separate panel, so it never appears in the chrome render. This builds the real thing
    /// and reports the numbers that decide whether it is visible at all.
    private static func reportToolbar(outputDirectory: URL, selection: CGRect) -> Bool {
        let bar = ToolbarView(delegate: OverlayCoordinator.shared)
        let fitting = bar.fittingSize
        print("\nToolbar")
        print("  ToolbarView.fittingSize  \(Int(fitting.width))×\(Int(fitting.height))")

        let panel = ToolbarWindow(delegate: OverlayCoordinator.shared)
        if let screen = NSScreen.main {
            panel.position(below: selection, on: screen)
        }
        let f = panel.frame
        print("  window frame             (\(Int(f.minX)), \(Int(f.minY)), \(Int(f.width))×\(Int(f.height)))")
        print("  window level             \(panel.level.rawValue)  (overlay sits at \(NSWindow.Level.screenSaver.rawValue))")

        guard fitting.width > 100, fitting.height > 20 else {
            print("  ✗ the view reports no usable size, so the panel is effectively invisible")
            return false
        }
        guard panel.frame.width > 100, panel.frame.height > 20 else {
            print("  ✗ the panel has no usable frame")
            return false
        }
        // The bug this catches: `isFloatingPanel = true` silently resets the level to
        // .floating (3), putting the bar underneath the overlay where it cannot be seen.
        guard panel.level.rawValue > NSWindow.Level.screenSaver.rawValue else {
            print("  ✗ the panel sits below the overlay, so it is hidden behind the capture")
            return false
        }

        bar.frame = CGRect(origin: .zero, size: fitting)
        bar.layoutSubtreeIfNeeded()

        // Cannot simulate a click offscreen, but an unwired button is the other way the bar
        // silently does nothing — so at least assert every one of them has a target.
        let buttons = bar.allButtons()
        let wired = buttons.filter { $0.target != nil && $0.action != nil }
        print("  buttons                  \(wired.count)/\(buttons.count) wired to an action")
        guard wired.count == buttons.count, buttons.count >= 16 else {
            print("  ✗ some controls would do nothing when clicked")
            return false
        }
        guard let rep = bar.bitmapImageRepForCachingDisplay(in: bar.bounds) else {
            print("  ✗ could not snapshot the toolbar")
            return false
        }
        bar.cacheDisplay(in: bar.bounds, to: rep)
        if let image = rep.cgImage {
            let url = outputDirectory.appendingPathComponent("toolbar.png")
            write(image, to: url)
            print("  \(image.width)×\(image.height)  → \(url.path)")
        }
        return true
    }

    /// One of each tool, laid out inside the selection.
    private static func sampleAnnotations(in selection: CGRect) -> [Annotation] {
        let red = PixelColor(red: 255, green: 59, blue: 48)
        let yellow = PixelColor(red: 255, green: 204, blue: 0)
        let blue = PixelColor(red: 10, green: 132, blue: 255)
        func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: selection.minX + dx, y: selection.minY + dy)
        }

        return [
            Annotation(tool: .pixelate, points: [point(20, 20), point(130, 70)], color: red, lineWidth: 10),
            Annotation(
                tool: .highlighter,
                points: [point(150, 40), point(250, 40), point(340, 55)],
                color: yellow,
                lineWidth: 16
            ),
            Annotation(tool: .rectangle, points: [point(20, 95), point(130, 165)], color: blue, lineWidth: 4),
            Annotation(tool: .ellipse, points: [point(150, 95), point(260, 165)], color: red, lineWidth: 4),
            Annotation(tool: .arrow, points: [point(280, 100), point(390, 170)], color: red, lineWidth: 4),
            Annotation(
                tool: .pen,
                points: (0...24).map { step in
                    let t = CGFloat(step) / 24
                    return point(25 + t * 160, 195 + sin(t * 8) * 18)
                },
                color: blue,
                lineWidth: 3
            ),
            Annotation(tool: .line, points: [point(200, 185), point(300, 215)], color: yellow, lineWidth: 3),
            Annotation(tool: .text, points: [point(210, 225)], color: red, lineWidth: 20, text: "Tiếng Việt ✓"),
        ]
    }

    /// The live preview and the exported file go through the same renderer, so the inside
    /// of the selection must match. Anything else means the two paths have drifted.
    private static func compareExportAgainstPreview(
        shot: DisplayShot,
        shots: [DisplayShot],
        selection: CGRect,
        marks: [Annotation],
        outputDirectory: URL
    ) -> Bool {
        guard let cropped = ImageCompositor.crop(globalRect: selection, from: shots) else {
            print("✗ compositor returned nil")
            return false
        }
        let scale = ScreenGeometry.renderScale(forGlobalRect: selection, among: shots.map(\.geometry))
        guard
            let exported = AnnotationRenderer.flatten(
                marks,
                onto: cropped,
                cropRect: selection,
                scale: scale
            )
        else {
            print("✗ flatten returned nil")
            return false
        }

        let exportURL = outputDirectory.appendingPathComponent("export-annotated.png")
        write(exported, to: exportURL)
        print("  \(exported.width)×\(exported.height)  → \(exportURL.path)  (what gets saved)")

        // The same region straight out of the preview render, with no dim over it.
        guard
            let previewFull = render(
                shot: shot,
                selection: selection,
                pointer: nil,
                isSettled: true,
                annotations: marks
            ),
            let previewInside = crop(previewFull, to: selection, shot: shot)
        else {
            print("✗ could not isolate the preview's selection interior")
            return false
        }

        guard
            previewInside.width == exported.width,
            previewInside.height == exported.height
        else {
            print("  ✗ preview \(previewInside.width)×\(previewInside.height) vs export"
                + " \(exported.width)×\(exported.height) — sizes differ")
            return false
        }

        let difference = SelfCheck.meanAbsoluteDifference(previewInside, exported)
        print(String(format: "  preview vs export mean difference %.2f / 255", difference))

        // Non-zero but tiny: the preview draws the border and handles over the very edge
        // of the selection, and the two paths round subpixel geometry independently.
        guard difference < 6 else {
            print("  ✗ the preview and the exported file disagree")
            return false
        }

        return reportOCR(on: cropped)
    }

    /// Exercises the OCR path on real screen text and reports which languages Vision
    /// actually offers on this machine — the Vietnamese model is not present on every
    /// macOS version, and `OCRService` silently falls back to English when it is missing.
    private static func reportOCR(on image: CGImage) -> Bool {
        let languages = OCRService.languageReport()
        print("\nOCR")
        print("  using: \(languages.chosen.joined(separator: ", "))")
        print("  Vision offers \(languages.available.count) languages here")
        if !languages.chosen.contains(where: { $0.hasPrefix("vi") }) {
            print("  ✗ no Vietnamese model — accented text will come back mangled")
            return false
        }

        do {
            let text = try OCRService.recognizeText(inSync: image)
            let lines = text.split(separator: "\n")
            print("  screen text: \(lines.count) lines, first: \(lines.first ?? "—")")
        } catch {
            print("  ✗ screen text: \(error.localizedDescription)")
            return false
        }

        // A synthetic sample, so the accent test does not depend on whatever happens to be
        // on screen. It also exercises the text tool's own glyph rendering.
        let expected = "Kiểm tra tiếng Việt có dấu"
        guard let sample = vietnameseSample(expected) else {
            print("  ✗ could not build the Vietnamese sample")
            return false
        }

        do {
            let read = try OCRService.recognizeText(inSync: sample).trimmingCharacters(in: .whitespacesAndNewlines)
            print("  expected:  \(expected)")
            print("  recognised: \(read)")
            guard read == expected else {
                print("  ✗ Vietnamese round-trip does not match")
                return false
            }
        } catch {
            print("  ✗ Vietnamese sample: \(error.localizedDescription)")
            return false
        }

        print("\n✓ chrome rendered, preview matches export, OCR reads Vietnamese")
        return true
    }

    /// Black text on white, drawn through the annotation renderer at Retina scale.
    private static func vietnameseSample(_ text: String) -> CGImage? {
        let scale: CGFloat = 2
        let bounds = CGRect(x: 0, y: 0, width: 520, height: 90)

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: Int(bounds.width * scale),
                height: Int(bounds.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale))

        AnnotationRenderer.draw(
            [
                Annotation(
                    tool: .text,
                    points: [CGPoint(x: 20, y: 58)],
                    color: PixelColor(red: 0, green: 0, blue: 0),
                    lineWidth: 30,
                    text: text
                )
            ],
            in: context,
            transform: AnnotationRenderer.transform(origin: .zero, scale: scale)
        )

        return context.makeImage()
    }

    /// Composites the frozen bitmap and the chrome view into one image at native scale.
    ///
    /// The chrome cannot simply be asked to cache its display: the screenshot lives in
    /// the root view's backing *layer*, which `cacheDisplay(in:to:)` does not include. So
    /// the bitmap is drawn first and the view is rendered on top of it.
    private static func render(
        shot: DisplayShot,
        selection: CGRect,
        pointer: CGPoint?,
        isSettled: Bool,
        annotations: [Annotation]
    ) -> CGImage? {
        let pointSize = shot.geometry.frame.size
        let pixelSize = shot.geometry.pixelSize

        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(pixelSize.width),
                pixelsHigh: Int(pixelSize.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else { return nil }

        // Declaring the rep's size in *points* makes the graphics context scale, so the
        // chrome draws at Retina resolution using the same point coordinates as on screen.
        rep.size = pointSize

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        let chrome = SelectionChromeView(shot: shot)
        chrome.frame = CGRect(origin: .zero, size: pointSize)
        chrome.selection = selection
        chrome.pointer = pointer
        chrome.isSettled = isSettled
        chrome.annotations = annotations

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.draw(shot.image, in: CGRect(origin: .zero, size: pointSize))
        chrome.displayIgnoringOpacity(chrome.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()

        return rep.cgImage
    }

    private static func crop(_ image: CGImage, to globalRect: CGRect, shot: DisplayShot) -> CGImage? {
        let pixels = ScreenGeometry.pixelRect(forGlobalRect: globalRect, in: shot.geometry)
        guard let clamped = ScreenGeometry.clamped(pixels, toPixelSizeOf: shot.geometry) else {
            return nil
        }
        return image.cropping(to: clamped)
    }

    private static func write(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
