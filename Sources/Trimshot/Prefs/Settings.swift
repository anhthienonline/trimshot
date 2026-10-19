import AppKit

enum ImageFormat: String, CaseIterable {
    case png
    case jpeg

    var fileExtension: String { rawValue == "jpeg" ? "jpg" : "png" }

    var bitmapType: NSBitmapImageRep.FileType { self == .png ? .png : .jpeg }

    var properties: [NSBitmapImageRep.PropertyKey: Any] {
        self == .jpeg ? [.compressionFactor: 0.9] : [:]
    }
}

/// How many pixels an exported capture actually contains.
///
/// A 420 × 240 selection on a Retina display is 840 × 480 real pixels. `.two` keeps them,
/// which is what makes a capture worth checking colours and edges in. `.one` resamples down
/// so the file measures what the overlay reported — smaller, and the number matches.
///
/// This governs the *pixels*, not how the pasteboard labels them: at `.one` there is no
/// longer a 2× file to label, so the two agree by construction.
enum ExportScale: String, CaseIterable {
    case one = "1x"
    case two = "2x"

    var label: String { self == .one ? "1× — match the reading" : "2× — every pixel" }

    /// The divisor applied to a capture rendered at `renderScale`.
    func divisor(forRenderScale renderScale: CGFloat) -> CGFloat {
        self == .two ? 1 : max(renderScale, 1)
    }
}

/// UserDefaults-backed preferences. Deliberately tiny — everything here has a sane
/// default so the app works before the user ever opens Preferences.
@MainActor
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let saveDirectory = "saveDirectoryPath"
        static let imageFormat = "imageFormat"
        static let exportScale = "exportScale"
        static let copyAfterCapture = "copyAfterCapture"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let launchAtLoginConfigured = "launchAtLoginConfigured"
    }

    private init() {
        defaults.register(defaults: [
            Key.imageFormat: ImageFormat.png.rawValue,
            // 2× by default: this is a tool for checking pixels, so throwing half of them
            // away has to be something the user asks for.
            Key.exportScale: ExportScale.two.rawValue,
            Key.copyAfterCapture: true,
        ])
    }

    var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: Key.saveDirectory) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default
                .urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        set { defaults.set(newValue.path, forKey: Key.saveDirectory) }
    }

    var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: defaults.string(forKey: Key.imageFormat) ?? "") ?? .png }
        set { defaults.set(newValue.rawValue, forKey: Key.imageFormat) }
    }

    var exportScale: ExportScale {
        get { ExportScale(rawValue: defaults.string(forKey: Key.exportScale) ?? "") ?? .two }
        set { defaults.set(newValue.rawValue, forKey: Key.exportScale) }
    }

    /// Whether finishing a capture also puts the image on the pasteboard.
    var copyAfterCapture: Bool {
        get { defaults.bool(forKey: Key.copyAfterCapture) }
        set { defaults.set(newValue, forKey: Key.copyAfterCapture) }
    }

    /// Whether launch-at-login has been decided once already.
    ///
    /// Exists so the app can turn it on by itself the first time it runs from a permanent
    /// location, without overriding the user afterwards if they switch it back off.
    var launchAtLoginConfigured: Bool {
        get { defaults.bool(forKey: Key.launchAtLoginConfigured) }
        set { defaults.set(newValue, forKey: Key.launchAtLoginConfigured) }
    }

    var captureHotKey: HotKey {
        get {
            guard defaults.object(forKey: Key.hotKeyCode) != nil else {
                return .defaultCapture
            }
            return HotKey(
                keyCode: UInt32(defaults.integer(forKey: Key.hotKeyCode)),
                modifiers: UInt32(defaults.integer(forKey: Key.hotKeyModifiers))
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotKeyCode)
            defaults.set(Int(newValue.modifiers), forKey: Key.hotKeyModifiers)
        }
    }
}
