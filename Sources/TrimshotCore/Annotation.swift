import CoreGraphics
import Foundation

public enum AnnotationTool: String, CaseIterable, Sendable {
    case pen
    case line
    case arrow
    case rectangle
    case ellipse
    case highlighter
    case text
    case pixelate
    case image

    /// Freehand tools accumulate every point; the rest only need start and end.
    public var isFreehand: Bool { self == .pen || self == .highlighter }

    /// Tools that obscure rather than mark — they ignore the stroke colour.
    public var isRedaction: Bool { self == .pixelate }

    /// Tools that place a bitmap instead of drawing with the stroke colour.
    public var carriesImage: Bool { self == .image }
}

/// A bitmap carried by an annotation.
///
/// `CGImage` is immutable but neither `Sendable` nor `Equatable`, and `Annotation` needs to be
/// both — the chrome view compares drafts to decide whether to redraw. Identity comparison is
/// the right semantics here: two annotations hold the same picture only if they hold the same
/// object.
public struct AnnotationImage: @unchecked Sendable, Equatable {
    public let cgImage: CGImage

    public init(_ cgImage: CGImage) {
        self.cgImage = cgImage
    }

    public static func == (lhs: AnnotationImage, rhs: AnnotationImage) -> Bool {
        lhs.cgImage === rhs.cgImage
    }
}

/// One mark on the capture. Points are in **AppKit global points**, the same space the
/// selection lives in, so annotations survive the selection being moved or resized.
public struct Annotation: Sendable, Equatable {
    public var tool: AnnotationTool
    public var points: [CGPoint]
    public var color: PixelColor
    public var lineWidth: CGFloat
    public var text: String
    /// Set only for the image tool.
    public var image: AnnotationImage?

    public init(
        tool: AnnotationTool,
        points: [CGPoint],
        color: PixelColor,
        lineWidth: CGFloat,
        text: String = "",
        image: AnnotationImage? = nil
    ) {
        self.tool = tool
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.image = image
    }

    /// Start and end of a two-point tool.
    public var start: CGPoint { points.first ?? .zero }
    public var end: CGPoint { points.last ?? .zero }

    /// The rect a shape tool spans, normalised so dragging in any direction works.
    public var boundingRect: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            maxX = Swift.max(maxX, point.x)
            minY = Swift.min(minY, point.y)
            maxY = Swift.max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether this annotation has enough substance to keep once the drag ends.
    /// Filters out the stray one-pixel marks a click produces.
    public var isMeaningful: Bool {
        switch tool {
        case .image:
            // A placed bitmap needs both a picture and somewhere to put it.
            image != nil && (boundingRect.width >= 2 || boundingRect.height >= 2)
        case .text:
            !text.isEmpty
        case .pen, .highlighter:
            points.count >= 2
        default:
            boundingRect.width >= 2 || boundingRect.height >= 2
        }
    }
}

extension Annotation {
    /// The same mark shifted by a delta.
    public func moved(dx: CGFloat, dy: CGFloat) -> Annotation {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return copy
    }

    /// The same mark rescaled so its bounding rect becomes `rect`.
    ///
    /// Every point is remapped proportionally rather than the two corners being overwritten,
    /// so this works for a freehand stroke as well as a rectangle. A degenerate source rect
    /// has no proportions to preserve, so the mark is moved to the new origin instead of
    /// being divided by zero.
    public func resized(to rect: CGRect) -> Annotation {
        let old = boundingRect
        var copy = self
        guard old.width > 0, old.height > 0 else {
            copy.points = points.map { _ in rect.origin }
            return copy
        }
        copy.points = points.map { point in
            CGPoint(
                x: rect.minX + (point.x - old.minX) / old.width * rect.width,
                y: rect.minY + (point.y - old.minY) / old.height * rect.height
            )
        }
        return copy
    }

    /// Whether a point lands on this mark, for picking it up with the mouse.
    ///
    /// Bounding-box hit testing is right for the tools that fill a rect — an image, a
    /// pixelated block. A line or a freehand stroke would need distance-to-stroke instead,
    /// which is why those are not pickable yet rather than being pickable and wrong.
    public var isPickable: Bool { tool == .image || tool == .pixelate }

    public func contains(_ point: CGPoint, tolerance: CGFloat = 2) -> Bool {
        isPickable && boundingRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
}

/// The annotation list plus undo/redo.
///
/// Redo is dropped as soon as a new mark is added, which is what every drawing tool
/// does and avoids a confusing branching history.
public struct AnnotationStore: Sendable {
    public private(set) var annotations: [Annotation] = []
    private var undone: [Annotation] = []

    public init() {}

    public var canUndo: Bool { !annotations.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }
    public var isEmpty: Bool { annotations.isEmpty }

    public mutating func add(_ annotation: Annotation) {
        annotations.append(annotation)
        undone.removeAll()
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let last = annotations.popLast() else { return false }
        undone.append(last)
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let last = undone.popLast() else { return false }
        annotations.append(last)
        return true
    }

    /// Replaces one mark in place.
    ///
    /// Deliberately does not touch the undo stack: a drag would otherwise push a step per
    /// mouse-move. The consequence is that undo removes the mark rather than reverting the
    /// move, which is the behaviour most editors settle on for a first pass.
    public mutating func replace(at index: Int, with annotation: Annotation) {
        guard annotations.indices.contains(index) else { return }
        annotations[index] = annotation
    }

    public mutating func remove(at index: Int) {
        guard annotations.indices.contains(index) else { return }
        annotations.remove(at: index)
        undone.removeAll()
    }

    /// The topmost pickable mark under a point — topmost because later marks draw over
    /// earlier ones, so that is the one a click means.
    public func indexOfMark(at point: CGPoint) -> Int? {
        annotations.lastIndex { $0.contains(point) }
    }

    public mutating func removeAll() {
        annotations.removeAll()
        undone.removeAll()
    }
}
