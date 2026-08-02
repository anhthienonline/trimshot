import AppKit
import TrimshotCore

/// Everything drawn *on top of* the frozen screenshot: the dim, the hole punched for the
/// selection, its border and handles, the size readout, the crosshair guides and the
/// magnifier.
///
/// Transparent to the mouse — `hitTest` returns nil so `OverlayRootView` keeps receiving
/// every event.
final class SelectionChromeView: NSView {

    private let shot: DisplayShot
    private let magnifier: Magnifier

    /// AppKit global points, shared by every display's chrome view.
    var selection: CGRect? {
        didSet { if selection != oldValue { needsDisplay = true } }
    }

    /// Cursor position in AppKit global points. The coordinator broadcasts the same value to
    /// every display, so each view decides for itself whether it needs to redraw.
    ///
    /// A full-screen chrome redraw costs several milliseconds at Retina resolution, and this
    /// fires on every mouse move — repainting displays the cursor is nowhere near would
    /// multiply that by the number of monitors for nothing.
    var pointer: CGPoint? {
        didSet {
            guard pointer != oldValue else { return }
            let wasRelevant = oldValue.map { shot.geometry.frame.contains($0) } ?? false
            let isRelevant = pointer.map { shot.geometry.frame.contains($0) } ?? false
            if wasRelevant || isRelevant { needsDisplay = true }
        }
    }

    /// True once the drag has finished: handles appear and the magnifier steps aside so
    /// it cannot cover the selection or the annotation toolbar.
    var isSettled = false {
        didSet { if isSettled != oldValue { needsDisplay = true } }
    }

    /// Committed marks, in AppKit global points.
    var annotations: [Annotation] = [] {
        didSet { needsDisplay = true }
    }

    /// The mark currently being dragged out.
    var draft: Annotation? {
        didSet { if draft != oldValue { needsDisplay = true } }
    }

    /// Non-nil while a drawing tool is armed: handles are hidden so the selection reads
    /// as a canvas rather than something to resize.
    var activeTool: AnnotationTool? {
        didSet { if activeTool != oldValue { needsDisplay = true } }
    }

    /// Bounding rect of the mark being edited, in AppKit global points.
    var selectedMark: CGRect? {
        didSet { if selectedMark != oldValue { needsDisplay = true } }
    }

    /// The A→B ruler reading, kept on screen after the drag so it can be read.
    var ruler: RulerReading? {
        didSet { if ruler != oldValue { needsDisplay = true } }
    }

    /// Measure mode: report the gap the cursor sits in instead of showing the loupe.
    var isMeasuring = false {
        didSet { if isMeasuring != oldValue { needsDisplay = true } }
    }

