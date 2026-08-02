import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var preferences: PreferencesWindowController?
    private var shortcutMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        registerHotKey()
        LaunchAtLogin.enableOnFirstRunFromPermanentLocation()
    }

    /// Opening the app again while it is already running.
    ///
    /// Being an `LSUIElement` app there is no window and no Dock icon, so macOS delivers
    /// this and otherwise *nothing happens at all* — double-clicking in Finder looks like a
    /// failed launch. Say where the app actually lives instead of staying silent.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let shortcut = Settings.shared.captureHotKey.displayString
        HUD.show(
            "Already running — press \(shortcut), or use the menu bar icon",
            duration: .seconds(3)
        )
        flashStatusItem()
        return true
    }

    /// Blinks the menu bar icon so it can be picked out of a crowded menu bar.
    private func flashStatusItem() {
        guard let button = statusItem?.button else { return }

        var remaining = 6
        func toggle() {
            guard remaining > 0 else {
                button.highlight(false)
                return
            }
            button.highlight(remaining % 2 == 0)
            remaining -= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { toggle() }
        }
        toggle()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: "Trimshot"
        )
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let capture = NSMenuItem(
            title: "Capture Area",
            action: #selector(captureArea),
            keyEquivalent: ""
        )
        capture.target = self
        menu.addItem(capture)

        let shortcut = NSMenuItem()
        shortcut.title = "Shortcut: \(Settings.shared.captureHotKey.displayString)"
        shortcut.isEnabled = false
        shortcutMenuItem = shortcut
        menu.addItem(shortcut)

        menu.addItem(.separator())

        let reveal = NSMenuItem(
            title: "Open Save Folder",
            action: #selector(openSaveFolder),
            keyEquivalent: ""
        )
        reveal.target = self
        menu.addItem(reveal)

        let prefs = NSMenuItem(
            title: "Settings…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Trimshot",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Hotkey

    private func registerHotKey() {
        applyHotKey(Settings.shared.captureHotKey)
    }

    // MARK: - Actions

    @objc private func captureArea() {
        // Ignore a second trigger while the overlay is already up, otherwise the
        // hotkey would stack sessions on top of each other.
        guard !OverlayCoordinator.shared.isActive else { return }

        Task { @MainActor in
            guard PermissionGate.ensureScreenRecordingAccess() else { return }

            do {
                let shots = try await ScreenCapturer.captureAllDisplays()
                OverlayCoordinator.shared.begin(with: shots)
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func openSaveFolder() {
        NSWorkspace.shared.open(Settings.shared.saveDirectory)
    }

    @objc private func openPreferences() {
        let controller = preferences ?? PreferencesWindowController()
        controller.onHotKeyChange = { [weak self] hotKey in
            self?.applyHotKey(hotKey)
        }
        preferences = controller
        controller.show()
    }

    /// Re-registers the global hotkey and reflects it in the menu.
    private func applyHotKey(_ hotKey: HotKey) {
        let registered = HotKeyManager.shared.register(hotKey) { [weak self] in
            self?.captureArea()
        }
        shortcutMenuItem?.title = registered
            ? "Shortcut: \(hotKey.displayString)"
            : "Shortcut: \(hotKey.displayString) — unavailable"

        if !registered {
            HUD.show("\(hotKey.displayString) is already taken by another app")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
