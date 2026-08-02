import CoreGraphics
import Foundation
import TrimshotCore

/// A 1440×900 pt Retina laptop screen — the main display, at the origin.
let retina = DisplayGeometry(
    displayID: 1,
    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    scale: 2
)

/// A 1920×1080 non-Retina monitor placed to the *left* of the main screen, so its
/// origin is negative — the arrangement that breaks naive coordinate math.
let leftMonitor = DisplayGeometry(
    displayID: 2,
    frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
    scale: 1
)

Check.suite("ScreenGeometry") {
    // A rect whose top edge sits 100 pt below the display's top edge.
    Check.expectEqual(
        ScreenGeometry.pixelRect(
            forGlobalRect: CGRect(x: 100, y: 700, width: 200, height: 100),
            in: retina
        ),
        CGRect(x: 200, y: 200, width: 400, height: 200),
        "global points → pixels on a 2x display, with Y flipped"
    )

    Check.expectEqual(
        ScreenGeometry.pixelRect(
            forGlobalRect: CGRect(x: -1900, y: 1000, width: 100, height: 50),
            in: leftMonitor
        ),
        CGRect(x: 20, y: 30, width: 100, height: 50),
        "global points → pixels on a display at a negative origin"
    )

    for display in [retina, leftMonitor] {
        let original = CGRect(x: 40, y: 60, width: 300, height: 180)
        let global = ScreenGeometry.globalRect(forPixelRect: original, in: display)
        Check.expectEqual(
            ScreenGeometry.pixelRect(forGlobalRect: global, in: display),
            original,
            "pixel → global → pixel round-trips on display \(display.displayID)"
        )
    }

    Check.expectEqual(
        retina.pixelSize,
        CGSize(width: 2880, height: 1800),
        "a 2x display reports twice its point size in pixels"
    )

    Check.expectEqual(
        ScreenGeometry.clamped(CGRect(x: 2800, y: 100, width: 400, height: 200), toPixelSizeOf: retina),
        CGRect(x: 2800, y: 100, width: 80, height: 200),
        "clamping trims a rect that runs off the display edge"
    )

    Check.expect(
        ScreenGeometry.clamped(CGRect(x: 5000, y: 5000, width: 100, height: 100), toPixelSizeOf: retina) == nil,
        "clamping returns nil when the rect misses the display entirely"
    )

    Check.expectEqual(
        ScreenGeometry.displays(
            intersecting: CGRect(x: 10, y: 10, width: 100, height: 100),
            among: [retina, leftMonitor]
        ),
        [retina],
        "only displays the selection touches are returned"
    )

    // Straddles the seam at x = 0.
    let spanning = CGRect(x: -50, y: 10, width: 100, height: 100)
    Check.expectEqual(
        ScreenGeometry.displays(intersecting: spanning, among: [retina, leftMonitor]).count,
        2,
        "a selection across the seam reports both displays"
    )

    Check.expectEqual(
        ScreenGeometry.renderScale(forGlobalRect: spanning, among: [retina, leftMonitor]),
        2,
        "a selection spanning mixed-scale displays renders at the highest scale"
    )

    let downRight = ScreenGeometry.normalizedRect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 220))
    let upLeft = ScreenGeometry.normalizedRect(from: CGPoint(x: 110, y: 220), to: CGPoint(x: 10, y: 20))
    Check.expectEqual(downRight, CGRect(x: 10, y: 20, width: 100, height: 200), "drag down-right normalizes")
    Check.expectEqual(upLeft, downRight, "dragging up-left gives the same rect as down-right")
}

Check.suite("ScreenGeometry.pixelPoint") {
    // The display's top-left corner is pixel (0, 0).
    let topLeft = ScreenGeometry.pixelPoint(
        forGlobalPoint: CGPoint(x: 0, y: 900),
        in: retina
    )
    Check.expect(topLeft == (0, 0), "the top-left corner maps to pixel 0,0")

    let middle = ScreenGeometry.pixelPoint(
        forGlobalPoint: CGPoint(x: 100, y: 800),
        in: retina
    )
    Check.expect(middle == (200, 200), "a point 100 pt in and 100 pt down maps to 200,200 at 2x")

    // Flooring, not rounding: anywhere inside a pixel reports that pixel.
    let inside = ScreenGeometry.pixelPoint(
        forGlobalPoint: CGPoint(x: 100.4, y: 899.6),
        in: retina
    )
    Check.expect(inside == (200, 0), "a fractional point floors to the pixel it sits in")

    let onLeftMonitor = ScreenGeometry.pixelPoint(
        forGlobalPoint: CGPoint(x: -1900, y: 1050),
        in: leftMonitor
    )
    Check.expect(onLeftMonitor == (20, 30), "negative-origin displays map correctly")
}

