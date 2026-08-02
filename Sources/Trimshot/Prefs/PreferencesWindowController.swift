import AppKit
import ServiceManagement

/// The one settings window. Small on purpose — everything here has a working default, so
/// most people never need to open it.
@MainActor
final class PreferencesWindowController: NSWindowController {

    /// Called when the shortcut changes so the app can re-register the global hotkey.
    var onHotKeyChange: ((HotKey) -> Void)?

    private let settings = Settings.shared
    private var saveDirectoryLabel: NSTextField?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Trimshot Settings"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.contentView = buildContent()
        window.center()
    }

    func show() {
        // The app is .accessory, so it has to claim focus for the window to accept input.
        NSApp.activate(ignoringOtherApps: true)
        refresh()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildContent() -> NSView {
        let recorder = HotKeyRecorderView(hotKey: settings.captureHotKey)
        recorder.onChange = { [weak self] hotKey in
            self?.settings.captureHotKey = hotKey
            self?.onHotKeyChange?(hotKey)
        }

        let directoryLabel = NSTextField(labelWithString: settings.saveDirectory.path)
        directoryLabel.lineBreakMode = .byTruncatingMiddle
        directoryLabel.textColor = .secondaryLabelColor
        directoryLabel.font = .systemFont(ofSize: 11)
        directoryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        saveDirectoryLabel = directoryLabel

        let chooseButton = NSButton(
            title: "Choose…",
            target: self,
            action: #selector(chooseSaveDirectory)
        )

        let directoryStack = NSStackView(views: [chooseButton, directoryLabel])
        directoryStack.orientation = .horizontal
        directoryStack.alignment = .centerY
        directoryStack.spacing = 8

        let formatPicker = NSPopUpButton()
        formatPicker.addItems(withTitles: ImageFormat.allCases.map { $0.rawValue.uppercased() })
        formatPicker.selectItem(at: ImageFormat.allCases.firstIndex(of: settings.imageFormat) ?? 0)
        formatPicker.target = self
        formatPicker.action = #selector(formatChanged)

        let copyToggle = NSButton(
            checkboxWithTitle: "Also copy to the clipboard when saving",
            target: self,
            action: #selector(copyToggled)
        )
        copyToggle.state = settings.copyAfterCapture ? .on : .off

        let loginToggle = NSButton(
            checkboxWithTitle: "Launch at login",
            target: self,
            action: #selector(launchAtLoginToggled)
        )
        loginToggle.state = LaunchAtLogin.isEnabled ? .on : .off

        let grid = NSGridView(views: [
            [label("Shortcut"), recorder],
            [label("Save to"), directoryStack],
            [label("Format"), formatPicker],
            [NSGridCell.emptyContentView, copyToggle],
            [NSGridCell.emptyContentView, loginToggle],
        ])
        grid.rowSpacing = 14
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(
            labelWithString: """
                In the overlay: drag to select, ⌘A for the whole screen, C copies the \
                colour under the cursor, ⌘Z undoes a mark, ⌘C copies, ⌘S saves, esc cancels.
                """
        )
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 3
        hint.preferredMaxLayoutWidth = 380
        hint.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        container.addSubview(hint)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -22),

            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            hint.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
            hint.topAnchor.constraint(greaterThanOrEqualTo: grid.bottomAnchor, constant: 18),
        ])

        return container
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func refresh() {
        saveDirectoryLabel?.stringValue = settings.saveDirectory.path
    }

    // MARK: - Actions

    @objc private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.saveDirectory = url
        refresh()
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        let formats = ImageFormat.allCases
        guard formats.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.imageFormat = formats[sender.indexOfSelectedItem]
    }

    @objc private func copyToggled(_ sender: NSButton) {
        settings.copyAfterCapture = sender.state == .on
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        do {
            try LaunchAtLogin.set(enabled: sender.state == .on)
        } catch {
            sender.state = LaunchAtLogin.isEnabled ? .on : .off
            NSAlert(error: error).runModal()
        }
    }
}

/// Login-item registration via `SMAppService`.
///
/// Only works for a properly bundled, signed app — running the bare binary from the build
/// directory will fail, which is why the toggle surfaces the error rather than silently
/// doing nothing.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func set(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Whether the app lives somewhere a login item can still point at next time the Mac
    /// boots.
    ///
    /// `build/` is wiped by every `scripts/bundle.sh`, so registering from there produces a
    /// login item that silently breaks. `/Applications` and `~/Applications` are the two
    /// places that survive.
    static var isInAPermanentLocation: Bool {
        let path = Bundle.main.bundlePath
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    /// Turns launch-at-login on the first time the app runs from a permanent location.
    /// Does nothing afterwards, so switching it off in Settings sticks.
    static func enableOnFirstRunFromPermanentLocation() {
        let settings = Settings.shared
        guard !settings.launchAtLoginConfigured, isInAPermanentLocation else { return }

        do {
            try set(enabled: true)
            settings.launchAtLoginConfigured = true
        } catch {
            // Not fatal — the Settings checkbox is still there to try again and show why.
            NSLog("launch-at-login registration failed: \(error.localizedDescription)")
        }
    }
}
