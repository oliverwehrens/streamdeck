import Foundation

/// A key combination such as `cmd+shift+m`: modifiers plus one key.
public struct KeyCombo: Equatable, Sendable {
    public enum Modifier: String, CaseIterable, Sendable {
        case cmd, shift, alt, ctrl, fn
    }

    /// A character resolves through the active keyboard layout when sent; a named key is the same on every layout.
    public enum Key: Hashable, Sendable {
        case character(Character)
        /// macOS virtual key code.
        case named(UInt16)
    }

    public var modifiers: Set<Modifier>
    public var key: Key

    public init(modifiers: Set<Modifier>, key: Key) {
        self.modifiers = modifiers
        self.key = key
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
        var key: (name: String, key: Key)?
        for part in parts.map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let modifier = Modifier(rawValue: part) ?? modifierAliases[part] {
                modifiers.insert(modifier)
            } else if let found = self.key(named: part) {
                if let key { return .failure(.multipleKeys(key.name, part)) }
                key = (part, found)
            } else {
                return .failure(.unknownKey(part))
            }
        }
        guard let key else { return .failure(.missingKey) }
        return .success(KeyCombo(modifiers: modifiers, key: key.key))
    }

    /// The canonical config text, which `parse` reads back to this combo.
    public var text: String {
        let order: [Modifier] = [.cmd, .ctrl, .alt, .shift, .fn]
        return (order.filter(modifiers.contains).map(\.rawValue) + [Self.name(of: key)]).joined(separator: "+")
    }

    /// The config name of a key: the character itself, or the canonical name of a named key.
    public static func name(of key: Key) -> String {
        switch key {
        case let .character(character): String(character)
        case let .named(code): canonicalNames[code] ?? String(format: "0x%02X", code)
        }
    }

    /// The named key for a virtual key code, if it has a config name.
    public static func namedKey(forKeyCode code: UInt16) -> Key? {
        canonicalNames[code] == nil ? nil : .named(code)
    }

    /// Whether the config format has a name for this character.
    public static func isCharacterName(_ character: Character) -> Bool {
        usCharacterCodes[character] != nil
    }

    static func key(named name: String) -> Key? {
        if name.count == 1, let character = name.first, usCharacterCodes[character] != nil { return .character(character) }
        return namedKeyCodes[name].map(Key.named)
    }

    static let modifierAliases: [String: Modifier] = [
        "command": .cmd, "option": .alt, "opt": .alt, "control": .ctrl,
    ]

    /// Characters with a config name and their US (ANSI) key codes from HIToolbox `Events.h` (kVK_ANSI_*).
    public static let usCharacterCodes: [Character: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
    ]

    /// Named keys in canonical spelling, from HIToolbox `Events.h` (kVK_*).
    static let canonicalNames: [UInt16: String] = {
        var names: [UInt16: String] = [
            0x24: "return", 0x30: "tab", 0x31: "space", 0x33: "delete", 0x35: "esc", 0x75: "forwarddelete",
            0x73: "home", 0x77: "end", 0x74: "pageup", 0x79: "pagedown",
            0x7B: "left", 0x7C: "right", 0x7D: "down", 0x7E: "up",
        ]
        for (index, code) in functionKeyCodes.enumerated() { names[code] = "f\(index + 1)" }
        return names
    }()

    static let namedKeyCodes: [String: UInt16] = {
        var codes = Dictionary(uniqueKeysWithValues: canonicalNames.map { ($1, $0) })
        for (alias, name) in ["enter": "return", "backspace": "delete", "escape": "esc"] { codes[alias] = codes[name] }
        return codes
    }()

    /// F1-F20.
    static let functionKeyCodes: [UInt16] = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
    ]
}
