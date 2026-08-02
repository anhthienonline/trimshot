import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey, described the way Carbon wants it.
struct HotKey: Equatable, Codable {
    /// Virtual key code, e.g. `kVK_ANSI_2`.
    var keyCode: UInt32
    /// Carbon modifier mask: `cmdKey`, `shiftKey`, `optionKey`, `controlKey`.
    var modifiers: UInt32

    /// ⌃G — clear of macOS's own ⌘⇧3/4/5 screenshot shortcuts, and AppKit's text system
    /// leaves ⌃G unbound (unlike ⌃A/⌃E/⌃K/⌃Y, which it uses for Emacs-style editing).
    static let defaultCapture = HotKey(
        keyCode: UInt32(kVK_ANSI_G),
        modifiers: UInt32(controlKey)
    )

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (Self.keyNames[keyCode] ?? "?")
    }

    /// Carbon modifier mask built from an `NSEvent`'s flags, for the recorder.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    /// A shortcut needs at least one of ⌘ ⌃ ⌥ — ⇧ alone would swallow ordinary typing.
    var hasRequiredModifier: Bool {
        modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }

    private static let keyNames: [UInt32: String] = {
        var names: [UInt32: String] = [
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "esc",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Home): "↖",
            UInt32(kVK_End): "↘",
            UInt32(kVK_PageUp): "⇞",
            UInt32(kVK_PageDown): "⇟",
            UInt32(kVK_ANSI_Grave): "`",
            UInt32(kVK_ANSI_Minus): "-",
            UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[",
            UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",",
            UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/",
        ]

        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
        ]
        let digits: [(Int, String)] = [
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
        ]
        let functions: [(Int, String)] = [
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"),
            (kVK_F5, "F5"), (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"),
            (kVK_F9, "F9"), (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
        ]

        for (code, name) in letters + digits + functions {
            names[UInt32(code)] = name
        }
        return names
    }()
}

/// Registers a global hotkey through Carbon's `RegisterEventHotKey`.
///
/// Chosen over `NSEvent.addGlobalMonitorForEvents` and `CGEventTap` because those
/// require the Accessibility permission — a second scary system prompt on top of the
/// Screen Recording one we already can't avoid. `RegisterEventHotKey` needs none.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    /// Carbon identifies hotkeys by a four-char signature + id: 'SCCP' / 1.
    private static let signature: OSType = 0x5343_4350
    private static let hotKeyID: UInt32 = 1

    private init() {}

    /// Replaces any previously registered hotkey. Returns false if the combination is
    /// already taken by another app.
    @discardableResult
    func register(_ hotKey: HotKey, action: @escaping () -> Void) -> Bool {
        unregister()
        self.action = action
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        action = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    /// Called from the Carbon handler, which always runs on the main run loop.
    fileprivate func fire() {
        action?()
    }
}

/// Carbon needs a plain C function pointer, so this can't be a method or a closure
/// that captures. The manager instance arrives via `userData`.
private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr, id.signature == 0x5343_4350 else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { manager.fire() }
    return noErr
}
