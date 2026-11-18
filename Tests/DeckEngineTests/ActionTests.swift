import DeckConfig
import Foundation
import Testing
@testable import DeckEngine

// MARK: 5.3 Keystrokes

@Test func usLayoutMatchesFormerKeyCodes() {
    for (character, code) in KeyCombo.usCharacterCodes {
        #expect(TableKeyboardLayout.us.keyCode(typing: character) == code)
        #expect(TableKeyboardLayout.us.character(forKeyCode: code) == character)
    }
}

@Test func germanFakeLayout() {
    #expect(germanLayout.keyCode(typing: "z") == 0x10)
    #expect(germanLayout.keyCode(typing: "y") == 0x06)
    #expect(germanLayout.keyCode(typing: "[") == nil)
    #expect(germanLayout.character(forKeyCode: 0x29) == "ö")
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


@Test func runResultSucceeded() {
    #expect(ActionResult(CommandResult(exitCode: 0, stderr: "warning"), command: "true") == .succeeded)
}

@Test func runResultReportsExitStatus() {
    #expect(ActionResult(CommandResult(exitCode: 3), command: "exit 3") == .failed("'exit 3' exited with status 3"))
}

@Test func runResultKeepsLastThreeStderrLines() {
    let result = CommandResult(exitCode: 1, stderr: "one\ntwo\nthree\nfour\n")
    #expect(ActionResult(result, command: "x") == .failed("'x' exited with status 1: two / three / four"))
}

@Test func failingCommandReportsStatusAndStderr() async {
    let result = await ShellRunner().run("echo oops >&2; exit 3", timeout: nil)
    #expect(ActionResult(result, command: "echo oops >&2; exit 3") == .failed("'echo oops >&2; exit 3' exited with status 3: oops"))
}
