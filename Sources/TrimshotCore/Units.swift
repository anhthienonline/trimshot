import CoreGraphics
import Foundation

/// How every number the app shows is formatted.
///
/// Trimshot reports **CSS pixels** — the logical unit Figma, CSS and the rest of design work
/// in. On a 2× display a 420 px frame occupies 840 device pixels, and a saved PNG really is
/// 840 wide; but nobody designing is thinking in 840, so reporting device pixels would mean
/// dividing by two on every reading. macOS's own screenshot tool reports device pixels, which
/// is exactly the friction this avoids.
///
/// Everything routes through here rather than formatting in place, because a tool whose whole
/// claim is that the numbers are exact cannot afford one label in a different unit from the
/// rest. AppKit points are already CSS pixels, so there is no conversion — the discipline is
/// in *not* multiplying by the scale factor anywhere.
public enum Units {

    /// `377 px`
    public static func length(_ points: CGFloat) -> String {
        "\(Int(points.rounded())) px"
    }

    /// `420 × 240 px`
    public static func size(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px"
    }

    /// `1284, 662` — a position, where the unit is obvious from context and the label would
    /// only crowd a small readout.
    public static func point(_ point: CGPoint) -> String {
        "\(Int(point.x.rounded())), \(Int(point.y.rounded()))"
    }

    /// The device-pixel size of an exported bitmap, for the rare place that means the file
    /// rather than the screen.
    public static func deviceSize(width: Int, height: Int) -> String {
        "\(width) × \(height)"
    }
}
