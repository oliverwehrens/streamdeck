@testable import DeckEngine
import DeckHID
import Testing
@testable import DeckPlatformLinux

private func status(connected: Bool = false, problems: [(Problem.Source, String)] = []) -> DeckEngine.Status {
    var status = DeckEngine.Status()
    status.connected = connected
    status.device = connected ? DeviceInfo(serial: "AL22", firmware: "1.02.007") : nil
    status.problems = problems.map { Problem(source: $0.0, message: $0.1) }
    return status
}

@Test func addedProblemGivesOneLine() {
    let lines = StatusLog.lines(from: status(), to: status(problems: [(.config, "Config not applied:\n• line 3: bad")]))
    #expect(lines == ["problem: Config not applied: • line 3: bad"])
}

@Test func removedProblemGivesResolved() {
    let lines = StatusLog.lines(from: status(problems: [(.permission, "no uinput")]), to: status())
    #expect(lines == ["resolved: no uinput"])
}

@Test func unchangedStatusGivesNothing() {
    let same = status(connected: true, problems: [(.config, "x")])
    #expect(StatusLog.lines(from: same, to: same).isEmpty)
}

@Test func connectionChanges() {
    #expect(StatusLog.lines(from: status(), to: status(connected: true)) == ["connected: Stream Deck AL22 (firmware 1.02.007)"])
    #expect(StatusLog.lines(from: status(connected: true), to: status()) == ["disconnected"])
}

@Test func statusKeyPressListsEverything() {
    #expect(StatusLog.allProblems(status()) == ["no problems"])
    #expect(StatusLog.allProblems(status(problems: [(.config, "a"), (.permission, "b")])) == ["problem: a", "problem: b"])
}
