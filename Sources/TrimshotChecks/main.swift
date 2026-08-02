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

Check.finish()
