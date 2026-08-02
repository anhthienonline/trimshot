import AppKit

/// A brief, non-interactive confirmation toast.
///
/// A menu-bar-only app has nowhere to show feedback, and a capture that silently
/// succeeds feels broken — so every completed action says what it did and, when saving,
/// where the file went.
@MainActor
enum HUD {
    private static var window: NSWindow?
    private static var dismissTask: Task<Void, Never>?

    static func show(_ message: String, duration: Duration = .milliseconds(1600)) {
        dismissTask?.cancel()
        window?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let padding = NSSize(width: 18, height: 12)
        let size = NSSize(
            width: label.frame.width + padding.width * 2,
            height: label.frame.height + padding.height * 2
        )

        let screen = screenUnderMouse()
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + screen.frame.height * 0.14
        )

        let panel = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Above the capture overlay, which sits at .screenSaver — otherwise the
        // copy-colour confirmation would be drawn underneath it and never seen.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        label.frame.origin = NSPoint(x: padding.width, y: padding.height)
        background.addSubview(label)
        panel.contentView = background
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        window = panel
        dismissTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            } completionHandler: {
                // AppKit runs this on the main thread but types it as a plain closure.
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    if window === panel { window = nil }
                }
            }
        }
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
