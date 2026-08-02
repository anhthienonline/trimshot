import AppKit

/// Every window level the app uses, in one place.
///
/// Window ordering has been the single most repeated source of bugs here, three times over:
/// the toolbar rendered underneath the capture because `isFloatingPanel` silently reset its
/// level; the confirmation HUD was at `.statusBar`, a thousand levels below the overlay it
/// needed to appear over; and a file picker opened behind the overlay, invisible, while
/// `runModal()` froze the app in a modal session with nothing on screen to explain it.
///
/// All three were silent — no warning, no crash, just something that should be visible and
/// is not. Naming the levels together makes the stacking order something you can read, and
/// `ChromePreview` asserts it holds.
@MainActor
enum OverlayLevel {
    /// The frozen-screen overlay. `.screenSaver` clears the menu bar, the Dock, and
    /// full-screen apps.
    static let capture = NSWindow.Level.screenSaver

    /// The annotation toolbar, just above the capture it belongs to.
    static let toolbar = NSWindow.Level(rawValue: capture.rawValue + 1)

    /// Confirmation toasts, which have to be readable during a capture.
    static let hud = NSWindow.Level(rawValue: capture.rawValue + 1)

    /// Modal pickers. Above everything, because a modal window nobody can see is a hang.
    static let panel = NSWindow.Level(rawValue: capture.rawValue + 2)

    /// The invariant the app depends on. Checked by `--render-chrome`.
    static var isOrderedCorrectly: Bool {
        panel.rawValue > toolbar.rawValue
            && toolbar.rawValue >= capture.rawValue
            && hud.rawValue >= capture.rawValue
    }
}
