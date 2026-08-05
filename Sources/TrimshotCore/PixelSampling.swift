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