Check.suite("SelectionHandle") {
    let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    Check.expectEqual(
        SelectionHandle.topLeft.point(in: rect),
        CGPoint(x: 100, y: 200),
        "topLeft is minX/maxY in a Y-up space"
    )
    Check.expectEqual(
        SelectionHandle.bottomRight.point(in: rect),
        CGPoint(x: 300, y: 100),
        "bottomRight is maxX/minY"
    )

    Check.expectEqual(
        SelectionHandle.topLeft.resize(rect, to: CGPoint(x: 150, y: 180)),
        CGRect(x: 150, y: 100, width: 150, height: 80),
        "dragging topLeft leaves the opposite corner pinned"
    )
    Check.expectEqual(
        SelectionHandle.right.resize(rect, to: CGPoint(x: 400, y: 999)),
        CGRect(x: 100, y: 100, width: 300, height: 100),
        "an edge handle only moves its own axis"
    )
    Check.expectEqual(
        SelectionHandle.left.resize(rect, to: CGPoint(x: 400, y: 0)),
        CGRect(x: 300, y: 100, width: 100, height: 100),
        "dragging an edge past its opposite flips the rect instead of going negative"
    )

    Check.expect(
        SelectionHandle.hitTest(CGPoint(x: 102, y: 198), in: rect) == .topLeft,
        "a point near a corner hits that corner"
    )
    Check.expect(
        SelectionHandle.hitTest(CGPoint(x: 200, y: 200), in: rect) == .top,
        "a point at the middle of an edge hits that edge"
    )
    Check.expect(
        SelectionHandle.hitTest(CGPoint(x: 200, y: 150), in: rect) == nil,
        "the interior hits no handle"
    )

    // Corners win where their grab areas overlap an edge midpoint on a tiny selection.
    let tiny = CGRect(x: 0, y: 0, width: 10, height: 10)
    Check.expect(
        SelectionHandle.hitTest(CGPoint(x: 0, y: 0), in: tiny) == .bottomLeft,
        "on a tiny rect the corner wins over the edge midpoint"
    )
}

Check.suite("CGRect.offsetBy(clampedTo:)") {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let rect = CGRect(x: 10, y: 10, width: 100, height: 100)

    Check.expectEqual(
        rect.offsetBy(dx: -50, dy: 0, clampedTo: bounds),
        CGRect(x: 0, y: 10, width: 100, height: 100),
        "moving past the left edge stops at it and keeps its size"
    )
    Check.expectEqual(
        rect.offsetBy(dx: 5000, dy: 5000, clampedTo: bounds),
        CGRect(x: 900, y: 700, width: 100, height: 100),
        "moving far past the far corner stops flush against it"
    )
    Check.expectEqual(
        rect.offsetBy(dx: 5, dy: 5, clampedTo: nil),
        CGRect(x: 15, y: 15, width: 100, height: 100),
        "no bounds means no clamping"
    )
}

Check.suite("Annotation") {
    let red = PixelColor(red: 255, green: 59, blue: 48)

    let pen = Annotation(
        tool: .pen,
        points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 90), CGPoint(x: 30, y: 40)],
        color: red,
        lineWidth: 3
    )
    Check.expectEqual(
        pen.boundingRect,
        CGRect(x: 10, y: 10, width: 40, height: 80),
        "boundingRect spans every point of a freehand stroke"
    )

    let backwards = Annotation(
        tool: .rectangle,
        points: [CGPoint(x: 100, y: 100), CGPoint(x: 20, y: 30)],
        color: red,
        lineWidth: 2
    )
    Check.expectEqual(
        backwards.boundingRect,
        CGRect(x: 20, y: 30, width: 80, height: 70),
        "dragging up-left still yields a positive rect"
    )

    Check.expect(
        !Annotation(tool: .rectangle, points: [.zero, CGPoint(x: 1, y: 1)], color: red, lineWidth: 2)
            .isMeaningful,
        "a click-sized rectangle is discarded"
    )
    Check.expect(
        !Annotation(tool: .text, points: [.zero], color: red, lineWidth: 18, text: "").isMeaningful,
        "empty text is discarded"
    )
    Check.expect(
        Annotation(tool: .text, points: [.zero], color: red, lineWidth: 18, text: "hi").isMeaningful,
        "text with content is kept"
    )
    Check.expect(
        !Annotation(tool: .pen, points: [.zero], color: red, lineWidth: 3).isMeaningful,
        "a single-point stroke is discarded"
    )
}

