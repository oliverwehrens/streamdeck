import DeckConfig
import DeckHID
import DeckRender
import Foundation
import Testing
@testable import DeckEngine

private let info = DeviceInfo(serial: "S", firmware: "F")

private func twoPages() -> DeckConfig {
    // Pages differ only in keys 1 and 2; switching must write just those.
    DeckConfig(brightness: 55, defaultPage: "home", pages: [
        "home": Page(keys: [
            0: KeyDefinition(label: "Same"),
            1: KeyDefinition(label: "Go", action: .page(.named("other"))),
            3: KeyDefinition(label: "Run", action: .run("echo hi")),
        ]),
        "other": Page(keys: [
            0: KeyDefinition(label: "Same"),
            2: KeyDefinition(label: "Back", action: .page(.back)),
            3: KeyDefinition(label: "Run", action: .run("echo hi")),
        ]),
    ])
}

@MainActor
private func connectedEngine(_ config: DeckConfig = twoPages(), performer: FakePerformer = FakePerformer(),
                             commands: FakeCommands = noCommands) async -> (DeckEngine, FakeTransport) {
    let transport = FakeTransport()
    let engine = DeckEngine(transport: transport, performer: performer, commands: commands, ownBundleID: "own", frontmostApp: nil)
    engine.start()
    engine.configLoaded(config)
    engine.handle(.connected(info))
    return (engine, transport)
}

@MainActor @Test func connectWritesAllKeysAndBrightness() async {
    let (engine, transport) = await connectedEngine()
    #expect(Set(transport.imageKeys) == Set(0 ..< 15))
    #expect(transport.brightness.last == 55)
    #expect(engine.status.connected)
    #expect(engine.status.device == info)
    #expect(engine.status.page == "home")
}

@MainActor @Test func pageSwitchSendsOnlyChangedKeys() async {
    let (engine, transport) = await connectedEngine()
    transport.clear()
    engine.handle(.key(KeyEvent(key: 1, edge: .down)))
    #expect(engine.status.page == "other")
    // Key 1 (Go -> blank) and key 2 (blank -> Back) change; 0 and 3 are identical.
    #expect(Set(transport.imageKeys) == [1, 2])
}

@MainActor @Test func holdingKeyFiresOnce() async {
    let performer = FakePerformer()
    let (engine, _) = await connectedEngine(performer: performer)
    engine.handle(.key(KeyEvent(key: 3, edge: .down)))
    try? await Task.sleep(for: .milliseconds(300))
    engine.handle(.key(KeyEvent(key: 3, edge: .up)))
    await eventually { performer.performed.count >= 1 }
    try? await Task.sleep(for: .milliseconds(100))
    #expect(performer.performed == [.run("echo hi")])
}

@MainActor @Test func releaseDoesNotFire() async {
    let performer = FakePerformer()
    let (engine, _) = await connectedEngine(performer: performer)
    engine.handle(.key(KeyEvent(key: 3, edge: .up)))
    try? await Task.sleep(for: .milliseconds(100))
    #expect(performer.performed.isEmpty)
}

@MainActor @Test func pressFeedbackDarkensWhileHeld() async throws {
    let (engine, transport) = await connectedEngine()
    let normal = try #require(transport.images.last { $0.key == 3 }?.jpeg)
    transport.clear()
    engine.handle(.key(KeyEvent(key: 3, edge: .down)))
    let held = try #require(transport.images.last { $0.key == 3 }?.jpeg)
    #expect(held != normal)
    engine.handle(.key(KeyEvent(key: 3, edge: .up)))
    #expect(transport.images.last { $0.key == 3 }?.jpeg == normal)
}

@MainActor @Test func keyWithoutActionGetsNoFeedback() async {
    let (engine, transport) = await connectedEngine()
    transport.clear()
    engine.handle(.key(KeyEvent(key: 0, edge: .down)))
    engine.handle(.key(KeyEvent(key: 0, edge: .up)))
    #expect(transport.images.isEmpty)
}

@MainActor @Test func failedActionIsReported() async {
    let (engine, _) = await connectedEngine(performer: FakePerformer(result: .failed("exit status 1")))
    engine.handle(.key(KeyEvent(key: 3, edge: .down)))
    await eventually { !engine.status.problems.isEmpty }
    #expect(engine.status.problems.map(\.message) == ["Page 'home', key 3: exit status 1"])
}

@MainActor @Test func missingPermissionIsReported() async {
    let (engine, _) = await connectedEngine(performer: FakePerformer(result: .needsAccessibility))
    engine.handle(.key(KeyEvent(key: 3, edge: .down)))
    await eventually { !engine.status.problems.isEmpty }
    #expect(engine.status.problems.first?.source == .permission)
}

@MainActor @Test func disconnectAndReconnectRedraws() async {
    let (engine, transport) = await connectedEngine()
    engine.handle(.key(KeyEvent(key: 1, edge: .down)))
    engine.handle(.disconnected)
    #expect(!engine.status.connected)
    transport.clear()
    engine.handle(.connected(info))
    #expect(Set(transport.imageKeys) == Set(0 ..< 15))
    #expect(engine.status.page == "other")
    #expect(transport.brightness == [55])
}

@MainActor @Test func nothingIsWrittenWhileDisconnected() async {
    let transport = FakeTransport()
    let engine = DeckEngine(transport: transport, performer: FakePerformer(), commands: noCommands, ownBundleID: "own", frontmostApp: nil)
    engine.configLoaded(twoPages())
    #expect(transport.images.isEmpty)
    engine.handle(.connected(info))
    #expect(transport.images.count == 15)
}

@MainActor @Test func sessionBrightnessResetsOnReload() async {
    let (engine, transport) = await connectedEngine()
    engine.setSessionBrightness(20)
    #expect(transport.brightness.last == 20)
    engine.configLoaded(twoPages())
    #expect(transport.brightness.last == 55)
}

@MainActor @Test func configFailureIsReportedAndCleared() async {
    let (engine, _) = await connectedEngine()
    engine.configFailed([ConfigError("bad", line: 3)])
    #expect(engine.status.problems.first?.source == .config)
    #expect(engine.status.problems.first?.message.contains("line 3: bad") == true)
    engine.configLoaded(twoPages())
    #expect(engine.status.problems.isEmpty)
}

@MainActor @Test func missingIconIsReported() async {
    let config = DeckConfig(defaultPage: "home", pages: ["home": Page(keys: [4: KeyDefinition(icon: .file("/nope.png"))])])
    let (engine, _) = await connectedEngine(config)
    #expect(engine.status.problems.map(\.source) == [.icon(key: 4)])
}

@MainActor @Test func shutdownBlanksKeysAndStops() async {
    let (engine, transport) = await connectedEngine()
    transport.clear()
    engine.shutdown()
    let blank = KeyRenderer.render(.blank).jpeg
    #expect(transport.images.count == 15)
    #expect(transport.images.allSatisfy { $0.jpeg == blank })
    #expect(transport.stopped)
}

@MainActor @Test func redrawAllResendsEverything() async {
    let (engine, transport) = await connectedEngine()
    transport.clear()
    engine.redrawAll()
    #expect(transport.images.count == 15)
    #expect(transport.brightness == [55])
}

@MainActor @Test func deviceEventsArriveThroughTransportStream() async {
    let transport = FakeTransport()
    let engine = DeckEngine(transport: transport, performer: FakePerformer(), commands: noCommands, ownBundleID: "own", frontmostApp: nil)
    engine.start()
    engine.configLoaded(twoPages())
    transport.continuation.yield(.connected(info))
    await eventually { engine.status.connected }
    #expect(engine.status.connected)
}
