import CoreGraphics
import Foundation

public enum Axis: Sendable {
    case horizontal
    case vertical
}

/// A run of near-uniform pixels along one axis, in image pixel coordinates.
public struct EdgeSpan: Equatable, Sendable {
    /// First pixel of the run.
    public let start: Int
    /// Last pixel of the run, inclusive.
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public var length: Int { end - start + 1 }
}

/// Finds the gap the cursor is sitting in by walking outward until the picture changes.
///
/// This is how a spacing check works in practice: you point at the space between a button and
/// its label and want the number. Rather than asking the user to drag between two edges by
/// eye — which defeats the point of a measuring tool — the span is detected from the frozen
/// bitmap, so the answer is derived from pixels instead of from aim.
public enum EdgeDetector {

    /// Luminance of one row or column, 0…1, in a single pass.
    ///
    /// Reading pixel by pixel would mean thousands of `CGContext` setups per cursor move.
    /// One N×1 draw is a single operation, so a full-width scan costs about the same as one
    /// pixel read.
    public static func luminanceLine(in image: CGImage, axis: Axis, index: Int) -> [Double]? {
        let count = axis == .horizontal ? image.width : image.height
        guard count > 0 else { return nil }
        switch axis {
        case .horizontal: guard index >= 0, index < image.height else { return nil }
        case .vertical: guard index >= 0, index < image.width else { return nil }
        }

        let width = axis == .horizontal ? count : 1
        let height = axis == .horizontal ? 1 : count
        let bytesPerRow = width * 4

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerRow * height)
        buffer.initialize(repeating: 0, count: bytesPerRow * height)
        defer { buffer.deallocate() }

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        // Shift the image so the wanted row or column lands on the strip. The context is
        // Y-up while image coordinates are Y-down, hence `height - 1 - index`.
        let offsetY: CGFloat
        switch axis {
        case .horizontal: offsetY = -CGFloat(image.height - 1 - index)
        case .vertical: offsetY = 0
        }
        let offsetX: CGFloat = axis == .horizontal ? 0 : -CGFloat(index)
        context.draw(
            image,
            in: CGRect(x: offsetX, y: offsetY, width: CGFloat(image.width), height: CGFloat(image.height))
        )

        var line = [Double](repeating: 0, count: count)
        for i in 0..<count {
            // No flip on read-back. A CGBitmapContext stores its rows top-first in memory
            // even though its coordinate origin is bottom-left, and the image above is drawn
            // upright — so buffer row i already is image row i. Reversing here inverted every
            // vertical measurement.
            let pixel = axis == .horizontal ? i * 4 : i * bytesPerRow
            let r = Double(buffer[pixel])
            let g = Double(buffer[pixel + 1])
            let b = Double(buffer[pixel + 2])
            line[i] = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        }
        return line
    }

    /// The near-uniform run containing `origin`, found by walking both ways until luminance
    /// departs from the starting value by more than `threshold`.
    ///
    /// `threshold` is in luminance units, 0…1. 0.10 ignores gradients and anti-aliasing while
    /// still stopping at any edge a person would call an edge.
    public static func span(
        in line: [Double],
        from origin: Int,
        threshold: Double = 0.10
    ) -> EdgeSpan? {
        guard !line.isEmpty, origin >= 0, origin < line.count else { return nil }

        let reference = line[origin]
        var start = origin
        while start - 1 >= 0, abs(line[start - 1] - reference) <= threshold {
            start -= 1
        }
        var end = origin
        while end + 1 < line.count, abs(line[end + 1] - reference) <= threshold {
            end += 1
        }
        return EdgeSpan(start: start, end: end)
    }

    /// Where a pixel span lands in a display's own view coordinates, ready to draw.
    ///
    /// Two things are easy to get wrong here, and both are silent: a span's `end` is an
    /// *inclusive* pixel index, so the run covers `start … end + 1` in continuous
    /// coordinates — without that a 40 px gap draws 39 px wide. And image rows count
    /// downward while view coordinates count upward, so a vertical span has to be flipped.
    public static func viewSpan(
        for span: EdgeSpan,
        axis: Axis,
        in display: DisplayGeometry
    ) -> (from: CGFloat, to: CGFloat) {
        let scale = display.scale
        let near = CGFloat(span.start) / scale
        let far = CGFloat(span.end + 1) / scale
        switch axis {
        case .horizontal:
            return (near, far)
        case .vertical:
            let height = display.frame.height
            return (height - near, height - far)
        }
    }

    /// Convenience: the horizontal and vertical runs through one pixel of an image.
    public static func spans(
        in image: CGImage,
        atX x: Int,
        y: Int,
        threshold: Double = 0.10
    ) -> (horizontal: EdgeSpan?, vertical: EdgeSpan?) {
        let row = luminanceLine(in: image, axis: .horizontal, index: y)
        let column = luminanceLine(in: image, axis: .vertical, index: x)
        return (
            row.flatMap { span(in: $0, from: x, threshold: threshold) },
            column.flatMap { span(in: $0, from: y, threshold: threshold) }
        )
    }
}
