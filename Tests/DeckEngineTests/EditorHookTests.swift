import DeckConfig
import DeckHID
import DeckRender
import Foundation
import Testing
@testable import DeckEngine

private func pages() -> DeckConfig {
    DeckConfig(defaultPage: "home", pages: [
        "home": Page(keys: [0: KeyDefinition(label: "Home", action: .run("home"))]),
        "media": Page(keys: [0: KeyDefinition(label: "Media")]),
        "browser": Page(keys: [0: KeyDefinition(label: "Browser")]),
    ], appPages: ["com.apple.Safari": "browser"])
}

@MainActor
private func engine(performer: FakePerformer = FakePerformer(), commands: FakeCommands = noCommands) -> (DeckEngine, FakeTransport) {
    let transport = FakeTransport()
    let engine = DeckEngine(transport: transport, performer: performer, commands: commands, configDirectory: testConfigDirectory, ownBundleID: "own", frontmostApp: nil)
    engine.configLoaded(pages())
    engine.handle(.connected(DeviceInfo(serial: "", firmware: "")))
    return (engine, transport)
}

private func image(_ label: String) -> Data {
    KeyRenderer.render(KeyAppearance(label: label)).jpeg
}

// MARK: - 2.1 Editor page

@MainActor @Test func editorPageIsShown() {
    let (engine, transport) = engine()
    engine.editorPage = "media"
    #expect(engine.status.page == "media")
    #expect(transport.images.last { $0.key == 0 }?.jpeg == image("Media"))
}

@MainActor @Test func clearingEditorPageReturnsToNavigationPage() {
    let (engine, transport) = engine()
    engine.editorPage = "media"
    // The editor is focused, so another app activating only changes what navigation tracks.
    engine.appActivated(bundleID: "com.apple.Safari")
    #expect(engine.status.page == "media")
    engine.editorPage = nil
    #expect(engine.status.page == "browser")
    #expect(transport.images.last { $0.key == 0 }?.jpeg == image("Browser"))
}

@MainActor @Test func unknownEditorPageFallsBackToNavigation() {
    let (engine, _) = engine()
    engine.editorPage = "draft-only"
    #expect(engine.status.page == "home")
}

// MARK: - 2.2 Editor key presses

@MainActor @Test func editorKeyPressReplacesAction() async {
    let performer = FakePerformer()
    let (engine, _) = engine(performer: performer)
    var selected: [Int] = []
    engine.onEditorKeyPress = { selected.append($0) }
    engine.handle(.key(KeyEvent(key: 0, edge: .down)))
    engine.handle(.key(KeyEvent(key: 0, edge: .up)))
    // Key 9 has no definition and is still selectable.
    engine.handle(.key(KeyEvent(key: 9, edge: .down)))
    try? await Task.sleep(for: .milliseconds(100))
    #expect(selected == [0, 9])
    #expect(performer.performed.isEmpty)
}

@MainActor @Test func actionsRunAgainAfterEditorReleasesKeys() async {
    let performer = FakePerformer()
    let (engine, _) = engine(performer: performer)
    engine.onEditorKeyPress = { _ in }
    engine.onEditorKeyPress = nil
    engine.handle(.key(KeyEvent(key: 0, edge: .down)))
    await eventually { !performer.performed.isEmpty }
    #expect(performer.performed == [.run("home")])
}

// MARK: - 2.3 Identical config

@MainActor @Test func identicalConfigDoesNotRestartDynamicKeys() async {
    let commands = FakeCommands { _, _ in CommandResult(exitCode: 0, stdout: "x") }
    let config = DeckConfig(defaultPage: "home", pages: [
        "home": Page(keys: [0: KeyDefinition(dynamic: Dynamic(run: "clock", every: 60))]),
    ])
    let transport = FakeTransport()
    let engine = DeckEngine(transport: transport, performer: FakePerformer(), commands: commands, configDirectory: testConfigDirectory, ownBundleID: "own", frontmostApp: nil)
    engine.configLoaded(config)
    await eventually { commands.state.calls["clock"] == 1 }
    engine.configLoaded(config)
    try? await Task.sleep(for: .milliseconds(200))
    #expect(commands.state.calls["clock"] == 1)
}

@MainActor @Test func identicalConfigClearsConfigError() {
    let (engine, _) = engine()
    engine.configFailed([ConfigError("broken")])
    #expect(engine.status.problems.contains { $0.source == .config })
    engine.configLoaded(pages())
    #expect(!engine.status.problems.contains { $0.source == .config })
}
