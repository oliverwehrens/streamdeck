import CoreGraphics
import DeckConfig
import DeckEngine
import Foundation
import Testing
@testable import DeckPlatformMac

// MARK: Keystrokes

@Test func modifierFlags() {
    let flags = SystemActionPerformer.flags(for: [.cmd, .shift, .alt, .ctrl, .fn])
    #expect(flags.contains([.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]))
    #expect(SystemActionPerformer.flags(for: []).isEmpty)
}

@Test func keystrokeWithoutPermissionIsNotSent() async throws {
    let performer = SystemActionPerformer(commands: noCommands, isTrusted: { false })
    let combo = try KeyCombo.parse("cmd+space").get()
    #expect(await performer.perform(.keys(combo)) == .needsAccessibility)
}

@Test func charactersResolveThroughTheLayout() throws {
    let undo = try KeyCombo.parse("cmd+z").get()
    #expect(SystemActionPerformer.resolve(undo, layout: germanLayout) == .success(.init(keyCode: 0x10, flags: .maskCommand)))
    #expect(SystemActionPerformer.resolve(undo, layout: TableKeyboardLayout.us) == .success(.init(keyCode: 0x06, flags: .maskCommand)))
}

@Test func namedKeysIgnoreTheLayout() throws {
    let left = try KeyCombo.parse("cmd+left").get()
    for layout in [germanLayout, TableKeyboardLayout.us] {
        #expect(SystemActionPerformer.resolve(left, layout: layout) == .success(.init(keyCode: 0x7B, flags: .maskCommand)))
    }
}

@Test func characterMissingFromLayoutIsNotSent() async throws {
    let performer = SystemActionPerformer(commands: noCommands, isTrusted: { true }, layout: germanLayout)
    let combo = try KeyCombo.parse("cmd+[").get()
    #expect(await performer.perform(.keys(combo)) == .failed("keys 'cmd+[': keyboard layout 'German' has no key for '['"))
}

@Test func systemLayoutTypesLetters() async {
    let layout = await MainActor.run { SystemKeyboardLayout.current() }
    #expect(layout.keyCode(typing: "a") != nil)
    #expect(layout.keyCode(typing: "z") != nil)
}

// MARK: Media keys

@Test func mediaWithoutPermissionIsNotSent() async {
    let performer = SystemActionPerformer(commands: noCommands, isTrusted: { false })
    #expect(await performer.perform(.media(.playpause)) == .needsAccessibility)
}

@Test func mediaKeyTypes() {
    #expect(SystemActionPerformer.keyType(for: .playpause) == 16)
    #expect(SystemActionPerformer.keyType(for: .volumeup) == 0)
    #expect(Set(MediaKey.allCases.map(SystemActionPerformer.keyType)).count == MediaKey.allCases.count)
}

// MARK: Run and open

@Test func failingCommandReportsStatusAndStderr() async {
    let performer = SystemActionPerformer(commands: ShellRunner(), isTrusted: { true })
    let result = await performer.perform(.run("echo oops >&2; exit 3"))
    #expect(result == .failed("'echo oops >&2; exit 3' exited with status 3: oops"))
}

@Test func openMissingFileFails() async {
    let performer = SystemActionPerformer(commands: noCommands, isTrusted: { true })
    #expect(await performer.perform(.open("/no/such/file.txt")) == .failed("cannot open '/no/such/file.txt': no such file"))
}
