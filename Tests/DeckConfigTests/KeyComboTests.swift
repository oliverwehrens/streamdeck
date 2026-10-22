import Testing
@testable import DeckConfig

@Test func parsesModifiersAndKey() throws {
    let combo = try KeyCombo.parse("cmd+shift+m").get()
    #expect(combo.modifiers == [.cmd, .shift])
    #expect(combo.key == .character("m"))
}

@Test(arguments: [("cmd+space", 0x31), ("f12", 0x6F), ("ctrl+alt+left", 0x7B), ("Command+Option+Esc", 0x35), ("f1", 0x7A), ("f20", 0x5A)])
func parsesNamedKeys(text: String, code: Int) throws {
    #expect(try KeyCombo.parse(text).get().key == .named(UInt16(code)))
}

@Test func parsesCharactersCaseInsensitively() throws {
    #expect(try KeyCombo.parse("CMD+Z").get().key == .character("z"))
    #expect(try KeyCombo.parse("cmd+[").get().key == .character("["))
    #expect(try KeyCombo.parse("alt+1").get().key == .character("1"))
}

@Test func rejectsUnknownKey() {
    #expect(KeyCombo.parse("cmd+banana") == .failure(.unknownKey("banana")))
    #expect(KeyCombo.parse("cmd+ö") == .failure(.unknownKey("ö")))
}

@Test func rejectsModifiersOnly() {
    #expect(KeyCombo.parse("cmd+shift") == .failure(.missingKey))
}

@Test func rejectsTwoKeys() {
    #expect(KeyCombo.parse("a+b") == .failure(.multipleKeys("a", "b")))
}

@Test func rejectsEmpty() {
    #expect(KeyCombo.parse("") == .failure(.empty))
}

@Test(arguments: [("cmd+shift+m", "cmd+shift+m"), ("ctrl+alt+left", "ctrl+alt+left"), ("f12", "f12"),
                  ("Command+Option+Esc", "cmd+alt+esc"), ("shift+alt+ctrl+cmd+fn+a", "cmd+ctrl+alt+shift+fn+a"),
                  ("enter", "return"), ("backspace", "delete"), ("escape", "esc")])
func writesCanonicalText(input: String, text: String) throws {
    #expect(try KeyCombo.parse(input).get().text == text)
}

@Test func textRoundTripsForEveryKeyAndModifierSet() throws {
    let keys = KeyCombo.usCharacterCodes.keys.map(KeyCombo.Key.character) + KeyCombo.canonicalNames.keys.map(KeyCombo.Key.named)
    let modifiers = KeyCombo.Modifier.allCases
    for key in keys {
        for mask in 0..<(1 << modifiers.count) {
            let set = Set(modifiers.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            let combo = KeyCombo(modifiers: set, key: key)
            #expect(try KeyCombo.parse(combo.text).get() == combo, "\(combo.text)")
        }
    }
}

@Test func namedKeyLookup() {
    #expect(KeyCombo.namedKey(forKeyCode: 0x7B) == .named(0x7B))
    #expect(KeyCombo.namedKey(forKeyCode: 0x06) == nil)
    #expect(KeyCombo.namedKey(forKeyCode: 0x57) == nil)
}
