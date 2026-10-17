import Foundation

/// A key combination such as `cmd+shift+m`: modifiers plus one key.
public struct KeyCombo: Equatable, Sendable {
    public enum Modifier: String, CaseIterable, Sendable {
        case cmd, shift, alt, ctrl, fn
    }

    public var modifiers: Set<Modifier>
    /// macOS virtual key code (ANSI layout).
    public var keyCode: UInt16

    public init(modifiers: Set<Modifier>, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    public enum ParseError: Error, Equatable {
        case empty
        case unknownKey(String)
        case missingKey
        case multipleKeys(String, String)
    }

    /// Parses `mod+mod+key`. Names are case-insensitive.
    public static func parse(_ text: String) -> Result<KeyCombo, ParseError> {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .failure(.empty) }
        var modifiers = Set<Modifier>()
        var key: (name: String, code: UInt16)?
        for part in parts.map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let modifier = Modifier(rawValue: part) ?? modifierAliases[part] {
                modifiers.insert(modifier)
            } else if let code = keyCodes[part] {
                if let key { return .failure(.multipleKeys(key.name, part)) }
                key = (part, code)
            } else {
                return .failure(.unknownKey(part))
            }
        }
        guard let key else { return .failure(.missingKey) }
        return .success(KeyCombo(modifiers: modifiers, keyCode: key.code))
    }

    static let modifierAliases: [String: Modifier] = [
        "command": .cmd, "option": .alt, "opt": .alt, "control": .ctrl,
    ]

    /// Virtual key codes from HIToolbox `Events.h` (kVK_*).
    static let keyCodes: [String: UInt16] = {
        var codes: [String: UInt16] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
            "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
            "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
            "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
            "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
            "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "backspace": 0x33,
            "esc": 0x35, "escape": 0x35, "forwarddelete": 0x75, "home": 0x73, "end": 0x77,
            "pageup": 0x74, "pagedown": 0x79, "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        ]
        let functionKeys: [UInt16] = [
            0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
            0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
        ]
        for (index, code) in functionKeys.enumerated() { codes["f\(index + 1)"] = code }
        return codes
    }()
}