Check.suite("AnnotationStore") {
    let red = PixelColor(red: 255, green: 59, blue: 48)
    func mark(_ x: CGFloat) -> Annotation {
        Annotation(tool: .line, points: [CGPoint(x: x, y: 0), CGPoint(x: x, y: 10)], color: red, lineWidth: 2)
    }

    var store = AnnotationStore()
    Check.expect(!store.canUndo && !store.canRedo, "a fresh store has nothing to undo or redo")

    store.add(mark(1))
    store.add(mark(2))
    Check.expectEqual(store.annotations.count, 2, "two marks are stored")

    store.undo()
    Check.expectEqual(store.annotations.count, 1, "undo removes the last mark")
    Check.expect(store.canRedo, "undo makes redo available")

    store.redo()
    Check.expectEqual(store.annotations.count, 2, "redo puts it back")

    store.undo()
    store.add(mark(3))
    Check.expect(!store.canRedo, "drawing after an undo clears the redo stack")
    Check.expectEqual(store.annotations.map(\.start.x), [1, 3], "the redone branch is gone")
}

Check.suite("AnnotationRenderer.transform") {
    // The live preview: display origin, no scaling.
    let preview = AnnotationRenderer.transform(origin: CGPoint(x: -1920, y: 0), scale: 1)
    Check.expectEqual(
        CGPoint(x: -1900, y: 50).applying(preview),
        CGPoint(x: 20, y: 50),
        "preview maps global points into the display's own coordinates"
    )

    // The export: crop origin, Retina scale.
    let export = AnnotationRenderer.transform(origin: CGPoint(x: 100, y: 200), scale: 2)
    Check.expectEqual(
        CGPoint(x: 150, y: 260).applying(export),
        CGPoint(x: 100, y: 120),
        "export translates by the crop origin before scaling to pixels"
    )
    Check.expectEqual(
        CGRect(x: 100, y: 200, width: 40, height: 30).applying(export),
        CGRect(x: 0, y: 0, width: 80, height: 60),
        "a rect at the crop origin lands at the bitmap origin, doubled"
    )
}

Check.suite("EdgeDetector.span") {
    // A white field with a dark bar from 30 to 39 inclusive.
    var line = [Double](repeating: 1.0, count: 100)
    for i in 30...39 { line[i] = 0.05 }

    Check.expectEqual(
        EdgeDetector.span(in: line, from: 10),
        EdgeSpan(start: 0, end: 29),
        "a point left of the bar spans up to the bar's edge"
    )
    Check.expectEqual(
        EdgeDetector.span(in: line, from: 60),
        EdgeSpan(start: 40, end: 99),
        "a point right of the bar spans from the bar to the end"
    )
    Check.expectEqual(
        EdgeDetector.span(in: line, from: 34),
        EdgeSpan(start: 30, end: 39),
        "a point on the bar measures the bar itself"
    )
    Check.expectEqual(
        EdgeDetector.span(in: line, from: 10)?.length,
        30,
        "length is inclusive of both ends"
    )

    // The gap between two bars — the spacing case this exists for.
    var gap = [Double](repeating: 1.0, count: 60)
    for i in 0...9 { gap[i] = 0.0 }
    for i in 34...59 { gap[i] = 0.0 }
    Check.expectEqual(
        EdgeDetector.span(in: gap, from: 20),
        EdgeSpan(start: 10, end: 33),
        "the run between two dark bars is measured, not the bars"
    )
    Check.expectEqual(
        EdgeDetector.span(in: gap, from: 20)?.length,
        24,
        "a 24 px gap reports 24"
    )

    // Anti-aliasing and gradients must not be mistaken for edges.
    var soft = [Double](repeating: 0.5, count: 40)
    for i in 0..<40 { soft[i] = 0.5 + Double(i) * 0.002 }  // 0.078 total drift
    Check.expectEqual(
        EdgeDetector.span(in: soft, from: 20),
        EdgeSpan(start: 0, end: 39),
        "a gentle gradient inside the threshold is one span"
    )

    Check.expect(
        EdgeDetector.span(in: line, from: -1) == nil
            && EdgeDetector.span(in: line, from: 100) == nil
            && EdgeDetector.span(in: [], from: 0) == nil,
        "out-of-range origins and empty lines return nil"
    )
}

