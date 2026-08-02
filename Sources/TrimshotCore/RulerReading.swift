import CoreGraphics
import Foundation

/// A measurement between two points, the way Photoshop's ruler reports one: the direct
/// distance, its horizontal and vertical components, and the angle.
///
/// Points are in AppKit global points, so `dy` is positive upward. Photoshop's Y runs the
/// other way, which is why its angle for the same drag has the opposite sign — worth knowing
/// if you are comparing the two side by side.
public struct RulerReading: Equatable, Sendable {
    public let from: CGPoint
    public let to: CGPoint

    public init(from: CGPoint, to: CGPoint) {
        self.from = from
        self.to = to
    }

    /// Signed horizontal component. Photoshop calls this W.
    public var dx: CGFloat { to.x - from.x }

    /// Signed vertical component, positive upward. Photoshop calls this H.
    public var dy: CGFloat { to.y - from.y }

    /// Direct distance. Photoshop calls this D.
    public var distance: CGFloat { (dx * dx + dy * dy).squareRoot() }

    /// Degrees in (-180, 180], measured like a protractor: 0 along +x, positive turning
    /// counter-clockwise. Photoshop calls this A.
    public var angle: CGFloat {
        guard dx != 0 || dy != 0 else { return 0 }
        return atan2(dy, dx) * 180 / .pi
    }

    /// The corner a Photoshop-style ruler draws its two legs through: along x first, then y.
    public var elbow: CGPoint { CGPoint(x: to.x, y: from.y) }

    public var isMeaningful: Bool { distance >= 1 }

    /// Converts a length in points to whole pixels on a display of the given scale.
    public static func pixels(_ points: CGFloat, scale: CGFloat) -> Int {
        Int((points * scale).rounded())
    }
}
