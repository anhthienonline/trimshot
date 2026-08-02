import CoreGraphics
import Foundation

/// An RGB sample read straight out of a captured bitmap.
public struct PixelColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var hexString: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    public var rgbString: String {
        "rgb(\(red), \(green), \(blue))"
    }

    /// Whether to draw labels in black or white on top of this color.
    /// Uses the WCAG relative-luminance coefficients.
    public var isLight: Bool {
        let luminance = 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
        return luminance > 140
    }
}

extension CGImage {
    /// Reads one pixel, given in the image's own pixel coordinates (origin top-left).
    ///
    /// Redraws the single pixel into a known 8-bit RGBA buffer rather than poking at
    /// `dataProvider`, because ScreenCaptureKit hands back BGRA — and HDR displays hand
    /// back half-float RGhA — so the raw bytes are not reliably laid out.
    public func pixelColor(atX x: Int, y: Int) -> PixelColor? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }

        // The context keeps this pointer alive for as long as it draws, so it has to
        // outlive any closure scope — hence a manual allocation rather than an Array.
        let pixel = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        pixel.initialize(repeating: 0, count: 4)
        defer { pixel.deallocate() }

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: pixel,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        // Shift the image so the pixel of interest lands on the 1×1 canvas. The canvas
        // is Y-up while image coordinates are Y-down, hence `height - 1 - y`.
        context.draw(
            self,
            in: CGRect(x: -x, y: -(height - 1 - y), width: width, height: height)
        )

        return PixelColor(red: pixel[0], green: pixel[1], blue: pixel[2])
    }
}