Check.suite("EdgeDetector on a real bitmap") {
    // Two black bars on white, 40 px apart, drawn rather than described — this exercises the
    // row/column extraction and its Y-flip, which the array-level checks cannot.
    let width = 200, height = 120
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    // In image coordinates (Y down) these sit at y = 0..<20 and y = 100..<120.
    context.fill(CGRect(x: 20, y: 0, width: 10, height: height))    // vertical bar
    context.fill(CGRect(x: 70, y: 0, width: 10, height: height))    // vertical bar
    context.fill(CGRect(x: 0, y: height - 20, width: width, height: 20))  // top band, Y-down
    let image = context.makeImage()!

    let result = EdgeDetector.spans(in: image, atX: 45, y: 60)
    Check.expectEqual(
        result.horizontal,
        EdgeSpan(start: 30, end: 69),
        "the horizontal gap between the two bars measures 30…69"
    )
    Check.expectEqual(result.horizontal?.length, 40, "which is 40 px")

    // Vertically at x = 45 the only feature is the band occupying image rows 0…19, so a
    // point at y = 60 spans from row 20 to the bottom. Getting the flip wrong inverts this.
    Check.expectEqual(
        result.vertical,
        EdgeSpan(start: 20, end: 119),
        "the vertical span starts below the band, proving the Y flip"
    )
}

Check.suite("EdgeDetector.viewSpan") {
    // A 2x display 900 pt tall: 1800 image rows.
    let span = EdgeSpan(start: 100, end: 179)   // 80 px inclusive
    Check.expectEqual(span.length, 80, "the span is 80 px")

    let h = EdgeDetector.viewSpan(for: span, axis: .horizontal, in: retina)
    Check.expectEqual(h.from, 50, "horizontal start converts to points")
    Check.expectEqual(h.to, 90, "and the end is exclusive, so the run draws its full width")
    Check.expectEqual(h.to - h.from, 40, "80 px at 2x is 40 pt wide on screen")

    let v = EdgeDetector.viewSpan(for: span, axis: .vertical, in: retina)
    Check.expectEqual(v.from, 850, "vertical start is measured down from the top")
    Check.expectEqual(v.to, 810, "and runs downward, so `to` is the lower number")
    Check.expectEqual(v.from - v.to, 40, "same 40 pt, flipped")

    // A 1x display: points and pixels coincide, so nothing should be scaled.
    let flat = EdgeDetector.viewSpan(for: span, axis: .horizontal, in: leftMonitor)
    Check.expectEqual(flat.to - flat.from, 80, "at 1x the run is 80 pt wide")
}

Check.suite("AnnotationRenderer.fit") {
    // A 200×100 picture dropped into a square: letterboxed, centred, never stretched.
    let square = CGRect(x: 0, y: 0, width: 100, height: 100)
    let wide = AnnotationRenderer.fit(CGSize(width: 200, height: 100), in: square)
    Check.expectEqual(wide, CGRect(x: 0, y: 25, width: 100, height: 50), "a wide image letterboxes vertically")
    Check.expectEqual(wide.width / wide.height, 2, "and keeps its 2:1 aspect ratio")

    let tall = AnnotationRenderer.fit(CGSize(width: 100, height: 200), in: square)
    Check.expectEqual(tall, CGRect(x: 25, y: 0, width: 50, height: 100), "a tall image letterboxes horizontally")

    let exact = AnnotationRenderer.fit(CGSize(width: 50, height: 50), in: square)
    Check.expectEqual(exact, square, "a matching aspect ratio fills the rect")

    // Off-origin rects have to stay centred on the rect, not on the origin.
    let offset = AnnotationRenderer.fit(
        CGSize(width: 200, height: 100),
        in: CGRect(x: 300, y: 400, width: 100, height: 100)
    )
    Check.expectEqual(offset.midX, 350, "centred horizontally on the target rect")
    Check.expectEqual(offset.midY, 450, "and vertically")

    Check.expectEqual(
        AnnotationRenderer.fit(CGSize(width: 0, height: 0), in: square),
        square,
        "a degenerate size falls back to the rect rather than dividing by zero"
    )
}

