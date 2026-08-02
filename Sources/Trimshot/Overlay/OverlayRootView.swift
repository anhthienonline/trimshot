import AppKit
import Carbon.HIToolbox
import TrimshotCore

/// Fills one display: shows the frozen bitmap and owns all mouse and key handling.
///
/// The bitmap is set as the backing layer's `contents` rather than drawn in `draw(_:)`
/// so that redrawing the selection during a drag never re-blits a 2880×1800 image. The
/// dim and the marching-ants chrome live in a child view stacked above it.
final class OverlayRootView: NSView {

    /// What the current mouse-down is doing. A settled selection can be resized by a
    /// handle or moved from the inside, so a plain "am I dragging" flag is not enough.
    private enum Interaction {
        case none
        /// Drawing a fresh selection from `anchor`.
        case drawing(anchor: CGPoint)
        /// Dragging one handle; the rest of the rect stays put.
        case resizing(handle: SelectionHandle, rect: CGRect)
        /// Sliding a settled selection; `grabOffset` is cursor − rect origin.
        case moving(grabOffset: CGSize, size: CGSize)
        /// Dragging out an annotation with the active tool.
        case annotating(tool: AnnotationTool, points: [CGPoint])
    }

    private let shot: DisplayShot
    private weak var coordinator: OverlayCoordinator?
    private let chrome: SelectionChromeView
    private let magnifier: Magnifier

    private var interaction: Interaction = .none

    /// Live editor for the text tool, plus where it was placed.
    private var textField: NSTextField?
    private var textFieldOrigin: CGPoint?
    private var textFieldFontSize: CGFloat = 18

