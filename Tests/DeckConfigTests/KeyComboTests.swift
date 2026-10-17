import Testing
@testable import DeckConfig

@Test func parsesModifiersAndKey() throws {
    let combo = try KeyCombo.parse("cmd+shift+m").get()
    #expect(combo.modifiers == [.cmd, .shift])
    #expect(combo.keyCode == 0x2E)
}

@Test(arguments: [("cmd+space", 0x31), ("f12", 0x6F), ("ctrl+alt+left", 0x7B), ("Command+Option+Esc", 0x35), ("f1", 0x7A), ("f20", 0x5A)])
func parsesNamedKeys(text: String, code: Int) throws {
    #expect(try KeyCombo.parse(text).get().keyCode == UInt16(code))
}

@Test func rejectsUnknownKey() {
    #expect(KeyCombo.parse("cmd+banana") == .failure(.unknownKey("banana")))
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
