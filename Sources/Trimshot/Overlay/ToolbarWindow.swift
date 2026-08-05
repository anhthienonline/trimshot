import AppKit
import TrimshotCore

@MainActor
protocol ToolbarDelegate: AnyObject {
    func toolbarDidSelect(tool: AnnotationTool?)
    func toolbarDidSelect(color: PixelColor)
    func toolbarDidSelect(width: CGFloat)
    func toolbarDidPickCustomColor()
    func toolbarDidToggleMeasure()
    func toolbarDidTapUndo()
    func toolbarDidTapRecognizeText()
    func toolbarDidTapCopy()
    func toolbarDidTapSave()
    func toolbarDidTapClose()
}

/// The floating toolbar that appears once a selection settles.
///
/// A separate panel rather than a subview of the overlay: a selection can span two
/// displays, and the bar needs to be free to sit outside the selection — or outside the
/// display it started on — without fighting the overlay's own event handling.
///
/// `.nonactivatingPanel` is what keeps ⌘C, ⌘S and esc working: clicking a button must
/// not take key status away from the overlay view that handles them.
final class ToolbarWindow: NSPanel {

    private let bar: ToolbarView

    init(delegate: ToolbarDelegate) {
        bar = ToolbarView(delegate: delegate)
        super.init(
            contentRect: CGRect(origin: .zero, size: bar.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        sharingType = .none
        // The hover tips depend on mouseMoved reaching the bar, and this defaults to false —
        // the same omission that froze the measure tool for a whole session.
        acceptsMouseMovedEvents = true

        // Order matters, and getting it wrong hides the toolbar completely: setting
        // `isFloatingPanel` overwrites `level` with `.floating` (3), far below the overlay.
        // Assign the level last. See OverlayLevel.
        isFloatingPanel = true
        level = OverlayLevel.toolbar

        contentView = bar
        setContentSize(bar.fittingSize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func orderOut(_ sender: Any?) {
        bar.hideTip()
        super.orderOut(sender)
    }

    func update(
        tool: AnnotationTool?,
        color: PixelColor,
        width: CGFloat,
        canUndo: Bool,
        isMeasuring: Bool
    ) {
        bar.update(tool: tool, color: color, width: width, canUndo: canUndo, isMeasuring: isMeasuring)
    }

    /// Parks the bar just below the selection, flipping above it — and finally inside it —
    /// when there is no room on the display the selection ends on.
    func position(below selection: CGRect, on screen: NSScreen) {
        let size = bar.fittingSize
        let gap: CGFloat = 10
        let margin: CGFloat = 8
        let visible = screen.visibleFrame

        var origin = CGPoint(
            x: selection.midX - size.width / 2,
            y: selection.minY - gap - size.height
        )

        if origin.y < visible.minY + margin {
            origin.y = selection.maxY + gap
        }
        if origin.y + size.height > visible.maxY - margin {
            origin.y = max(visible.minY + margin, selection.minY + gap)
        }

        origin.x = min(
            max(origin.x, visible.minX + margin),
            max(visible.minX + margin, visible.maxX - size.width - margin)
        )

        setFrame(CGRect(origin: origin, size: size), display: true)
    }
}
