import AppKit
import ServiceManagement

/// `Trimshot --dump-status`
///
/// Prints the things that are otherwise invisible from outside the app: whether the Screen
/// Recording grant survived being moved or rebuilt, and whether the login item is actually
/// registered. `SMAppService.mainApp` always refers to the *calling* process's own bundle,
/// so this cannot be queried by a helper script — it has to run inside the app.
@MainActor
enum StatusDump {

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        Task { @MainActor in
            report()
            exit(0)
        }

        app.run()
        exit(1)
    }

    private static func report() {
        print("bundle          \(Bundle.main.bundlePath)")
        print("permanent home  \(LaunchAtLogin.isInAPermanentLocation ? "yes" : "no — a login item here would break")")
        print("screen recording \(PermissionGate.hasScreenRecordingAccess ? "granted" : "NOT granted")")
        print("launch at login  \(describe(LaunchAtLogin.status))")
        print("configured once  \(Settings.shared.launchAtLoginConfigured ? "yes" : "no")")
        print("capture shortcut \(Settings.shared.captureHotKey.displayString)")
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "enabled"
        case .requiresApproval: "requires approval in System Settings › Login Items"
        case .notRegistered: "not registered"
        case .notFound: "not found"
        @unknown default: "unknown (\(status.rawValue))"
        }
    }
}
