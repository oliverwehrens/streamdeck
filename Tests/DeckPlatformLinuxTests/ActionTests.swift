import CLinux
import DeckConfig
import DeckEngine
import DeckSupport
import Foundation
import Testing
@testable import DeckPlatformLinux

private final class FakeLauncher: ProgramLauncher, @unchecked Sendable {
    let launched = Locked<[[String]]>(initialState: [])
    let result: LaunchResult
    init(result: LaunchResult = .exited(status: 0, stderr: "")) { self.result = result }
    func launch(_ program: String, arguments: [String], patience: TimeInterval) async -> LaunchResult {
        launched.withLock { $0.append([program] + arguments) }
        return result
    }
    var all: [[String]] { launched.withLock { $0 } }
}

private let german = TableKeyboardLayout(name: "de", codes: ["z": UInt16(KEY_Y), "y": UInt16(KEY_Z), "a": UInt16(KEY_A)])

private func performer(launcher: FakeLauncher = FakeLauncher(), sink: RecordingSink? = RecordingSink(),
                       layout: any KeyboardLayout = german) -> LinuxActionPerformer {
    let keyboard: Result<UinputKeyboard, UinputError> = sink.map { .success(UinputKeyboard(sink: $0)) }
        ?? .failure(UinputError(path: "/dev/uinput", errno: EACCES))
    return LinuxActionPerformer(commands: ShellRunner(shell: "/bin/sh"), keyboard: keyboard, layout: layout, launcher: launcher)
}

// MARK: - open

@Test func steamURLGoesToSteam() async {
    let launcher = FakeLauncher()
    #expect(await performer(launcher: launcher).perform(.open("steam://rungameid/570")) == .succeeded)
    #expect(launcher.all == [["steam", "steam://rungameid/570"]])
}

@Test func otherURLGoesToXdgOpen() async {
    let launcher = FakeLauncher()
    #expect(await performer(launcher: launcher).perform(.open("https://example.com")) == .succeeded)
    #expect(launcher.all == [["xdg-open", "https://example.com"]])
}

@Test func existingPathIsExpanded() {
    let home = NSHomeDirectory()
    #expect(LinuxActionPerformer.route("~/notes.txt") { $0 == home + "/notes.txt" } == .program("xdg-open", [home + "/notes.txt"]))
    #expect(LinuxActionPerformer.route("/tmp") { _ in true } == .program("xdg-open", ["/tmp"]))
}

@Test func missingFileFailsLikeMacOS() async {
    let launcher = FakeLauncher()
    let result = await performer(launcher: launcher).perform(.open("~/nothing-here-\(UUID().uuidString).txt"))
    guard case let .failed(message) = result else { Issue.record("expected failure"); return }
    #expect(message.hasPrefix("cannot open '~/nothing-here-"))
    #expect(message.hasSuffix("': no such file"))
    #expect(launcher.all.isEmpty)
}

@Test func failedOpenIncludesStderr() async {
    let launcher = FakeLauncher(result: .exited(status: 4, stderr: "gio: no handler\n"))
    #expect(await performer(launcher: launcher).perform(.open("foo://bar"))
        == .failed("cannot open 'foo://bar': xdg-open exited with status 4: gio: no handler"))
    let missing = FakeLauncher(result: .exited(status: 127, stderr: ""))
    #expect(await performer(launcher: missing).perform(.open("steam://store"))
        == .failed("cannot open 'steam://store': steam is not installed"))
}

@Test func programStillRunningCountsAsStarted() async {
    #expect(await performer(launcher: FakeLauncher(result: .stillRunning)).perform(.open("steam://store")) == .succeeded)
}

@Test func processLauncherOutcomes() async {
    let launcher = ProcessLauncher()
    #expect(await launcher.launch("true", arguments: [], patience: 5) == .exited(status: 0, stderr: ""))
    #expect(await launcher.launch("sh", arguments: ["-c", "echo oops >&2; exit 3"], patience: 5) == .exited(status: 3, stderr: "oops\n"))
    #expect(await launcher.launch("sleep", arguments: ["30"], patience: 0.2) == .stillRunning)
    if case let .exited(status, _) = await launcher.launch("no-such-program-\(UUID().uuidString)", arguments: [], patience: 5) {
        #expect(status == 127)
    } else {
        Issue.record("expected env to exit 127")
    }
}

// MARK: - run

@Test func runFailureIncludesStderr() async {
    let result = await performer().perform(.run("echo bad >&2; exit 2"))
    #expect(result == .failed("'echo bad >&2; exit 2' exited with status 2: bad"))
}

// MARK: - keys and media

private func combo(_ text: String) throws -> KeyCombo { try KeyCombo.parse(text).get() }
private func key(_ code: Int32, _ value: Int32) -> InputEvent { InputEvent(type: UInt16(EV_KEY), code: UInt16(code), value: value) }

@Test func keysGoThroughTheLayout() async throws {
    let sink = RecordingSink()
    #expect(await performer(sink: sink).perform(.keys(try combo("cmd+shift+z"))) == .succeeded)
    #expect(sink.all == [
        key(KEY_LEFTSHIFT, 1), key(KEY_LEFTMETA, 1), key(KEY_Y, 1), UinputKeyboard.syn,
        key(KEY_Y, 0), key(KEY_LEFTMETA, 0), key(KEY_LEFTSHIFT, 0), UinputKeyboard.syn,
    ])
}

@Test func namedKeysIgnoreTheLayout() async throws {
    let sink = RecordingSink()
    #expect(await performer(sink: sink).perform(.keys(try combo("ctrl+f12"))) == .succeeded)
    #expect(sink.all.first == key(KEY_LEFTCTRL, 1))
    #expect(sink.all[1] == key(KEY_F12, 1))
}

@Test func fnIsNotSent() async throws {
    let sink = RecordingSink()
    #expect(await performer(sink: sink).perform(.keys(try combo("fn+f"))) == .failed("keys 'fn+f': fn has no Linux equivalent"))
    #expect(sink.all.isEmpty)
}

@Test func characterMissingFromLayout() async throws {
    let sink = RecordingSink()
    #expect(await performer(sink: sink).perform(.keys(try combo("ctrl+["))) == .failed("keys 'ctrl+[': keyboard layout 'de' has no key for '['"))
    #expect(sink.all.isEmpty)
}

@Test func mediaKey() async {
    let sink = RecordingSink()
    #expect(await performer(sink: sink).perform(.media(.volumeup)) == .succeeded)
    #expect(sink.all.first == key(KEY_VOLUMEUP, 1))
}

@Test func withoutUinputKeysFailWithTheUdevMessage() async throws {
    let unavailable = performer(sink: nil)
    for action in [Action.keys(try combo("ctrl+a")), .media(.mute)] {
        guard case let .failed(message) = await unavailable.perform(action) else { Issue.record("expected failure"); continue }
        #expect(message.contains("udev rules"))
    }
    #expect(await unavailable.perform(.open("steam://store")) != .needsAccessibility)
}
