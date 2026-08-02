import CoreGraphics
import CoreText
import Foundation

public enum AnnotationRenderer {

    /// Maps AppKit global points into a destination context whose origin is
    /// `origin` (in global points) and whose unit is `scale` pixels per point.
    ///
    /// Used for both jobs: the live preview passes `scale: 1` and the display's origin,
    /// the export passes the crop origin and the Retina scale. One transform means one
    /// drawing implementation, so the preview cannot drift from the saved file.
    public static func transform(origin: CGPoint, scale: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: -origin.x, y: -origin.y)
    }

    /// Centres `size` inside `rect` at its own aspect ratio, letterboxing rather than
    /// stretching. A placed screenshot distorted to fit whatever rectangle the user happened
    /// to drag is worse than useless in a tool people trust for measurements.
    public static func fit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.midX - fitted.width / 2,
            y: rect.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// Draws annotations into `context`, which must be in a Y-up coordinate space.
    ///
    /// `pixelateSource` supplies the bitmap the redaction tool samples; without it,
    /// pixelate annotations fall back to a solid block.
    public static func draw(
        _ annotations: [Annotation],
        in context: CGContext,
        transform: CGAffineTransform,
        pixelateSource: (image: CGImage, geometry: DisplayGeometry)? = nil
    ) {
        guard !annotations.isEmpty else { return }

        for annotation in annotations {
            // Pixelate resamples a bitmap, so it works in device pixels and cannot be
            // drawn through the same transformed CTM as the vector tools.
            if annotation.tool == .pixelate {
                drawPixelate(annotation, in: context, transform: transform, source: pixelateSource)
                continue
            }
            if annotation.tool == .image {
                drawPlacedImage(annotation, in: context, transform: transform)
                continue
            }

            context.saveGState()
            context.concatenate(transform)
            // Everything below is in global points; CG scales stroke widths and glyphs
            // along with the CTM.
            context.setLineCap(.round)
            context.setLineJoin(.round)
            draw(annotation, in: context)
            context.restoreGState()
        }
    }

    // MARK: - Vector tools

    private static func draw(_ annotation: Annotation, in context: CGContext) {
        let color = cgColor(annotation.color, alpha: annotation.tool == .highlighter ? 0.35 : 1)

        switch annotation.tool {
        case .pen, .highlighter:
            guard annotation.points.count >= 2 else { return }
            context.setStrokeColor(color)
            context.setLineWidth(annotation.lineWidth)
            context.addLines(between: annotation.points)
            context.strokePath()

        case .line:
            context.setStrokeColor(color)
            context.setLineWidth(annotation.lineWidth)
            context.addLines(between: [annotation.start, annotation.end])
            context.strokePath()

        case .arrow:
            drawArrow(annotation, color: color, in: context)

        case .rectangle:
            context.setStrokeColor(color)
            context.setLineWidth(annotation.lineWidth)
            context.stroke(annotation.boundingRect)

        case .ellipse:
            context.setStrokeColor(color)
            context.setLineWidth(annotation.lineWidth)
            context.strokeEllipse(in: annotation.boundingRect)

        case .text:
            drawText(annotation, color: color, in: context)

        case .pixelate, .image:
            break  // handled separately — both draw bitmaps, not strokes
        }
    }

    /// Draws a placed bitmap into the rect it was dragged out over.
    private static func drawPlacedImage(
        _ annotation: Annotation,
        in context: CGContext,
        transform: CGAffineTransform
    ) {
        guard let image = annotation.image?.cgImage else { return }
        let destination = annotation.boundingRect.applying(transform)
        guard destination.width >= 1, destination.height >= 1 else { return }

        let size = CGSize(width: image.width, height: image.height)
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: fit(size, in: destination))
        context.restoreGState()
    }

    private static func drawArrow(_ annotation: Annotation, color: CGColor, in context: CGContext) {
        let start = annotation.start
        let end = annotation.end
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1 else { return }

        // Head scales with the stroke so thin arrows do not get a clumsy head, but stops
        // growing past a third of the shaft on very short drags.
        let headLength = min(annotation.lineWidth * 4.5, length * 0.34)
        let headHalfWidth = headLength * 0.55
        let ux = dx / length
        let uy = dy / length
        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)

        context.setStrokeColor(color)
        context.setLineWidth(annotation.lineWidth)
        // Stop the shaft inside the head so the round cap does not poke out of the tip.
        context.addLines(between: [start, CGPoint(x: base.x + ux * headLength * 0.35,
                                                  y: base.y + uy * headLength * 0.35)])
        context.strokePath()

        context.setFillColor(color)
        context.move(to: end)
        context.addLine(to: CGPoint(x: base.x - uy * headHalfWidth, y: base.y + ux * headHalfWidth))
        context.addLine(to: CGPoint(x: base.x + uy * headHalfWidth, y: base.y - ux * headHalfWidth))
        context.closePath()
        context.fillPath()
    }

    /// For text annotations `lineWidth` carries the font size in points.
    private static func drawText(_ annotation: Annotation, color: CGColor, in context: CGContext) {
        guard !annotation.text.isEmpty else { return }

        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, annotation.lineWidth, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        guard
            let attributed = CFAttributedStringCreate(
                nil,
                annotation.text as CFString,
                attributes as CFDictionary
            )
        else { return }

        let line = CTLineCreateWithAttributedString(attributed)
        context.textMatrix = .identity
        // `start` is the point clicked, treated as the text's top-left, so the caret the
        // user saw and the committed glyphs line up.
        context.textPosition = CGPoint(
            x: annotation.start.x,
            y: annotation.start.y - CTFontGetAscent(font)
        )
        CTLineDraw(line, context)
    }

    // MARK: - Pixelate

    /// Redacts by downsampling the region and blowing it back up with nearest-neighbour
    /// sampling — the mosaic look, and unlike a blur it is not reversible.
    private static func drawPixelate(
        _ annotation: Annotation,
        in context: CGContext,
        transform: CGAffineTransform,
        source: (image: CGImage, geometry: DisplayGeometry)?
    ) {
        let globalRect = annotation.boundingRect
        guard globalRect.width >= 1, globalRect.height >= 1 else { return }

        let destination = globalRect.applying(transform)
        guard destination.width >= 1, destination.height >= 1 else { return }

        guard let source else {
            // No bitmap to sample: fall back to a solid block rather than leaving the
            // region readable.
            context.setFillColor(cgColor(annotation.color, alpha: 1))
            context.fill(destination)
            return
        }

        let sourcePixels = ScreenGeometry.pixelRect(forGlobalRect: globalRect, in: source.geometry)
        guard
            let clamped = ScreenGeometry.clamped(sourcePixels, toPixelSizeOf: source.geometry),
            let crop = source.image.cropping(to: clamped)
        else { return }

        // `lineWidth` doubles as the mosaic block size in points.
        let block = max(4, annotation.lineWidth)
        let columns = max(1, Int((globalRect.width / block).rounded()))
        let rows = max(1, Int((globalRect.height / block).rounded()))

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let small = CGContext(
                data: nil,
                width: columns,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return }

        small.interpolationQuality = .medium
        small.draw(crop, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let mosaic = small.makeImage() else { return }

        context.saveGState()
        context.interpolationQuality = .none
        context.draw(mosaic, in: destination)
        context.restoreGState()
    }

    // MARK: - Helpers

    private static func cgColor(_ color: PixelColor, alpha: CGFloat) -> CGColor {
        CGColor(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: alpha
        )
    }

    /// Bakes annotations into a cropped capture, ready to copy or save.
    ///
    /// Draws at the crop's own pixel resolution rather than rasterising the on-screen
    /// view, so strokes and text stay sharp on Retina.
    public static func flatten(
        _ annotations: [Annotation],
        onto image: CGImage,
        cropRect: CGRect,
        scale: CGFloat
    ) -> CGImage? {
        guard !annotations.isEmpty else { return image }

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

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let geometry = DisplayGeometry(displayID: 0, frame: cropRect, scale: scale)
        draw(
            annotations,
            in: context,
            transform: transform(origin: cropRect.origin, scale: scale),
            pixelateSource: (image: image, geometry: geometry)
        )

        return context.makeImage()
    }
}
