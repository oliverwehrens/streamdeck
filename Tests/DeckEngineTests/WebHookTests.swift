import DeckConfig
import DeckHID
import Foundation
import Testing
@testable import DeckEngine

// Hooks for the web editor: key images, the overlay, and the web problem.

private let info = DeviceInfo(serial: "S", firmware: "F")

private func config() -> DeckConfig {
    DeckConfig(defaultPage: "home", pages: [
        "home": Page(keys: [
            0: KeyDefinition(label: "Zero", action: .run("zero")),
            14: KeyDefinition(label: "Fourteen"),
        ]),
        "media": Page(keys: [0: KeyDefinition(label: "Media")]),
    ])
}

@MainActor
private func engine(onDeck: Bool = true, performer: FakePerformer = FakePerformer()) -> (DeckEngine, FakeTransport) {
    let transport = FakeTransport()
    let engine = DeckEngine(transport: transport, renderer: FakeRenderer(), performer: performer, commands: noCommands,
                            configDirectory: testConfigDirectory, ownBundleID: "own", frontmostApp: nil,
                            showsProblemsOnDeck: onDeck)
    return (engine, transport)
}

private func image(_ appearance: KeyAppearance) -> Data { FakeRenderer().render(appearance).jpeg }
private func shown(_ transport: FakeTransport, _ key: Int) -> Data? { transport.images.last { $0.key == key }?.jpeg }

// MARK: - 3.1 Key images

@MainActor @Test func keyImagesWithoutDevice() {
    let (engine, transport) = engine()
    var reported: [Int: Data] = [:]
    engine.onKeyImage = { reported[$0] = $1 }
    engine.configLoaded(config())
    #expect(Set(reported.keys) == Set(0 ..< 15))
    #expect(reported[0] == image(KeyAppearance(label: "Zero")))
    #expect(engine.keyImages == reported)
    #expect(transport.images.isEmpty)
}

@MainActor @Test func unchangedImageIsNotReportedTwice() {
    let (engine, _) = engine()
    engine.configLoaded(config())
    var reported: [Int] = []
    engine.onKeyImage = { key, _ in reported.append(key) }
    engine.redrawAll()
    #expect(reported.isEmpty)
    engine.editorPage = "media"
    #expect(reported == [0, 14])
}

@MainActor @Test func keyImagesMatchTheDevice() {
    let (engine, transport) = engine()
    engine.configLoaded(config())
    engine.handle(.connected(info))
    for key in 0 ..< 15 { #expect(engine.keyImages[key] == shown(transport, key)) }
}

// MARK: - 3.2 Overlay

@MainActor @Test func overlayReplacesEveryKey() {
    let (engine, transport) = engine()
    engine.configLoaded(config())
    engine.handle(.connected(info))
    engine.editorPage = "media"
    engine.configFailed([ConfigError("bad")])
    let code = KeyAppearance(label: "48")
    engine.overlay = [6: code]
    #expect(shown(transport, 6) == image(code))
    #expect(shown(transport, 0) == image(.blank))
    #expect(shown(transport, 14) == image(.blank))
    #expect(engine.keyImages[6] == image(code))
}

@MainActor @Test func overlayPressRunsNoAction() async {
    let performer = FakePerformer()
    let (engine, _) = engine(performer: performer)
    engine.configLoaded(config())
    engine.handle(.connected(info))
    var pressed: [Int] = []
    engine.onOverlayKeyPress = { pressed.append($0) }
    engine.onEditorKeyPress = { _ in Issue.record("editor got the press") }
    engine.overlay = [:]
    engine.handle(.key(KeyEvent(key: 0, edge: .down)))
    engine.handle(.key(KeyEvent(key: 0, edge: .up)))
    try? await Task.sleep(for: .milliseconds(50))
    #expect(pressed == [0])
    #expect(performer.performed.isEmpty)
}

@MainActor @Test func clearingOverlayRestoresPageAndStatusKey() {
    let (engine, transport) = engine()
    engine.configLoaded(config())
    engine.handle(.connected(info))
    engine.overlay = [6: KeyAppearance(label: "48")]
    engine.configFailed([ConfigError("bad")])
    #expect(shown(transport, 14) == image(.blank))
    engine.overlay = nil
    #expect(shown(transport, 0) == image(KeyAppearance(label: "Zero")))
    #expect(shown(transport, 6) == image(.blank))
    #expect(shown(transport, 14) == image(DeckEngine.statusKeyAppearance(label: "Config")))
}

// MARK: - 3.3 Web problem

@MainActor @Test func webProblemOnStatusKey() {
    let (engine, transport) = engine()
    engine.configLoaded(config())
    engine.handle(.connected(info))
    engine.setWebProblem("web editor: cannot listen")
    #expect(shown(transport, 14) == image(DeckEngine.statusKeyAppearance(label: "Web")))
    #expect(engine.status.problems.contains { $0.source == .web })
    engine.configFailed([ConfigError("bad")])
    #expect(shown(transport, 14) == image(DeckEngine.statusKeyAppearance(label: "2 problems")))
    engine.configLoaded(config())
    engine.setWebProblem(nil)
    #expect(shown(transport, 14) == image(KeyAppearance(label: "Fourteen")))
}

@MainActor @Test func webProblemNotOnDeckWithoutFlag() {
    let (engine, transport) = engine(onDeck: false)
    engine.configLoaded(config())
    engine.handle(.connected(info))
    engine.setWebProblem("web editor: cannot listen")
    #expect(shown(transport, 14) == image(KeyAppearance(label: "Fourteen")))
}
