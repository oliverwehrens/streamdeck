import AppKit
import DeckConfig
import DeckEngine
import Testing
@testable import StreamDeckApp

/// German (QWERTZ) without modifiers: Y and Z swapped, Ö where US has `;`.
private let german: TableKeyboardLayout = {
    var codes = TableKeyboardLayout.us.codes
    for character in "[];'\\/=`-" { codes[character] = nil }
    codes["z"] = 0x10
    codes["y"] = 0x06
    codes["-"] = 0x2C
    codes["ö"] = 0x29
    return TableKeyboardLayout(name: "German", codes: codes)
}()

private func text(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [], layout: some KeyboardLayout = TableKeyboardLayout.us) -> String? {
    if case let .combo(combo) = KeyRecorder.recording(keyCode: keyCode, flags: flags, layout: layout) { combo.text } else { nil }
}

@Test func recordsACombination() {
    #expect(text(0x2E, [.command, .shift]) == "cmd+shift+m")
}

@Test func recordsANamedKey() {
    #expect(text(0x7B, [.control, .option, .function]) == "ctrl+alt+left")
}

@Test func recordsByTheLayout() {
    #expect(text(0x10, .command, layout: german) == "cmd+z")
    #expect(text(0x06, layout: german) == "y")
    #expect(text(0x2C, layout: german) == "-")
}

@Test func dropsImplicitFnOnFKeysArrowsAndNavigation() {
    #expect(text(0x6F, .function) == "f12")
    #expect(text(0x7E, [.command, .function]) == "cmd+up")
    #expect(text(0x75, .function) == "forwarddelete")
}

@Test func keepsHeldFn() {
    #expect(text(0x26, .function) == "fn+j")
}

@Test func ignoresCapsLock() {
    #expect(text(0x00, [.capsLock, .command]) == "cmd+a")
}

@Test func keypadKeyIsUnsupported() {
    #expect(KeyRecorder.recording(keyCode: 0x57, flags: [], layout: TableKeyboardLayout.us) == .unsupported(keyCode: 0x57))
}

@Test func letterWithoutConfigNameIsUnsupported() {
    #expect(KeyRecorder.recording(keyCode: 0x29, flags: [], layout: german) == .unsupported(keyCode: 0x29))
}

@Test func recordingRoundTripsThroughSending() throws {
    for layout in [german, TableKeyboardLayout.us] {
        for code in UInt16(0)..<128 {
            guard case let .combo(combo) = KeyRecorder.recording(keyCode: code, flags: .command, layout: layout) else { continue }
            let parsed = try KeyCombo.parse(combo.text).get()
            let sent: UInt16? = switch parsed.key {
            case let .named(named): named
            case let .character(character): layout.keyCode(typing: character)
            }
            #expect(sent == code, "\(layout.name) \(combo.text)")
        }
    }
}
