import CoreGraphics
import DeckConfig
import Foundation
import Testing
@testable import DeckEngine

// MARK: 5.3 Keystrokes

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

// MARK: 5.4 Media keys

@Test func mediaWithoutPermissionIsNotSent() async {
    let performer = SystemActionPerformer(commands: noCommands, isTrusted: { false })
    #expect(await performer.perform(.media(.playpause)) == .needsAccessibility)
}

@Test func mediaKeyTypes() {
    #expect(SystemActionPerformer.keyType(for: .playpause) == 16)
    #expect(SystemActionPerformer.keyType(for: .volumeup) == 0)
    #expect(Set(MediaKey.allCases.map(SystemActionPerformer.keyType)).count == MediaKey.allCases.count)
}

// MARK: 5.5 Run and open

@Test func shellCommandSucceeds() async {
    let result = await ShellRunner().run("echo hello", timeout: nil)
    #expect(result.succeeded)
    #expect(result.stdout == "hello\n")
}

@Test func shellUsesLoginShellPath() async {
    let result = await ShellRunner().run("echo $PATH", timeout: nil)
    #expect(result.stdout.contains("/usr/bin"))
}

@Test func failingCommandReportsStatusAndStderr() async {
    let performer = SystemActionPerformer(commands: ShellRunner(), isTrusted: { true })
    let result = await performer.perform(.run("echo oops >&2; exit 3"))
    #expect(result == .failed("'echo oops >&2; exit 3' exited with status 3: oops"))
}

@Test func runDoesNotBlockCaller() async {
    let start = ContinuousClock.now
    async let slow = ShellRunner().run("sleep 1", timeout: nil)
    let elapsedBeforeAwait = ContinuousClock.now - start
    #expect(elapsedBeforeAwait < .milliseconds(200))
    _ = await slow
}

@Test func largeOutputDoesNotDeadlock() async {
    let result = await ShellRunner().run("head -c 300000 /dev/zero | tr '\\0' x", timeout: 10)
    #expect(result.stdout.count == 300_000)
}

@Test func timeoutTerminates() async {
    let start = ContinuousClock.now
    let result = await ShellRunner().run("sleep 30", timeout: 0.5)
    #expect(result.timedOut)
    #expect(!result.succeeded)
    #expect(ContinuousClock.now - start < .seconds(5))
}

@Test func openMissingFileFails() async {
    let performer = SystemActionPerformer(commands: noCommands, isTrusted: { true })
    #expect(await performer.perform(.open("/no/such/file.txt")) == .failed("cannot open '/no/such/file.txt': no such file"))
}
