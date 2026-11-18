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
