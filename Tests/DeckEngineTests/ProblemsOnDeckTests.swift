import DeckConfig
import DeckHID
import Foundation
import Testing
@testable import DeckEngine

private let info = DeviceInfo(serial: "S", firmware: "F")

private func config(label14: String = "Fourteen") -> DeckConfig {
    DeckConfig(defaultPage: "home", pages: [
        "home": Page(keys: [
            0: KeyDefinition(label: "Zero"),
            3: KeyDefinition(label: "Run", action: .run("false")),
            4: KeyDefinition(icon: .file("/nonexistent/icon.png"), label: "Missing"),
            14: KeyDefinition(label: label14, action: .run("echo fourteen")),
        ]),
    ])
}

@MainActor
private func engine(onDeck: Bool = true, performer: FakePerformer = FakePerformer(), load: DeckConfig? = config())
    -> (DeckEngine, FakeTransport) {
    let transport = FakeTransport()
    let engine = DeckEngine(transport: transport, renderer: FakeRenderer(), performer: performer, commands: noCommands,
                            configDirectory: testConfigDirectory, ownBundleID: "own", frontmostApp: nil,
                            showsProblemsOnDeck: onDeck)
    engine.start()
    if let load { engine.configLoaded(load) }
    engine.handle(.connected(info))
    return (engine, transport)
}

/// What the device shows on `key`, as the fake renderer's description of the appearance.
private func shown(_ transport: FakeTransport, _ key: Int) -> String {
    transport.images.last { $0.key == key }.map { String(decoding: $0.jpeg, as: UTF8.self) } ?? ""
}

private func blank() -> String { String(decoding: FakeRenderer().render(.blank).jpeg, as: UTF8.self) }
private func statusKey(_ label: String) -> String {
    String(decoding: FakeRenderer().render(DeckEngine.statusKeyAppearance(label: label)).jpeg, as: UTF8.self)
}

// MARK: - Error dot

@MainActor @Test func failedActionShowsErrorDotUntilSuccess() async {
    let performer = FakePerformer(result: .failed("exit status 1"))
    let (engine, transport) = engine(performer: performer)
    #expect(!shown(transport, 3).contains("error: true"))
    engine.handle(.key(KeyEvent(key: 3, edge: .down)))
    engine.handle(.key(KeyEvent(key: 3, edge: .up)))
    await eventually { shown(transport, 3).contains("error: true") }
    #expect(shown(transport, 3).contains("error: true"))

    performer.result = .succeeded
    engine.handle(.key(KeyEvent(key: 3, edge: .down)))
    engine.handle(.key(KeyEvent(key: 3, edge: .up)))
    await eventually { !shown(transport, 3).contains("error: true") }
    #expect(!shown(transport, 3).contains("error: true"))
}

@MainActor @Test func configReloadClearsErrorDot() async {
    let (engine, transport) = engine(performer: FakePerformer(result: .failed("exit status 1")))
    engine.handle(.key(KeyEvent(key: 3, edge: .down)))
    engine.handle(.key(KeyEvent(key: 3, edge: .up)))
    await eventually { shown(transport, 3).contains("error: true") }
    engine.configLoaded(config())
    #expect(!shown(transport, 3).contains("error: true"))
}

@MainActor @Test func missingIconShowsErrorDot() async {
    let (engine, transport) = engine()
    #expect(shown(transport, 4).contains("error: true"))
    #expect(engine.status.problems.contains { $0.source == .icon(key: 4) })
}

@MainActor @Test func withoutFlagNoErrorDots() async {
    let (engine, transport) = engine(onDeck: false, performer: FakePerformer(result: .failed("exit status 1")))
    engine.handle(.key(KeyEvent(key: 3, edge: .down)))
    engine.handle(.key(KeyEvent(key: 3, edge: .up)))
    await eventually { !engine.status.problems.filter { $0.source == .action(page: "home", key: 3) }.isEmpty }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(!shown(transport, 3).contains("error: true"))
    #expect(!shown(transport, 4).contains("error: true"))
}

// MARK: - Status key

@MainActor @Test func configFailureWithoutConfigShowsStatusKey() async {
    let (engine, transport) = engine(load: nil)
    engine.configFailed([ConfigError("bad", line: 1)])
    #expect(shown(transport, 14) == statusKey("Config"))
    for key in 0 ..< 14 { #expect(shown(transport, key) == blank()) }
}

@MainActor @Test func brokenEditKeepsLastConfigAndShowsStatusKey() async {
    let (engine, transport) = engine()
    engine.configFailed([ConfigError("bad", line: 1)])
    #expect(shown(transport, 14) == statusKey("Config"))
    #expect(shown(transport, 0).contains("Zero"))
}

@MainActor @Test func permissionProblemShowsKeys() async {
    let (engine, transport) = engine()
    engine.setPermissionProblem("no uinput")
    #expect(shown(transport, 14) == statusKey("Keys"))
}

@MainActor @Test func severalProblemsAreCounted() async {
    let (engine, transport) = engine()
    engine.configFailed([ConfigError("bad", line: 1)])
    engine.setPermissionProblem("no uinput")
    #expect(shown(transport, 14) == statusKey("2 problems"))
}

@MainActor @Test func deviceProblemDoesNotShowStatusKey() async {
    let (engine, transport) = engine()
    engine.handle(.openFailed("permission denied"))
    #expect(shown(transport, 14).contains("Fourteen"))
}

@MainActor @Test func pressingStatusKeyRunsNoAction() async {
    let performer = FakePerformer()
    let (engine, transport) = engine(performer: performer)
    var presses = 0
    engine.onStatusKeyPress = { presses += 1 }
    engine.configFailed([ConfigError("bad", line: 1)])
    transport.clear()
    engine.handle(.key(KeyEvent(key: 14, edge: .down)))
    engine.handle(.key(KeyEvent(key: 14, edge: .up)))
    try? await Task.sleep(for: .milliseconds(50))
    #expect(presses == 1)
    #expect(performer.performed.isEmpty)
    #expect(transport.images.isEmpty)
}

@MainActor @Test func fixingProblemRestoresKey14() async {
    let (engine, transport) = engine()
    engine.configFailed([ConfigError("bad", line: 1)])
    engine.configLoaded(config(label14: "Back again"))
    #expect(shown(transport, 14).contains("Back again"))
    engine.setPermissionProblem("no uinput")
    engine.setPermissionProblem(nil)
    #expect(shown(transport, 14).contains("Back again"))
}

@MainActor @Test func withoutFlagKey14IsNeverReplaced() async {
    let performer = FakePerformer()
    let (engine, transport) = engine(onDeck: false, performer: performer)
    engine.configFailed([ConfigError("bad", line: 1)])
    engine.setPermissionProblem("no uinput")
    #expect(shown(transport, 14).contains("Fourteen"))
    engine.handle(.key(KeyEvent(key: 14, edge: .down)))
    await eventually { !performer.performed.isEmpty }
    #expect(performer.performed == [.run("echo fourteen")])
}
