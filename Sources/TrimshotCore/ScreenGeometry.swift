import CoreGraphics
import Foundation

/// A display, described in the one coordinate space this app reasons in:
/// **AppKit global points** — origin at the bottom-left of the main screen, Y up.
///
/// Kept as a plain value (not an `NSScreen`) so the geometry math below is checkable
/// without real hardware. Building one from an `NSScreen` lives in `ScreenCapturer`.
public struct DisplayGeometry: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    /// Frame in AppKit global points.
    public let frame: CGRect
    /// `NSScreen.backingScaleFactor` — 2.0 on Retina, 1.0 on most external monitors.
    public let scale: CGFloat

    public init(displayID: CGDirectDisplayID, frame: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.frame = frame
        self.scale = scale
    }

    public var pixelSize: CGSize {
        CGSize(width: frame.width * scale, height: frame.height * scale)
    }
}

/// Conversions between AppKit global points and per-display pixels.
///
/// This is the single riskiest piece of the app, so it lives alone and is covered by
/// `TrimshotChecks`. Three coordinate systems collide here:
///
/// - **AppKit global points** — origin bottom-left of the main screen, Y **up**.
///   `NSScreen.frame` and `NSWindow.convertPoint(toScreen:)` speak this.
/// - **Display-local pixels** — origin top-left of one display, Y **down**.
///   The `CGImage` from ScreenCaptureKit is in this space.
/// - Displays may sit at negative coordinates (a monitor to the left of, or above,
///   the main screen) and may each have a different `scale`.
public enum ScreenGeometry {

    /// Maps a rect given in AppKit global points into pixel coordinates inside
    /// `display`'s captured bitmap (origin top-left, Y down).
    ///
    /// The result is *not* clipped to the bitmap — see `clamped(_:toPixelSizeOf:)`.
    public static func pixelRect(forGlobalRect rect: CGRect, in display: DisplayGeometry) -> CGRect {
        let localX = rect.minX - display.frame.minX
        // Flip Y: distance from the display's top edge down to the rect's top edge.
        let localY = display.frame.maxY - rect.maxY

        return CGRect(
            x: (localX * display.scale).rounded(),
            y: (localY * display.scale).rounded(),
            width: (rect.width * display.scale).rounded(),
            height: (rect.height * display.scale).rounded()
        )
    }

    /// Maps a point in AppKit global points to the pixel it lands on inside
    /// `display`'s bitmap (origin top-left, Y down).
    ///
    /// Floors rather than rounds: a cursor anywhere inside a pixel should report *that*
    /// pixel, which matters for the magnifier and the colour picker.
    public static func pixelPoint(
        forGlobalPoint point: CGPoint,
        in display: DisplayGeometry
    ) -> (x: Int, y: Int) {
        let localX = (point.x - display.frame.minX) * display.scale
        let localY = (display.frame.maxY - point.y) * display.scale
        return (Int(localX.rounded(.down)), Int(localY.rounded(.down)))
    }

    /// Inverse of `pixelRect(forGlobalRect:in:)`.
    public static func globalRect(forPixelRect rect: CGRect, in display: DisplayGeometry) -> CGRect {
        let width = rect.width / display.scale
        let height = rect.height / display.scale
        return CGRect(
            x: display.frame.minX + rect.minX / display.scale,
            y: display.frame.maxY - rect.minY / display.scale - height,
            width: width,
            height: height
        )
    }

    /// Clips a pixel rect to the bounds of the display's bitmap. Returns nil when the
    /// rect falls entirely outside — i.e. the selection doesn't touch this display.
    public static func clamped(_ pixelRect: CGRect, toPixelSizeOf display: DisplayGeometry) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: display.pixelSize)
        let clipped = pixelRect.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return clipped
    }

    /// Displays the selection actually overlaps, in the order given.
    public static func displays(
        intersecting rect: CGRect,
        among displays: [DisplayGeometry]
    ) -> [DisplayGeometry] {
        displays.filter {
            let overlap = $0.frame.intersection(rect)
            return !overlap.isNull && !overlap.isEmpty
        }
    }

    /// The scale to render a cross-display selection at.
    ///
    /// Uses the highest scale among the displays it touches, so dragging from a Retina
    /// screen onto a 1x monitor keeps the Retina half sharp instead of halving it.
    public static func renderScale(
        forGlobalRect rect: CGRect,
        among displays: [DisplayGeometry]
    ) -> CGFloat {
        Self.displays(intersecting: rect, among: displays).map(\.scale).max() ?? 1
    }

    /// Snaps a drag rect to whole points and guarantees a positive size, so dragging
    /// up-and-left produces the same rect as dragging down-and-right.
    public static func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        ).integral
    }
}
