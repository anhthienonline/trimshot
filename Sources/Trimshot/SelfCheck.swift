import AppKit
import TrimshotCore

/// `Trimshot --self-check [outputDir]`
///
/// Exercises the whole capture path without a human dragging a rectangle, and — the
/// point of the exercise — cross-checks the result against macOS's own `screencapture`
/// for the identical region. A flipped Y axis or a halved Retina scale shows up as a
/// large pixel difference here instead of as a wrong screenshot later.
@MainActor
enum SelfCheck {

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
            print("  Grant it under Privacy & Security › Screen & System Audio Recording,")
            print("  then run the self-check again.")
            return false
        }

        let shots: [DisplayShot]
        do {
            shots = try await ScreenCapturer.captureAllDisplays()
        } catch {
            print("✗ capture failed: \(error.localizedDescription)")
            return false
        }

        print("Displays")
        var sizesOK = true
        for shot in shots {
            let g = shot.geometry
            let expected = g.pixelSize
            let actual = CGSize(width: shot.image.width, height: shot.image.height)
            let match = abs(expected.width - actual.width) < 1 && abs(expected.height - actual.height) < 1
            sizesOK = sizesOK && match
            print(
                "  \(match ? "✓" : "✗") id \(g.displayID)  frame \(short(g.frame))  @\(g.scale)x"
                    + "  bitmap \(Int(actual.width))×\(Int(actual.height))"
                    + (match ? "" : "  expected \(Int(expected.width))×\(Int(expected.height))")
            )
        }

        guard let main = shots.first(where: { $0.geometry.frame.origin == .zero }) ?? shots.first else {
            print("✗ no display to test against")
            return false
        }

        // A band across the top of the main screen: it contains the menu bar, so it is
        // strongly asymmetric vertically — an upside-down crop cannot score well.
        let frame = main.geometry.frame
        let region = CGRect(
            x: frame.minX + 100,
            y: frame.maxY - 400,
            width: 600,
            height: 300
        )

        guard let ours = ImageCompositor.crop(globalRect: region, from: shots) else {
            print("✗ compositor returned nil for \(short(region))")
            return false
        }

        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let oursURL = outputDirectory.appendingPathComponent("selfcheck-ours.png")
        let referenceURL = outputDirectory.appendingPathComponent("selfcheck-screencapture.png")
        write(ours, to: oursURL)

        guard let reference = captureReference(region: region, mainFrame: frame, to: referenceURL) else {
            print("✗ could not produce a `screencapture` reference to compare against")
            return false
        }

        print("\nCrop \(short(region))")
        print("  ours        \(ours.width)×\(ours.height)  → \(oursURL.path)")
        print("  screencapture \(reference.width)×\(reference.height)  → \(referenceURL.path)")

        guard ours.width == reference.width, ours.height == reference.height else {
            print("  ✗ size mismatch — the Retina scale factor is being applied wrongly")
            return false
        }

        let difference = meanAbsoluteDifference(ours, reference)
        let flipped = meanAbsoluteDifference(ours, flip(reference) ?? reference)
        print(String(format: "  mean pixel difference %.2f / 255", difference))
        print(String(format: "  same, against a vertically flipped reference: %.2f", flipped))

        // 8/255 tolerates cursor movement, a blinking caret and colour-space rounding;
        // a genuine orientation bug lands an order of magnitude above it.
        guard difference < 8 else {
            print("  ✗ crop does not match macOS's own capture of the same region")
            if flipped < difference {
                print("    (it matches better upside down — the Y flip is inverted)")
            }
            return false
        }

        print("\n\(sizesOK ? "✓" : "✗") self-check \(sizesOK ? "passed" : "failed")")
        return sizesOK
    }

    // MARK: - Reference capture

    /// Shells out to `screencapture -R`, which takes CoreGraphics global coordinates:
    /// origin at the **top-left** of the main display, Y down, in points.
    private static func captureReference(
        region: CGRect,
        mainFrame: CGRect,
        to url: URL
    ) -> CGImage? {
        let cgY = mainFrame.height - region.maxY
        let argument = "\(Int(region.minX)),\(Int(cgY)),\(Int(region.width)),\(Int(region.height))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-R", argument, url.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("  screencapture failed to launch: \(error.localizedDescription)")
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return image
    }

    // MARK: - Comparison

    /// Mean absolute difference across RGB, 0–255. Both images are redrawn into the
    /// same 8-bit sRGB layout first so pixel formats cannot skew the result.
    static func meanAbsoluteDifference(_ a: CGImage, _ b: CGImage) -> Double {
        guard
            a.width == b.width, a.height == b.height,
            let bytesA = rgbaBytes(a), let bytesB = rgbaBytes(b)
        else { return .infinity }

        var total = 0.0
        var samples = 0
        // Every 4th pixel: plenty for a sanity check, and keeps a 5K crop instant.
        for index in stride(from: 0, to: min(bytesA.count, bytesB.count) - 3, by: 16) {
            for channel in 0..<3 {
                total += abs(Double(bytesA[index + channel]) - Double(bytesB[index + channel]))
                samples += 1
            }
        }
        return samples == 0 ? .infinity : total / Double(samples)
    }

    private static func rgbaBytes(_ image: CGImage) -> [UInt8]? {
        let bytesPerRow = image.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? bytes : nil
    }

    private static func flip(_ image: CGImage) -> CGImage? {
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    // MARK: - Output

    private static func write(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    private static func short(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.width))×\(Int(rect.height)))"
    }
}