    init(shot: DisplayShot) {
        self.shot = shot
        self.magnifier = Magnifier(shot: shot)
        super.init(frame: CGRect(origin: .zero, size: shot.geometry.frame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Coordinate conversion

    /// AppKit global points → this view's coordinates. The window matches the display
    /// frame exactly, so it is a plain translation.
    private func toLocal(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - shot.geometry.frame.minX,
            y: point.y - shot.geometry.frame.minY
        )
    }

    private func toLocal(_ rect: CGRect) -> CGRect {
        CGRect(origin: toLocal(rect.origin), size: rect.size)
    }

    private var pointerIsOnThisDisplay: Bool {
        guard let pointer else { return false }
        return shot.geometry.frame.contains(pointer)
    }

    // MARK: - Drawing

    private enum Style {
        static let dim = NSColor.black.withAlphaComponent(0.42)
        static let border = NSColor.white
        static let borderShadow = NSColor.black.withAlphaComponent(0.55)
        static let guide = NSColor.white.withAlphaComponent(0.35)
        static let labelBackground = NSColor.black.withAlphaComponent(0.78)
        static let labelText = NSColor.white
        static let handleFill = NSColor.white
        static let handleStroke = NSColor.black.withAlphaComponent(0.55)
        static let handleSize: CGFloat = 7
        /// Reserved for dimension annotations — see brand/BRAND.md. Nothing else may use it,
        /// or it stops meaning "this has been measured".
        static let measure = NSColor(srgbRed: 0xD8 / 255, green: 0x1B / 255, blue: 0x60 / 255, alpha: 1)
        /// The brand's signal teal, for the frame around a mark being edited. Distinct from
        /// both the solid white selection border and the magenta dimension lines.
        static let editFrame = NSColor(srgbRed: 0x5F / 255, green: 0xD3 / 255, blue: 0xDE / 255, alpha: 1)

        // Computed rather than stored: NSFont is not Sendable, so a `static let` would
        // be a concurrency error under Swift 6.
        static var labelFont: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .medium) }
        static var hintFont: NSFont { .systemFont(ofSize: 13, weight: .medium) }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let selection, selection.width >= 1, selection.height >= 1 {
            drawDim(punchingOut: toLocal(selection))
            drawAnnotations(clippedTo: toLocal(selection))
            drawBorder(around: toLocal(selection))
            // Handles would only get in the way of drawing, so they yield to an armed tool.
            if isSettled, activeTool == nil {
                drawHandles(on: toLocal(selection))
            }
            drawSizeLabel(for: selection)
            if let selectedMark {
                drawMarkFrame(on: toLocal(selectedMark))
            }
        } else {
            drawDim(punchingOut: nil)
            drawCrosshair()
            drawHint()
        }

        if isMeasuring {
            // A drag beats a hover: once you have measured A→B, that is the number you want
            // on screen, not the gap the cursor happens to be over now.
            if ruler != nil {
                drawRuler()
            } else {
                drawMeasurement()
            }
        } else if !isSettled, pointerIsOnThisDisplay, let pointer {
            // One or the other: the loupe and the dimension lines both want the area around
            // the cursor, and together they are unreadable.
            magnifier.draw(globalPoint: pointer, viewPoint: toLocal(pointer), in: bounds)
        }
    }

    /// Draws the horizontal and vertical runs the cursor sits inside, with their sizes.
    ///
    /// Magenta because that is what this palette reserves it for — a real dimension
    /// annotation, and nothing else in the app uses the colour.
    private func drawMeasurement() {
        guard pointerIsOnThisDisplay, let pointer else { return }

        let pixel = ScreenGeometry.pixelPoint(forGlobalPoint: pointer, in: shot.geometry)
        let spans = EdgeDetector.spans(in: shot.image, atX: pixel.x, y: pixel.y)
        let local = toLocal(pointer)

        Style.measure.setStroke()
        Style.measure.setFill()

        if let h = spans.horizontal {
            let x = EdgeDetector.viewSpan(for: h, axis: .horizontal, in: shot.geometry)
            drawDimension(
                from: CGPoint(x: x.from, y: local.y.rounded() + 0.5),
                to: CGPoint(x: x.to, y: local.y.rounded() + 0.5),
                text: sizeText(pixels: h.length, scale: shot.geometry.scale),
                vertical: false
            )
        }

        if let v = spans.vertical {
            let y = EdgeDetector.viewSpan(for: v, axis: .vertical, in: shot.geometry)
            drawDimension(
                from: CGPoint(x: local.x.rounded() + 0.5, y: y.from),
                to: CGPoint(x: local.x.rounded() + 0.5, y: y.to),
                text: sizeText(pixels: v.length, scale: shot.geometry.scale),
                vertical: true
            )
        }
    }