Check.suite("Annotation.image") {
    let red = PixelColor(red: 255, green: 59, blue: 48)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let picture = AnnotationImage(ctx.makeImage()!)

    let placed = Annotation(tool: .image, points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 20)],
                            color: red, lineWidth: 0, image: picture)
    Check.expect(placed.isMeaningful, "a placed image over a real rect is kept")

    let noPicture = Annotation(tool: .image, points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 20)],
                               color: red, lineWidth: 0)
    Check.expect(!noPicture.isMeaningful, "the image tool with nothing to place is discarded")

    let clickSized = Annotation(tool: .image, points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)],
                                color: red, lineWidth: 0, image: picture)
    Check.expect(!clickSized.isMeaningful, "a click-sized placement is discarded")

    Check.expect(placed == placed, "identity comparison makes an image annotation Equatable")
    Check.expect(placed != noPicture, "and distinguishes one with a picture from one without")
}

Check.suite("Annotation editing") {
    let red = PixelColor(red: 255, green: 59, blue: 48)
    let box = Annotation(tool: .rectangle, points: [CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 70)],
                         color: red, lineWidth: 2)

    Check.expectEqual(
        box.moved(dx: 5, dy: -5).boundingRect,
        CGRect(x: 15, y: 15, width: 100, height: 50),
        "moving shifts the whole mark and keeps its size"
    )

    Check.expectEqual(
        box.resized(to: CGRect(x: 0, y: 0, width: 200, height: 100)).boundingRect,
        CGRect(x: 0, y: 0, width: 200, height: 100),
        "resizing lands exactly on the requested rect"
    )

    // A freehand stroke must keep its shape proportionally, not just its two extremes.
    let stroke = Annotation(
        tool: .pen,
        points: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 10), CGPoint(x: 10, y: 0)],
        color: red, lineWidth: 3
    )
    let doubled = stroke.resized(to: CGRect(x: 0, y: 0, width: 20, height: 20))
    Check.expectEqual(doubled.points[1], CGPoint(x: 10, y: 20), "the middle point scales with the rest")
    Check.expectEqual(doubled.points.count, 3, "and no points are lost")

    let degenerate = Annotation(tool: .line, points: [CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)],
                               color: red, lineWidth: 2)
    Check.expectEqual(
        degenerate.resized(to: CGRect(x: 40, y: 40, width: 10, height: 10)).points,
        [CGPoint(x: 40, y: 40), CGPoint(x: 40, y: 40)],
        "a zero-size mark moves instead of dividing by zero"
    )

    // Only the tools that fill a rect are pickable; a line would need distance-to-stroke.
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let picture = AnnotationImage(ctx.makeImage()!)
    let placed = Annotation(tool: .image, points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50)],
                            color: red, lineWidth: 0, image: picture)
    Check.expect(placed.contains(CGPoint(x: 25, y: 25)), "a click inside a placed image picks it")
    Check.expect(!placed.contains(CGPoint(x: 80, y: 25)), "a click outside does not")
    Check.expect(!box.isPickable, "a rectangle outline is not pickable yet")

    var store = AnnotationStore()
    store.add(placed)
    store.add(placed.moved(dx: 100, dy: 0))
    Check.expectEqual(store.indexOfMark(at: CGPoint(x: 125, y: 25)), 1, "picks the mark under the point")
    Check.expectEqual(store.indexOfMark(at: CGPoint(x: 25, y: 25)), 0, "and the other one at its own spot")
    Check.expect(store.indexOfMark(at: CGPoint(x: 400, y: 400)) == nil, "empty space picks nothing")

    store.replace(at: 0, with: placed.moved(dx: 0, dy: 30))
    Check.expectEqual(store.annotations[0].boundingRect.minY, 30, "replace mutates in place")
    Check.expectEqual(store.annotations.count, 2, "without changing the count")

    store.remove(at: 0)
    Check.expectEqual(store.annotations.count, 1, "remove drops one")
    store.replace(at: 99, with: placed)
    store.remove(at: 99)
    Check.expectEqual(store.annotations.count, 1, "out-of-range indices are ignored, not crashes")
}

