import AppKit

/// A tooltip for the capture toolbar.
///
/// AppKit's own tooltips cannot be used here. They are drawn in a private window at an
/// ordinary level, and the toolbar sits above the capture overlay at `OverlayLevel.toolbar`
/// — so a system tooltip appears *behind* the capture, invisible, and there is no public API
/// to raise it. Rather than depend on being right about that, the toolbar carries its own.
///
/// Deliberately not a `NSWindow.toolTip` replacement in general: this exists for one bar,
/// shows one line, and never takes focus.
final class TipWindow: NSPanel {

    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        level = OverlayLevel.panel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        // Setting isFloatingPanel resets the level, so assign it after — the bug that hid the
        // toolbar itself for a whole session.
        level = OverlayLevel.panel
        sharingType = .none

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        background.appearance = NSAppearance(named: .vibrantDark)

        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: background.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -5),
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows `text` centred above `anchor`, which is in screen coordinates.
    func show(_ text: String, above anchor: CGRect) {
        label.stringValue = text
        let size = contentView?.fittingSize ?? .zero
        guard size.width > 0 else { return }

        var origin = CGPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.maxY + 8
        )
        // Flip below the bar when there is no room above it.
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main,
           origin.y + size.height > screen.frame.maxY - 4 {
            origin.y = anchor.minY - 8 - size.height
        }
        setFrame(CGRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
