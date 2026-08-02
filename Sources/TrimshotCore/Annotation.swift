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

    public mutating func removeAll() {
        annotations.removeAll()
        undone.removeAll()
    }
}