    init(shot: DisplayShot, coordinator: OverlayCoordinator) {
        self.shot = shot
        self.coordinator = coordinator
        self.chrome = SelectionChromeView(shot: shot)
        self.magnifier = Magnifier(shot: shot)
        super.init(frame: CGRect(origin: .zero, size: shot.geometry.frame.size))

        wantsLayer = true
        layer?.contents = shot.image
        layer?.contentsGravity = .resize
        layer?.contentsScale = shot.geometry.scale

        chrome.autoresizingMask = [.width, .height]
        chrome.frame = bounds
        addSubview(chrome)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - State from the coordinator

    func apply(selection: CGRect?) {
        chrome.selection = selection
        // The grab zones move with the selection. Without this, an arrow-key nudge leaves
        // the move and resize cursors sitting where the selection *used* to be, so the
        // pointer stops telling the truth about what a drag will do.
        window?.invalidateCursorRects(for: self)
    }

    func apply(pointer: CGPoint?) {
        chrome.pointer = pointer
    }

    func apply(isSettled: Bool) {
        chrome.isSettled = isSettled
        window?.invalidateCursorRects(for: self)
    }

    func apply(annotations: [Annotation], draft: Annotation?) {
        chrome.annotations = annotations
        chrome.draft = draft
    }

    func apply(isMeasuring: Bool) {
        chrome.isMeasuring = isMeasuring
    }

    func apply(activeTool: AnnotationTool?) {
        chrome.activeTool = activeTool
        commitPendingText()
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        guard let selection = coordinator?.selection, chrome.isSettled else {
            addCursorRect(bounds, cursor: .crosshair)
            return
        }

        addCursorRect(bounds, cursor: .crosshair)

        // With a tool active the selection is a canvas, so no move or resize affordances.
        if let tool = coordinator?.activeTool {
            let local = toLocal(selection)
            addCursorRect(local, cursor: tool == .text ? .iBeam : .crosshair)
            return
        }

        let local = toLocal(selection)
        addCursorRect(local.insetBy(dx: 6, dy: 6), cursor: .openHand)

        // NSCursor has no public diagonal resize cursors, so corners keep the crosshair
        // and only the edges get a directional hint.
        for handle in [SelectionHandle.left, .right] {
            addCursorRect(handleRect(handle, on: local), cursor: .resizeLeftRight)
        }
        for handle in [SelectionHandle.top, .bottom] {
            addCursorRect(handleRect(handle, on: local), cursor: .resizeUpDown)
        }
    }

    private func handleRect(_ handle: SelectionHandle, on rect: CGRect) -> CGRect {
        let centre = handle.point(in: rect)
        return CGRect(x: centre.x - 6, y: centre.y - 6, width: 12, height: 12)
    }

    // MARK: - Coordinates

    /// Converts a mouse event to AppKit global points. Valid even once the drag has left
    /// this window, because AppKit keeps routing drags to the originating view.
    private func globalPoint(for event: NSEvent) -> CGPoint {
        guard let window else { return .zero }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func toLocal(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -shot.geometry.frame.minX, dy: -shot.geometry.frame.minY)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = globalPoint(for: event)
        coordinator?.updatePointer(point)
        commitPendingText()

        // With a tool active, dragging inside the selection draws instead of adjusting.
        if let tool = coordinator?.activeTool,
           let selection = coordinator?.selection,
           chrome.isSettled,
           selection.contains(point) {
            if tool == .text {
                beginTextEntry(at: point)
            } else {
                interaction = .annotating(tool: tool, points: [point, point])
                updateDraft(tool: tool, points: [point, point])
            }
            return
        }

        if let selection = coordinator?.selection, chrome.isSettled {
            if let handle = SelectionHandle.hitTest(point, in: selection) {
                interaction = .resizing(handle: handle, rect: selection)
                return
            }
            if selection.contains(point) {
                interaction = .moving(
                    grabOffset: CGSize(
                        width: point.x - selection.minX,
                        height: point.y - selection.minY
                    ),
                    size: selection.size
                )
                return
            }
        }

        // Anywhere else starts over.
        interaction = .drawing(anchor: point)
        coordinator?.setSettled(false)
        coordinator?.updateSelection(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = globalPoint(for: event)
        coordinator?.updatePointer(point)

        switch interaction {
        case .none:
            break
        case .drawing(let anchor):
            coordinator?.updateSelection(ScreenGeometry.normalizedRect(from: anchor, to: point))
        case .resizing(let handle, let rect):
            coordinator?.updateSelection(handle.resize(rect, to: point))
        case .moving(let grabOffset, let size):
            let origin = CGPoint(
                x: (point.x - grabOffset.width).rounded(),
                y: (point.y - grabOffset.height).rounded()
            )
            coordinator?.updateSelection(CGRect(origin: origin, size: size))
        case .annotating(let tool, var points):
            if tool.isFreehand {
                points.append(point)
            } else {
                // Shape tools only ever need where the drag started and where it is now.
                points = [points[0], point]
            }
            interaction = .annotating(tool: tool, points: points)
            updateDraft(tool: tool, points: points)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = globalPoint(for: event)

        switch interaction {
        case .none:
            return
        case .drawing(let anchor):
            let rect = ScreenGeometry.normalizedRect(from: anchor, to: point)
            // A plain click is not a selection — treat anything smaller than a few points
            // as an accident and clear it rather than producing a 1-pixel capture.
            if rect.width >= 3 && rect.height >= 3 {
                coordinator?.updateSelection(rect)
                coordinator?.setSettled(true)
            } else {
                coordinator?.updateSelection(nil)
            }
        case .resizing, .moving:
            coordinator?.setSettled(true)
        case .annotating:
            coordinator?.commitDraft()
        }

        interaction = .none
        window?.invalidateCursorRects(for: self)
    }

    override func mouseMoved(with event: NSEvent) {
        coordinator?.updatePointer(globalPoint(for: event))
    }

    override func rightMouseDown(with event: NSEvent) {
        coordinator?.cancel()
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            coordinator?.cancel()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            coordinator?.finish(with: .copy)
        case kVK_ANSI_C where event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty:
            copyColorUnderCursor()
        case kVK_ANSI_M where event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty:
            coordinator?.toggleMeasuring()
        case kVK_LeftArrow:
            nudge(dx: -step(for: event), dy: 0, event: event)
        case kVK_RightArrow:
            nudge(dx: step(for: event), dy: 0, event: event)
        case kVK_UpArrow:
            nudge(dx: 0, dy: step(for: event), event: event)
        case kVK_DownArrow:
            nudge(dx: 0, dy: -step(for: event), event: event)
        default:
            super.keyDown(with: event)
        }
    }

    /// The app has no menu bar of its own, so ⌘C / ⌘S have to be caught here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            coordinator?.finish(with: .copy)
            return true
        case "s":
            coordinator?.finish(with: event.modifierFlags.contains(.shift) ? .saveAs : .save)
            return true
        case "a":
            coordinator?.selectWholeDisplay(shot.geometry)
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                coordinator?.redoAnnotation()
            } else {
                coordinator?.undoAnnotation()
            }
            return true
        default:
            return false
        }
    }

    private func step(for event: NSEvent) -> CGFloat {
        event.modifierFlags.contains(.shift) ? 10 : 1
    }

    /// Arrows move the selection; ⌥ + arrows drag its bottom-right corner.
    ///
    /// Both axes follow the arrow: ⌥→ moves the right edge right, ⌥↓ moves the bottom edge
    /// down — so each grows the selection, and ⌥← / ⌥↑ shrink it.
    private func nudge(dx: CGFloat, dy: CGFloat, event: NSEvent) {
        guard let coordinator, let selection = coordinator.selection else { return }

        let moved: CGRect
        if event.modifierFlags.contains(.option) {
            // dy is positive for ↑. Moving the *bottom* edge down means lowering minY and
            // adding the same amount to the height, which keeps the top edge pinned.
            let height = max(1, selection.height - dy)
            moved = CGRect(
                x: selection.minX,
                y: selection.maxY - height,
                width: max(1, selection.width + dx),
                height: height
            )
        } else {
            moved = selection.offsetBy(dx: dx, dy: dy, clampedTo: coordinator.displayBounds)
        }

        coordinator.updateSelection(moved)
        coordinator.setSettled(true)
    }

    // MARK: - Annotation drafts

    private func updateDraft(tool: AnnotationTool, points: [CGPoint]) {
        guard let coordinator else { return }
        coordinator.setDraft(
            Annotation(
                tool: tool,
                points: points,
                color: coordinator.strokeColor,
                lineWidth: tool == .pixelate ? max(6, coordinator.strokeWidth * 2)
                    : coordinator.strokeWidth,
                image: tool == .image ? coordinator.pendingImage : nil
            )
        )
    }

    // MARK: - Text tool

    /// Text is typed into a real `NSTextField` placed over the capture, so it gets the
    /// system's editing, IME and Vietnamese input behaviour for free. On commit it is
    /// converted into an `Annotation` and the field goes away.
    private func beginTextEntry(at globalPoint: CGPoint) {
        guard let coordinator else { return }

        let fontSize = max(14, coordinator.strokeWidth * 4)
        let field = NSTextField(frame: .zero)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = NSColor(
            srgbRed: CGFloat(coordinator.strokeColor.red) / 255,
            green: CGFloat(coordinator.strokeColor.green) / 255,
            blue: CGFloat(coordinator.strokeColor.blue) / 255,
            alpha: 1
        )
        field.placeholderString = "Type, then ⏎"
        field.target = self
        field.action = #selector(textFieldCommitted)

        let local = CGPoint(
            x: globalPoint.x - shot.geometry.frame.minX,
            y: globalPoint.y - shot.geometry.frame.minY
        )
        let height = fontSize * 1.5
        field.frame = CGRect(x: local.x, y: local.y - height, width: 260, height: height)

        addSubview(field)
        textField = field
        textFieldOrigin = globalPoint
        textFieldFontSize = fontSize
        window?.makeFirstResponder(field)
    }

    @objc private func textFieldCommitted() {
        commitPendingText()
    }

    /// Turns whatever is in the text field into an annotation and dismisses it. Safe to
    /// call when there is no field.
    private func commitPendingText() {
        guard let field = textField, let origin = textFieldOrigin, let coordinator else { return }

        let text = field.stringValue
        textField = nil
        textFieldOrigin = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)

        guard !text.isEmpty else { return }
        coordinator.setDraft(
            Annotation(
                tool: .text,
                points: [origin],
                color: coordinator.strokeColor,
                lineWidth: textFieldFontSize,
                text: text
            )
        )
        coordinator.commitDraft()
    }

    private func copyColorUnderCursor() {
        let point = NSEvent.mouseLocation
        guard
            shot.geometry.frame.contains(point),
            let hex = magnifier.colorHex(at: point)
        else { return }

        ClipboardService.copy(text: hex)
        coordinator?.flashColorCopied(hex)
    }
}
