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
