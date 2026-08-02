import AppKit
import TrimshotCore

enum OverlayAction {
    case copy
    case save
    case saveAs
}

/// Owns a capture session: the frozen bitmaps, one overlay window per display, the
/// single selection rect shared between them, and the annotations drawn on top.
///
/// The selection lives here rather than in any one view because a drag can start on one
/// display and end on another — every view renders the same global rect in its own
/// coordinates.
@MainActor
final class OverlayCoordinator: NSObject {
    static let shared = OverlayCoordinator()

    private(set) var isActive = false

    private var windows: [OverlayWindow] = []
    private var shots: [DisplayShot] = []
    /// AppKit global points.
    private(set) var selection: CGRect?
    /// True once a drag has finished, so handles and the toolbar show.
    private(set) var isSettled = false
    private var previousApp: NSRunningApplication?

    // MARK: Annotation state

    private(set) var annotations = AnnotationStore()
    /// The mark currently being dragged out, not yet committed.
    private(set) var draft: Annotation?
    private(set) var activeTool: AnnotationTool?
    /// Measure mode: the overlay reports the gap the cursor sits in instead of waiting for a
    /// selection. Toggled with M.
    private(set) var isMeasuring = false
    /// The A→B ruler drag, kept after mouse-up so the reading can be read.
    private(set) var ruler: RulerReading?
    /// The bitmap the image tool will place, loaded when the tool is selected so the drag
    /// itself already previews the real picture.
    private(set) var pendingImage: AnnotationImage?
    /// Index of the mark being edited, if any. Placed images get selected on arrival so their
    /// handles are there immediately rather than after a discovery step.
    private(set) var selectedMark: Int?
    private(set) var strokeColor = PixelColor(red: 255, green: 59, blue: 48)
    /// The thinnest of the three. A heavy default covers the detail you are annotating.
    private(set) var strokeWidth: CGFloat = 2

    private var toolbar: ToolbarWindow?

    private override init() { super.init() }

    // MARK: - Session lifecycle

    func begin(with shots: [DisplayShot]) {
        guard !isActive else { return }
        isActive = true
        self.shots = shots
        self.selection = nil
        self.isSettled = false
        self.annotations.removeAll()
        self.draft = nil
        self.activeTool = nil
        self.isMeasuring = false
        self.pendingImage = nil
        selectedMark = nil
        previousApp = NSWorkspace.shared.frontmostApplication

        windows = shots.map { OverlayWindow(shot: $0, coordinator: self) }
        for window in windows {
            window.orderFrontRegardless()
        }

        // A .accessory app is not frontmost, so it has to claim focus explicitly or the
        // overlay never receives key events.
        NSApp.activate(ignoringOtherApps: true)

        let mouse = NSEvent.mouseLocation
        if let focus = windows.first(where: { $0.frame.contains(mouse) }) ?? windows.first {
            focus.makeKeyAndOrderFront(nil)
            focus.makeFirstResponder(focus.rootView)
        }

        updatePointer(mouse)
    }

    func cancel() {
        guard isActive else { return }
        teardown()
    }

    func finish(with action: OverlayAction) {
        guard isActive, let image = composeImage() else {
            NSSound.beep()
            return
        }

        teardown()
        perform(action, on: image)
    }

    /// The selection with its annotations baked in, at full capture resolution.
    private func composeImage() -> CGImage? {
        guard
            let selection,
            let cropped = ImageCompositor.crop(globalRect: selection, from: shots)
        else { return nil }

        guard !annotations.isEmpty else { return cropped }

        let scale = ScreenGeometry.renderScale(
            forGlobalRect: selection,
            among: shots.map(\.geometry)
        )
        return AnnotationRenderer.flatten(
            annotations.annotations,
            onto: cropped,
            cropRect: selection,
            scale: scale
        ) ?? cropped
    }