    /// The ruler box: a rectangle spanning the drag, with a dimension line on each axis.
    ///
    /// Not the direct A→B line. Drawing the diagonal plus its two components made a right
    /// triangle, and in UI work the diagonal is almost never the number wanted — the useful
    /// question is how wide and how tall.
    private func drawRuler() {
        guard let ruler, ruler.isMeaningful else { return }

        let rect = toLocal(ruler.rect)

        Style.measure.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 1
        outline.stroke()

        // Corner ticks, so the two endpoints of the drag stay identifiable inside the box.
        drawEndTick(at: CGPoint(x: rect.minX, y: rect.minY), facing: CGPoint(x: rect.maxX, y: rect.minY))
        drawEndTick(at: CGPoint(x: rect.maxX, y: rect.maxY), facing: CGPoint(x: rect.minX, y: rect.maxY))

        // Width, dimensioned below the box — flipped above when it is against the bottom edge.
        let below = rect.minY - 20 > bounds.minY
        let widthY = below ? rect.minY - 20 : rect.maxY + 20
        drawDimension(
            from: CGPoint(x: rect.minX, y: widthY),
            to: CGPoint(x: rect.maxX, y: widthY),
            text: Units.length(ruler.rect.width),
            vertical: false
        )

        // Height, dimensioned to the left, flipping right near the screen edge.
        let onLeft = rect.minX - 20 > bounds.minX
        let heightX = onLeft ? rect.minX - 20 : rect.maxX + 20
        drawDimension(
            from: CGPoint(x: heightX, y: rect.minY),
            to: CGPoint(x: heightX, y: rect.maxY),
            text: Units.length(ruler.rect.height),
            vertical: true
        )

        // The pair, in the middle, matching how the selection reports its own size.
        drawReading(Units.size(ruler.rect.size), centredOn: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// A short segment across the end of the ruler, so the endpoints are unambiguous.
    private func drawEndTick(at point: CGPoint, facing other: CGPoint) {
        let dx = other.x - point.x
        let dy = other.y - point.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let normal = CGPoint(x: -dy / length * 5, y: dx / length * 5)
        let tick = NSBezierPath()
        tick.lineWidth = 1.5
        tick.move(to: CGPoint(x: point.x - normal.x, y: point.y - normal.y))
        tick.line(to: CGPoint(x: point.x + normal.x, y: point.y + normal.y))
        tick.stroke()
    }

    private func drawReading(_ text: String, centredOn point: CGPoint) {
        let font = Style.labelFont
        let size = measure(text, font: font)
        let padding = CGSize(width: 7, height: 4)
        let box = CGRect(
            x: point.x - size.width / 2 - padding.width,
            y: point.y - size.height / 2 - padding.height,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )

        Style.measure.setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: CGPoint(x: box.minX + padding.width, y: box.minY + padding.height),
            withAttributes: [.font: font, .foregroundColor: NSColor.white]
        )
    }

    /// A span is measured in device pixels because that is what the bitmap is; the reading is
    /// in CSS pixels because that is what the app reports. See Units.
    private func sizeText(pixels: Int, scale: CGFloat) -> String {
        Units.length(CGFloat(pixels) / scale)
    }

    /// A line with end ticks and a label in the middle — the same annotation the brand uses.
    private func drawDimension(from a: CGPoint, to b: CGPoint, text: String, vertical: Bool) {
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: a)
        path.line(to: b)
        // End ticks, perpendicular to the run.
        let tick: CGFloat = 5
        if vertical {
            path.move(to: CGPoint(x: a.x - tick, y: a.y)); path.line(to: CGPoint(x: a.x + tick, y: a.y))
            path.move(to: CGPoint(x: b.x - tick, y: b.y)); path.line(to: CGPoint(x: b.x + tick, y: b.y))
        } else {
            path.move(to: CGPoint(x: a.x, y: a.y - tick)); path.line(to: CGPoint(x: a.x, y: a.y + tick))
            path.move(to: CGPoint(x: b.x, y: b.y - tick)); path.line(to: CGPoint(x: b.x, y: b.y + tick))
        }
        path.stroke()

        let font = Style.labelFont
        let size = measure(text, font: font)
        let padding = CGSize(width: 6, height: 3)
        let box = CGRect(
            x: (a.x + b.x) / 2 - size.width / 2 - padding.width,
            y: (a.y + b.y) / 2 - size.height / 2 - padding.height,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        Style.measure.setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: CGPoint(x: box.minX + padding.width, y: box.minY + padding.height),
            withAttributes: [.font: font, .foregroundColor: NSColor.white]
        )
    }

    /// Previews the marks using the very same renderer that bakes them into the exported
    /// file, so what is on screen cannot drift from what gets saved.
    private func drawAnnotations(clippedTo selectionInView: CGRect) {
        var all = annotations
        if let draft { all.append(draft) }
        guard !all.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.clip(to: selectionInView)
        AnnotationRenderer.draw(
            all,
            in: context,
            transform: AnnotationRenderer.transform(
                origin: shot.geometry.frame.origin,
                scale: 1
            ),
            pixelateSource: (image: shot.image, geometry: shot.geometry)
        )
        context.restoreGState()
    }

    private func drawDim(punchingOut hole: CGRect?) {
        let path = NSBezierPath(rect: bounds)
        if let hole {
            path.appendRect(hole)
            path.windingRule = .evenOdd
        }
        Style.dim.setFill()
        path.fill()
    }

