import AppKit
import Carbon.HIToolbox

/// A click-then-press control for choosing the capture shortcut.
///
/// Hand-rolled because the usual package for this (`KeyboardShortcuts`) cannot be built
/// without full Xcode — it uses `#Preview`, whose macro plugin ships only with Xcode.
final class HotKeyRecorderView: NSView {

    var onChange: ((HotKey) -> Void)?

    private var hotKey: HotKey
    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    init(hotKey: HotKey) {
        self.hotKey = hotKey
        super.init(frame: CGRect(x: 0, y: 0, width: 150, height: 26))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 26) }

    // MARK: - Interaction

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            return
        }

        let candidate = HotKey(
            keyCode: UInt32(event.keyCode),
            modifiers: HotKey.carbonModifiers(from: event.modifierFlags)
        )

        // Without ⌘, ⌃ or ⌥ the shortcut would fire while typing anywhere.
        guard candidate.hasRequiredModifier else {
            NSSound.beep()
            return
        }

        hotKey = candidate
        isRecording = false
        onChange?(candidate)
    }

    /// Swallow ⌘-anything while recording, or AppKit routes it to the menu instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)

        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.16)
            : NSColor.controlBackgroundColor).setFill()
        path.fill()

        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text = isRecording ? "Press a shortcut…" : hotKey.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isRecording ? .regular : .medium),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}