    private func teardown() {
        // NSColorPanel is shared and app-wide, and this raised it to OverlayLevel.panel.
        // Left open it would float above every window on the system for the rest of the
        // session, so it has to be put away with the overlay that summoned it.
        if NSColorPanel.sharedColorPanelExists {
            let panel = NSColorPanel.shared
            panel.setTarget(nil)
            panel.setAction(nil)
            panel.orderOut(nil)
        }

        toolbar?.orderOut(nil)
        toolbar = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows = []
        shots = []
        selection = nil
        isSettled = false
        isActive = false
        annotations.removeAll()
        draft = nil
        activeTool = nil
        isMeasuring = false
        ruler = nil
        pendingImage = nil
        selectedMark = nil

        // Hand focus back to whatever the user was actually working in.
        previousApp?.activate()
        previousApp = nil
    }

    // MARK: - Selection state

    func updateSelection(_ rect: CGRect?) {
        selection = rect
        if rect == nil { isSettled = false }
        for window in windows {
            window.rootView?.apply(selection: rect)
        }
        repositionToolbar()
    }

    func setSettled(_ settled: Bool) {
        guard settled != isSettled else { return }
        isSettled = settled
        for window in windows {
            window.rootView?.apply(isSettled: settled)
        }
        settled ? showToolbar() : hideToolbar()
    }

    func updatePointer(_ point: CGPoint?) {
        for window in windows {
            window.rootView?.apply(pointer: point)
        }
    }

    /// The union of every captured display, in AppKit global points — the area a selection
    /// is allowed to occupy.
    var displayBounds: CGRect? {
        shots.map(\.geometry.frame).reduce(nil) { union, frame in
            union.map { $0.union(frame) } ?? frame
        }
    }

    func setRuler(_ measurement: RulerReading?) {
        ruler = measurement
        for window in windows {
            window.rootView?.apply(ruler: measurement)
        }
    }

    func toggleMeasuring() {
        isMeasuring.toggle()
        // Leaving a stale reading behind would be a number with nothing to do with the mode
        // you are now in.
        if !isMeasuring { setRuler(nil) }
        for window in windows {
            window.rootView?.apply(isMeasuring: isMeasuring)
        }
        refreshToolbar()
        HUD.show(
            isMeasuring ? "Ruler on — hover to read a gap, drag to measure A→B" : "Ruler off",
            duration: .milliseconds(1600)
        )
    }

    func selectWholeDisplay(_ geometry: DisplayGeometry) {
        updateSelection(geometry.frame)
        setSettled(true)
    }

    /// Feedback for the copy-colour shortcut, which does not end the session.
    func flashColorCopied(_ hex: String) {
        HUD.show("Copied  \(hex)", duration: .milliseconds(900))
    }

    // MARK: - Annotations

    func setDraft(_ annotation: Annotation?) {
        draft = annotation
        broadcastAnnotations()
    }

    func commitDraft() {
        if let draft, draft.isMeaningful {
            annotations.add(draft)
        }
        draft = nil
        broadcastAnnotations()
        refreshToolbar()
    }

    func undoAnnotation() {
        guard annotations.undo() else { return }
        broadcastAnnotations()
        refreshToolbar()
    }

    func redoAnnotation() {
        guard annotations.redo() else { return }
        broadcastAnnotations()
        refreshToolbar()
    }

    private func broadcastAnnotations() {
        let all = annotations.annotations
        for window in windows {
            window.rootView?.apply(annotations: all, draft: draft)
            window.rootView?.apply(selectedMark: selectedMark.flatMap {
                all.indices.contains($0) ? all[$0].boundingRect : nil
            })
        }
    }

    // MARK: - Editing a placed mark

    func selectMark(_ index: Int?) {
        selectedMark = index.flatMap { annotations.annotations.indices.contains($0) ? $0 : nil }
        broadcastAnnotations()
    }

    /// The mark under a point, so a click can pick one up.
    func markIndex(at point: CGPoint) -> Int? {
        annotations.indexOfMark(at: point)
    }

    func mark(at index: Int) -> Annotation? {
        annotations.annotations.indices.contains(index) ? annotations.annotations[index] : nil
    }

    func updateMark(_ index: Int, to annotation: Annotation) {
        annotations.replace(at: index, with: annotation)
        broadcastAnnotations()
    }

