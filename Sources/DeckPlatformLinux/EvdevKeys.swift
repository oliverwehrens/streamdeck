import CLinux
import DeckConfig

/// Linux input (evdev) key codes for what the config can name. Characters go through `XKBLayout` instead.
public enum EvdevKeys {
    /// The evdev code for a named key, by its config name (`KeyCombo.name(of:)`).
    public static let named: [String: UInt16] = {
        var codes: [String: Int32] = [
            "return": KEY_ENTER, "tab": KEY_TAB, "space": KEY_SPACE, "delete": KEY_BACKSPACE, "esc": KEY_ESC,
            "forwarddelete": KEY_DELETE, "home": KEY_HOME, "end": KEY_END, "pageup": KEY_PAGEUP, "pagedown": KEY_PAGEDOWN,
            "left": KEY_LEFT, "right": KEY_RIGHT, "down": KEY_DOWN, "up": KEY_UP,
        ]
        let function: [Int32] = [
            KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10,
            KEY_F11, KEY_F12, KEY_F13, KEY_F14, KEY_F15, KEY_F16, KEY_F17, KEY_F18, KEY_F19, KEY_F20,
        ]
        for (index, code) in function.enumerated() { codes["f\(index + 1)"] = code }
        return codes.mapValues { UInt16($0) }
    }()

    /// The evdev code for a named key (`KeyCombo.Key.named`, which holds a macOS code).
    public static func code(for key: KeyCombo.Key) -> UInt16? {
        guard case .named = key else { return nil }
        return named[KeyCombo.name(of: key)]
    }

    public static func code(for modifier: KeyCombo.Modifier) -> UInt16? {
        switch modifier {
        case .cmd: UInt16(KEY_LEFTMETA)
        case .ctrl: UInt16(KEY_LEFTCTRL)
        case .alt: UInt16(KEY_LEFTALT)
        case .shift: UInt16(KEY_LEFTSHIFT)
        case .fn: nil
        }
    }

    public static func code(for media: MediaKey) -> UInt16 {
        let code: Int32 = switch media {
        case .playpause: KEY_PLAYPAUSE
        case .next: KEY_NEXTSONG
        case .previous: KEY_PREVIOUSSONG
        case .volumeup: KEY_VOLUMEUP
        case .volumedown: KEY_VOLUMEDOWN
        case .mute: KEY_MUTE
        case .brightnessup: KEY_BRIGHTNESSUP
        case .brightnessdown: KEY_BRIGHTNESSDOWN
        }
        return UInt16(code)
    }

    /// Modifiers in the order they are pressed.
    public static let modifierOrder: [KeyCombo.Modifier] = [.ctrl, .alt, .shift, .cmd]

    /// Every code the virtual keyboard may send; it must announce them all when it is created.
    public static var all: [UInt16] {
        var codes = Set(named.values)
        codes.formUnion(XKBKeycodes.evdev.values)
        codes.formUnion(modifierOrder.compactMap { code(for: $0) })
        codes.formUnion(MediaKey.allCases.map { code(for: $0) })
        return codes.sorted()
    }
}
