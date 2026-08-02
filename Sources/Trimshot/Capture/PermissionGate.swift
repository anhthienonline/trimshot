import AppKit
import CoreGraphics

/// Screen Recording is the one permission this app cannot work without.
///
/// macOS only ever shows its own prompt once per app identity. After that a denial is
/// permanent until the user changes it in System Settings, so on the second attempt we
/// stop asking and take them there.
@MainActor
enum PermissionGate {

    static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Returns true when capture may proceed. Shows the system prompt on first use and
    /// an explanatory alert afterwards.
    static func ensureScreenRecordingAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }

        // Triggers the system prompt the first time; returns false immediately on every
        // later call, because macOS remembers the denial.
        if CGRequestScreenCaptureAccess() { return true }

        presentDeniedAlert()
        return false
    }

    private static func presentDeniedAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Trimshot needs Screen Recording access"
        alert.informativeText = """
            macOS requires this permission to capture the screen. Enable \
            “Trimshot” under Privacy & Security › Screen & System Audio \
            Recording, then trigger the shortcut again.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )!
        NSWorkspace.shared.open(url)
    }
}