    private func drawBorder(around rect: CGRect) {
        // A dark line just outside a white line, so the border stays visible whether the
        // content underneath is light or dark.
        Style.borderShadow.setStroke()
        let outer = NSBezierPath(rect: rect.insetBy(dx: -1.5, dy: -1.5))
        outer.lineWidth = 1
        outer.stroke()

        Style.border.setStroke()
        let inner = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        inner.lineWidth = 1
        inner.stroke()
    }

    private func drawHandles(on rect: CGRect) {
        let size = Style.handleSize
        for handle in SelectionHandle.allCases {
            let centre = handle.point(in: rect)
            let box = CGRect(
                x: (centre.x - size / 2).rounded(),
                y: (centre.y - size / 2).rounded(),
                width: size,
                height: size
            )
            Style.handleFill.setFill()
            NSBezierPath(rect: box).fill()
            Style.handleStroke.setStroke()
            let outline = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    /// A dashed frame with handles around the mark being edited — dashed so it never reads as
    /// the selection border, which is solid.
    private func drawMarkFrame(on rect: CGRect) {
        Style.editFrame.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        outline.lineWidth = 1
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()
        drawHandles(on: rect)
    }

    private func drawCrosshair() {
        guard pointerIsOnThisDisplay, let pointer else { return }
        let local = toLocal(pointer)

        Style.guide.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: 0, y: local.y.rounded() + 0.5))
        path.line(to: CGPoint(x: bounds.width, y: local.y.rounded() + 0.5))
        path.move(to: CGPoint(x: local.x.rounded() + 0.5, y: 0))
        path.line(to: CGPoint(x: local.x.rounded() + 0.5, y: bounds.height))
        path.stroke()
    }

    /// `840 × 480 px · 420 × 240 pt` — pixels first because that is what a developer
    /// checking a build against a Figma frame actually needs.
    private func drawSizeLabel(for globalSelection: CGRect) {
        let text = Units.size(globalSelection.size)

        let local = toLocal(globalSelection)
        let size = measure(text, font: Style.labelFont)
        let padding = CGSize(width: 8, height: 4)
        let boxSize = CGSize(
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )

        // Prefer sitting just above the selection; drop inside when it is against the top
        // edge of the display.
        var origin = CGPoint(x: local.minX, y: local.maxY + 8)
        if origin.y + boxSize.height > bounds.maxY - 4 {
            origin.y = local.maxY - boxSize.height - 8
        }
        origin.x = min(max(origin.x, 4), max(4, bounds.maxX - boxSize.width - 4))

        drawLabel(text, at: origin, boxSize: boxSize, padding: padding, font: Style.labelFont)
    }

    private func drawHint() {
        guard pointerIsOnThisDisplay else { return }

        let text = isMeasuring
            ? "Measuring — point at a gap  ·  M returns to selecting  ·  esc cancels"
            : "Drag to select  ·  ⌘A whole screen  ·  C copies the colour  ·  M measures  ·  esc cancels"
        let size = measure(text, font: Style.hintFont)
        let padding = CGSize(width: 14, height: 9)
        let boxSize = CGSize(
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        // While measuring, the dimension lines run through the cursor and their labels sit
        // at the midpoint of each span — anywhere near the middle of the screen collides with
        // them. Park the hint at the bottom instead.
        let origin = CGPoint(
            x: (bounds.width - boxSize.width) / 2,
            y: isMeasuring ? bounds.height * 0.06 : bounds.height * 0.62
        )

        drawLabel(text, at: origin, boxSize: boxSize, padding: padding, font: Style.hintFont)
    }

    // MARK: - Label helpers

    private func measure(_ text: String, font: NSFont) -> CGSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private func drawLabel(
        _ text: String,
        at origin: CGPoint,
        boxSize: CGSize,
        padding: CGSize,
        font: NSFont
    ) {
        let box = CGRect(origin: origin, size: boxSize)
        Style.labelBackground.setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()

        (text as NSString).draw(
            at: CGPoint(x: box.minX + padding.width, y: box.minY + padding.height),
            withAttributes: [.font: font, .foregroundColor: Style.labelText]
        )
    }
}
