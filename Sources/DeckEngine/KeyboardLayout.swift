import Carbon
import DeckConfig

/// Maps characters to the virtual key codes that type them without modifiers.
public protocol KeyboardLayout: Sendable {
    var name: String { get }
    func keyCode(typing character: Character) -> UInt16?
    func character(forKeyCode code: UInt16) -> Character?
}

/// A fixed table. `.us` is the ANSI layout the config used to assume.
public struct TableKeyboardLayout: KeyboardLayout {
    public let name: String
    public let codes: [Character: UInt16]
    private let characters: [UInt16: Character]

    public init(name: String, codes: [Character: UInt16]) {
        self.name = name
        self.codes = codes
        characters = Dictionary(codes.map { ($1, $0) }, uniquingKeysWith: min)
    }

    public static let us = TableKeyboardLayout(name: "U.S.", codes: KeyCombo.usCharacterCodes)

    public func keyCode(typing character: Character) -> UInt16? { codes[character] }
    public func character(forKeyCode code: UInt16) -> Character? { characters[code] }
}

/// The Latin layout macOS currently uses for shortcuts, read on every call. Call it on the main thread.
public struct SystemKeyboardLayout: KeyboardLayout {
    public init() {}

    public var name: String { Self.current().name }
    public func keyCode(typing character: Character) -> UInt16? { Self.current().keyCode(typing: character) }
    public func character(forKeyCode code: UInt16) -> Character? { Self.current().character(forKeyCode: code) }

    /// Keypad keys type digits too; the main keys win.
    private static let keypadCodes: Set<UInt16> = [
        0x41, 0x43, 0x45, 0x47, 0x4B, 0x4C, 0x4E, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C,
    ]

    /// Translates key codes 0-127 without modifiers. Falls back to `.us` when the layout has no Unicode data.
    static func current() -> TableKeyboardLayout {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return .us }
        let data = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data
        let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "current"
        var codes: [Character: UInt16] = [:]
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in UInt16(0)..<128 where !keypadCodes.contains(code) && KeyCombo.namedKey(forKeyCode: code) == nil {
                var deadKeys: UInt32 = 0
                var length = 0
                var output = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, output.count, &length, &output)
                guard status == noErr, length > 0 else { continue }
                let text = String(utf16CodeUnits: output, count: length).lowercased()
                guard text.count == 1, let character = text.first, codes[character] == nil else { continue }
                codes[character] = code
            }
        }
        return codes.isEmpty ? .us : TableKeyboardLayout(name: name, codes: codes)
    }
}