Check.suite("RulerReading") {
    // A 3-4-5 triangle, so the distance is exact rather than approximately right.
    let m = RulerReading(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 50))
    Check.expectEqual(m.dx, 30, "dx is the signed horizontal component")
    Check.expectEqual(m.dy, 40, "dy is the signed vertical component, positive upward")
    Check.expectEqual(m.distance, 50, "3-4-5 scaled by ten gives exactly 50")
    Check.expectEqual(
        m.rect, CGRect(x: 10, y: 10, width: 30, height: 40),
        "the rect spans the drag"
    )
    // Dragging up-left has to give the same box as dragging down-right.
    Check.expectEqual(
        RulerReading(from: CGPoint(x: 40, y: 50), to: CGPoint(x: 10, y: 10)).rect,
        m.rect,
        "the rect is normalised whichever way you drag"
    )

    Check.expectEqual(
        RulerReading(from: .zero, to: CGPoint(x: 10, y: 0)).angle, 0,
        "due right is 0°"
    )
    Check.expectEqual(
        RulerReading(from: .zero, to: CGPoint(x: 0, y: 10)).angle, 90,
        "straight up is +90° in a Y-up space"
    )
    Check.expectEqual(
        RulerReading(from: .zero, to: CGPoint(x: 0, y: -10)).angle, -90,
        "straight down is -90°"
    )
    Check.expectEqual(
        RulerReading(from: .zero, to: CGPoint(x: -10, y: 0)).angle, 180,
        "due left is 180°"
    )
    Check.expectEqual(
        RulerReading(from: .zero, to: .zero).angle, 0,
        "a zero-length measurement reports 0° instead of NaN"
    )

    let diagonal = RulerReading(from: .zero, to: CGPoint(x: 10, y: 10))
    Check.expect(abs(diagonal.angle - 45) < 0.0001, "a 45° diagonal reads 45°")

    Check.expect(!RulerReading(from: .zero, to: CGPoint(x: 0.4, y: 0)).isMeaningful,
                 "a sub-pixel drag is not a measurement")
    Check.expect(RulerReading(from: .zero, to: CGPoint(x: 3, y: 4)).isMeaningful,
                 "a real drag is")

}

Check.suite("Units") {
    // Everything the app displays is CSS pixels — the unit Figma and CSS use — never device
    // pixels. A regression here would put every reading out by the display's scale factor.
    Check.expectEqual(Units.length(377), "377 px", "a length is rounded and labelled px")
    Check.expectEqual(Units.length(376.6), "377 px", "and rounds rather than truncates")
    Check.expectEqual(Units.length(0), "0 px", "zero is still a number")
    Check.expectEqual(
        Units.size(CGSize(width: 420, height: 240)),
        "420 × 240 px",
        "a size uses a multiplication sign, not an x"
    )
    Check.expectEqual(
        Units.size(CGSize(width: 419.5, height: 240.4)),
        "420 × 240 px",
        "and rounds both dimensions"
    )
    Check.expectEqual(Units.point(CGPoint(x: 1284, y: 662)), "1284, 662", "a position omits the unit")
    Check.expectEqual(Units.deviceSize(width: 840, height: 480), "840 × 480", "file dimensions omit it too")

    // The whole point: a 420 pt selection on a 2× display reads 420, not 840.
    let selectionOnRetina = CGRect(x: 0, y: 0, width: 420, height: 240)
    Check.expectEqual(
        Units.size(selectionOnRetina.size),
        "420 × 240 px",
        "a selection reports its CSS size, not its device size"
    )
    Check.expect(
        !Units.size(selectionOnRetina.size).contains("840"),
        "the device number never leaks into a reading"
    )
}

Check.finish()
