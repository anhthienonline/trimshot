import AppKit
import TrimshotCore

/// One borderless window per display, sitting above everything — including apps in
/// full screen — and showing that display's frozen bitmap.
final class OverlayWindow: NSWindow {

    init(shot: DisplayShot, coordinator: OverlayCoordinator) {
        super.init(
            contentRect: shot.geometry.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = OverlayLevel.capture
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        ignoresMouseEvents = false
        // Without this, `mouseMoved:` is never delivered and the cursor position only updates
        // on a click or a drag — which froze the measure-mode dimension lines at wherever the
        // pointer happened to be when the overlay opened. A feature that exists to follow the
        // cursor looks completely broken without it.
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        // Nothing here should end up in a Mission Control or window-list screenshot.
        sharingType = .none

        contentView = OverlayRootView(shot: shot, coordinator: coordinator)
        setFrame(shot.geometry.frame, display: false)
    }

    // Borderless windows refuse key status by default, which would swallow ESC.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var rootView: OverlayRootView? { contentView as? OverlayRootView }
}
