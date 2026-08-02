import AppKit
import TrimshotCore

/// The loupe that follows the cursor: a zoomed pixel grid, the HEX value under the
/// crosshair, and the pixel coordinate.
///
/// It reads the same frozen bitmap that gets cropped, so what it reports is exactly what
/// ends up in the file — no resampling, no live-screen drift.
@MainActor
struct Magnifier {
    let shot: DisplayShot

    /// Odd, so there is a true centre pixel to put the crosshair on.
    private let sourcePixels = 15
    private let loupeSize: CGFloat = 132
    private let captionHeight: CGFloat = 38
    private let cursorGap: CGFloat = 20

    private var cellSize: CGFloat { loupeSize / CGFloat(sourcePixels) }

    /// - Parameters:
    ///   - globalPoint: cursor position in AppKit global points.
    ///   - viewPoint: the same position in the drawing view's coordinates.
    ///   - bounds: the view's bounds, used to keep the loupe on screen.
    func draw(globalPoint: CGPoint, viewPoint: CGPoint, in bounds: CGRect) {
        let pixel = ScreenGeometry.pixelPoint(forGlobalPoint: globalPoint, in: shot.geometry)
        let color = shot.image.pixelColor(atX: pixel.x, y: pixel.y)

        let frame = panelFrame(near: viewPoint, in: bounds)
        let loupeRect = CGRect(
            x: frame.minX,
            y: frame.maxY - loupeSize,
            width: loupeSize,
            height: loupeSize
        )

        drawPanelBackground(frame)
        drawZoomedPixels(around: pixel, in: loupeRect)
        drawGrid(in: loupeRect)
        drawCentreCell(in: loupeRect)
        drawCaption(
            color: color,
            pixel: pixel,
            in: CGRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: captionHeight
            )
        )
    }

    /// The HEX value under the cursor, for the copy-colour shortcut.
    func colorHex(at globalPoint: CGPoint) -> String? {
        let pixel = ScreenGeometry.pixelPoint(forGlobalPoint: globalPoint, in: shot.geometry)
        return shot.image.pixelColor(atX: pixel.x, y: pixel.y)?.hexString
    }

    // MARK: - Layout

    /// Sits below-right of the cursor, flipping to the other side near an edge so the
    /// loupe never runs off the display.
    private func panelFrame(near cursor: CGPoint, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: loupeSize, height: loupeSize + captionHeight)

        var x = cursor.x + cursorGap
        if x + size.width > bounds.maxX - 8 {
            x = cursor.x - cursorGap - size.width
        }

        var y = cursor.y - cursorGap - size.height
        if y < bounds.minY + 8 {
            y = cursor.y + cursorGap
        }

        x = min(max(x, bounds.minX + 8), max(bounds.minX + 8, bounds.maxX - size.width - 8))
        y = min(max(y, bounds.minY + 8), max(bounds.minY + 8, bounds.maxY - size.height - 8))

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    // MARK: - Drawing

    private func drawPanelBackground(_ frame: CGRect) {
        NSColor.black.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()

        NSColor.white.withAlphaComponent(0.22).setStroke()
        let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()
    }

    private func drawZoomedPixels(around pixel: (x: Int, y: Int), in loupeRect: CGRect) {
        let half = sourcePixels / 2
        let source = CGRect(
            x: pixel.x - half,
            y: pixel.y - half,
            width: sourcePixels,
            height: sourcePixels
        )
        let imageBounds = CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height)
        let valid = source.intersection(imageBounds)

        guard
            !valid.isNull, valid.width >= 1, valid.height >= 1,
            let crop = shot.image.cropping(to: valid),
            let context = NSGraphicsContext.current?.cgContext
        else { return }

        // Near a screen edge the source window is clipped, so place the surviving part
        // at its proportional position instead of stretching it across the whole loupe.
        let fractionLeft = (valid.minX - source.minX) / source.width
        let fractionTop = (valid.minY - source.minY) / source.height
        let destinationWidth = valid.width / source.width * loupeRect.width
        let destinationHeight = valid.height / source.height * loupeRect.height
        let destination = CGRect(
            x: loupeRect.minX + fractionLeft * loupeRect.width,
            // Image Y runs down, the view's Y runs up.
            y: loupeRect.maxY - fractionTop * loupeRect.height - destinationHeight,
            width: destinationWidth,
            height: destinationHeight
        )

        context.saveGState()
        context.addPath(CGPath(roundedRect: loupeRect, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.clip()
        // Nearest-neighbour: the point is to see individual pixels, not a smooth blur.
        context.interpolationQuality = .none
        context.draw(crop, in: destination)
        context.restoreGState()
    }

    private func drawGrid(in loupeRect: CGRect) {
        NSColor.white.withAlphaComponent(0.12).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1

        for index in 1..<sourcePixels {
            let offset = CGFloat(index) * cellSize
            path.move(to: CGPoint(x: loupeRect.minX + offset, y: loupeRect.minY))
            path.line(to: CGPoint(x: loupeRect.minX + offset, y: loupeRect.maxY))
            path.move(to: CGPoint(x: loupeRect.minX, y: loupeRect.minY + offset))
            path.line(to: CGPoint(x: loupeRect.maxX, y: loupeRect.minY + offset))
        }
        path.stroke()
    }

    private func drawCentreCell(in loupeRect: CGRect) {
        let half = CGFloat(sourcePixels / 2)
        let cell = CGRect(
            x: loupeRect.minX + half * cellSize,
            y: loupeRect.minY + half * cellSize,
            width: cellSize,
            height: cellSize
        )

        NSColor.black.setStroke()
        let outer = NSBezierPath(rect: cell.insetBy(dx: -1, dy: -1))
        outer.lineWidth = 1
        outer.stroke()

        NSColor.white.setStroke()
        let inner = NSBezierPath(rect: cell)
        inner.lineWidth = 1
        inner.stroke()
    }

    private func drawCaption(color: PixelColor?, pixel: (x: Int, y: Int), in rect: CGRect) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let swatchSize: CGFloat = 12

        if let color {
            let swatch = CGRect(
                x: rect.minX + 9,
                y: rect.maxY - 9 - swatchSize,
                width: swatchSize,
                height: swatchSize
            )
            NSColor(
                srgbRed: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255,
                alpha: 1
            ).setFill()
            NSBezierPath(roundedRect: swatch, xRadius: 2, yRadius: 2).fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            NSBezierPath(roundedRect: swatch, xRadius: 2, yRadius: 2).stroke()

            (color.hexString as NSString).draw(
                at: CGPoint(x: swatch.maxX + 7, y: swatch.minY - 1),
                withAttributes: [.font: font, .foregroundColor: NSColor.white]
            )
        }

        ("\(pixel.x), \(pixel.y) px  ·  C copies" as NSString).draw(
            at: CGPoint(x: rect.minX + 9, y: rect.minY + 7),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.6),
            ]
        )
    }
}