    func deleteSelectedMark() {
        guard let selectedMark else { return }
        annotations.remove(at: selectedMark)
        self.selectedMark = nil
        broadcastAnnotations()
        refreshToolbar()
    }

    // MARK: - Toolbar

    private func showToolbar() {
        guard let selection else { return }

        let panel = toolbar ?? ToolbarWindow(delegate: self)
        toolbar = panel
        panel.update(
            tool: activeTool,
            color: strokeColor,
            width: strokeWidth,
            canUndo: annotations.canUndo,
            isMeasuring: isMeasuring
        )
        position(panel, for: selection)
        panel.orderFrontRegardless()
    }

    private func hideToolbar() {
        toolbar?.orderOut(nil)
    }

    private func repositionToolbar() {
        guard let toolbar, let selection, isSettled else { return }
        position(toolbar, for: selection)
    }

    private func position(_ panel: ToolbarWindow, for selection: CGRect) {
        // Anchor to the display holding the selection's bottom edge, which is where the
        // bar wants to sit.
        let anchor = CGPoint(x: selection.midX, y: selection.minY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) }
            ?? NSScreen.screens.first { !$0.frame.intersection(selection).isEmpty }
            ?? NSScreen.main
        guard let screen else { return }
        panel.position(below: selection, on: screen)
    }

    private func refreshToolbar() {
        toolbar?.update(
            tool: activeTool,
            color: strokeColor,
            width: strokeWidth,
            canUndo: annotations.canUndo,
            isMeasuring: isMeasuring
        )
    }

    // MARK: - Output

    private func perform(_ action: OverlayAction, on image: CGImage) {
        let settings = Settings.shared

        switch action {
        case .copy:
            ClipboardService.copy(image)
            // The selection, not the bitmap: a Retina file is 2× these numbers, and the
            // number worth confirming is the one the user just drew.
            HUD.show("Copied  " + (selection.map { Units.size($0.size) }
                ?? Units.deviceSize(width: image.width, height: image.height)))

        case .save:
            do {
                let url = try FileSaver.save(
                    image,
                    to: settings.saveDirectory,
                    format: settings.imageFormat
                )
                if settings.copyAfterCapture {
                    ClipboardService.copy(image)
                }
                HUD.show("Saved  \(url.lastPathComponent)")
            } catch {
                present(error)
            }

        case .saveAs:
            do {
                if let url = try FileSaver.saveWithPanel(image, format: settings.imageFormat) {
                    HUD.show("Saved  \(url.lastPathComponent)")
                }
            } catch {
                present(error)
            }
        }
    }

    /// OCR reads the selection *without* annotations — marks drawn on top would only
    /// confuse the recogniser — and leaves the session open so you can still copy the
    /// image afterwards.
    func recognizeText() {
        guard
            let selection,
            let cropped = ImageCompositor.crop(globalRect: selection, from: shots)
        else {
            NSSound.beep()
            return
        }

        HUD.show("Reading text…", duration: .seconds(20))

        Task { @MainActor in
            do {
                let text = try await OCRService.recognizeText(in: cropped)
                ClipboardService.copy(text: text)
                let lines = text.split(separator: "\n").count
                HUD.show("Copied text  \(lines) line\(lines == 1 ? "" : "s")")
            } catch {
                HUD.show(error.localizedDescription)
            }
        }
    }

    /// Swaps in whatever image is on the pasteboard while the image tool is armed.
    func pasteImageToPlace() {
        guard activeTool == .image else { return }
        guard let image = ClipboardService.readImage() else {
            HUD.show("No image on the clipboard", duration: .milliseconds(1500))
            return
        }
        pendingImage = AnnotationImage(image)
        HUD.show("Using the clipboard image — drag to place it", duration: .milliseconds(1500))
    }

    private func present(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

// MARK: - ToolbarDelegate

extension OverlayCoordinator: ToolbarDelegate {

    func toolbarDidSelect(tool: AnnotationTool?) {
        // The picture is chosen before the drag so the drag itself previews the real image.
        // The picker is asynchronous, so the tool arms in the callback rather than here.
        if tool == .image {
            FileSaver.chooseImage { [weak self] chosen, cancelled in
                guard let self else { return }
                guard self.isActive else {
                    // The capture ended while the picker was open.
                    return
                }
                if !cancelled, chosen == nil {
                    HUD.show("Could not read that image file")
                    self.refreshToolbar()
                    return
                }
                guard let chosen else {
                    // Cancelling is a normal outcome, not an error worth a warning — but the
                    // toolbar still has to be told, or the button it just highlighted stays
                    // highlighted for a tool that never armed.
                    HUD.show("No image chosen", duration: .milliseconds(1200))
                    self.refreshToolbar()
                    return
                }
                self.pendingImage = AnnotationImage(chosen)
                self.arm(.image)
                // Place it straight away. Arming the tool and waiting for a drag looks
                // identical to nothing having happened, which is how this read the first
                // time: choose a file, panel closes, blank screen.
                self.placeImageInMiddleOfSelection()
            }
            return
        }

        pendingImage = nil
        arm(tool)
    }

    /// Drops the pending image into the middle of the selection at 60% of its size.
    ///
    /// The tool stays armed afterwards, so dragging a rect still places another one exactly
    /// where you want it — this only removes the case where choosing a file appeared to do
    /// nothing at all.
    private func placeImageInMiddleOfSelection() {
        guard let selection, let image = pendingImage else { return }

        let box = selection.insetBy(dx: selection.width * 0.2, dy: selection.height * 0.2)
        let size = CGSize(width: image.cgImage.width, height: image.cgImage.height)
        let rect = AnnotationRenderer.fit(size, in: box)
        guard rect.width >= 2, rect.height >= 2 else {
            HUD.show("The selection is too small to place an image in")
            return
        }

        annotations.add(
            Annotation(
                tool: .image,
                points: [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)],
                color: strokeColor,
                lineWidth: 0,
                image: image
            )
        )
        // Disarm the tool and select what was just placed: with the tool still armed, a drag
        // on the new image would draw *another* one instead of moving it.
        arm(nil)
        selectMark(annotations.annotations.count - 1)
        HUD.show("Drag to move it, or a handle to resize  ·  ⌫ removes it")
    }

    private func arm(_ tool: AnnotationTool?) {
        activeTool = tool
        refreshToolbar()
        for window in windows {
            window.rootView?.apply(activeTool: tool)
        }
    }

    func toolbarDidSelect(color: PixelColor) {
        strokeColor = color
        refreshToolbar()
    }

    func toolbarDidSelect(width: CGFloat) {
        strokeWidth = width
        refreshToolbar()
    }

    func toolbarDidToggleMeasure() {
        toggleMeasuring()
    }

    func toolbarDidPickCustomColor() {
        let panel = NSColorPanel.shared
        // Same trap as the file picker: a panel defaults to level 0 and the overlay sits at
        // .screenSaver, so without this it opens behind the capture, invisible.
        panel.level = OverlayLevel.panel
        panel.isContinuous = true
        panel.showsAlpha = false
        panel.color = NSColor(
            srgbRed: CGFloat(strokeColor.red) / 255,
            green: CGFloat(strokeColor.green) / 255,
            blue: CGFloat(strokeColor.blue) / 255,
            alpha: 1
        )
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        panel.orderFrontRegardless()
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        // sRGB explicitly: a colour picked in another space would round-trip differently and
        // the hex the user chose is the hex they expect to get.
        guard let picked = sender.color.usingColorSpace(.sRGB) else { return }
        strokeColor = PixelColor(
            red: UInt8((picked.redComponent * 255).rounded()),
            green: UInt8((picked.greenComponent * 255).rounded()),
            blue: UInt8((picked.blueComponent * 255).rounded())
        )
        refreshToolbar()
    }

    func toolbarDidTapUndo() {
        undoAnnotation()
    }

    func toolbarDidTapRecognizeText() {
        recognizeText()
    }

    func toolbarDidTapCopy() {
        finish(with: .copy)
    }

    func toolbarDidTapSave() {
        finish(with: .save)
    }

    func toolbarDidTapClose() {
        cancel()
    }
}
