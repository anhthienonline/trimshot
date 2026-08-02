import CoreGraphics
import Foundation

/// The eight grab points around a settled selection.
///
/// Everything here is in **AppKit global points**, so `top` means the higher `maxY`
/// edge, not the lower one.
public enum SelectionHandle: CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    public func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .top: CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// The rect that results from dragging this handle to `point`.
    ///
    /// Dragging an edge past its opposite simply flips the rect rather than producing a
    /// negative size, which is what every other selection UI on the platform does.
    public func resize(_ rect: CGRect, to point: CGPoint) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch self {
        case .topLeft:
            minX = point.x
            maxY = point.y
        case .top:
            maxY = point.y
        case .topRight:
            maxX = point.x
            maxY = point.y
        case .right:
            maxX = point.x
        case .bottomRight:
            maxX = point.x
            minY = point.y
        case .bottom:
            minY = point.y
        case .bottomLeft:
            minX = point.x
            minY = point.y
        case .left:
            minX = point.x
        }

        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        ).integral
    }

    /// Which handle sits under `point`, if any. `tolerance` is the grab radius.
    public static func hitTest(
        _ point: CGPoint,
        in rect: CGRect,
        tolerance: CGFloat = 9
    ) -> SelectionHandle? {
        // Corners take priority: at small selection sizes their grab areas overlap the
        // edge midpoints, and a corner drag is almost always what was meant.
        let ordered: [SelectionHandle] = [
            .topLeft, .topRight, .bottomLeft, .bottomRight,
            .top, .right, .bottom, .left,
        ]
        return ordered.first { handle in
            let anchor = handle.point(in: rect)
            return abs(anchor.x - point.x) <= tolerance && abs(anchor.y - point.y) <= tolerance
        }
    }
}

extension CGRect {
    /// Moves the rect without changing its size. Used for dragging a settled selection
    /// and for arrow-key nudges.
    public func offsetBy(dx: CGFloat, dy: CGFloat, clampedTo bounds: CGRect?) -> CGRect {
        var moved = offsetBy(dx: dx, dy: dy)
        guard let bounds else { return moved }

        if moved.minX < bounds.minX { moved.origin.x = bounds.minX }
        if moved.minY < bounds.minY { moved.origin.y = bounds.minY }
        if moved.maxX > bounds.maxX { moved.origin.x = bounds.maxX - moved.width }
        if moved.maxY > bounds.maxY { moved.origin.y = bounds.maxY - moved.height }
        return moved
    }
}
