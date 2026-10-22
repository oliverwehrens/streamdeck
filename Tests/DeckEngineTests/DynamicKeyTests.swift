import DeckConfig
import DeckHID
import DeckRender
import Foundation
import Testing
@testable import DeckEngine

private func dynamicConfig(every: TimeInterval = 1) -> DeckConfig {
    DeckConfig(defaultPage: "home", pages: [
        "home": Page(keys: [
            0: KeyDefinition(label: "start", dynamic: Dynamic(run: "clock", every: every)),
            1: KeyDefinition(label: "Other", action: .page(.named("other"))),
        ]),
        "other": Page(keys: [
            0: KeyDefinition(label: "Back", action: .page(.back)),
        ]),
    ])
}

@MainActor
private func engine(_ commands: FakeCommands, config: DeckConfig = dynamicConfig()) -> (DeckEngine, FakeTransport) {
    let transport = FakeTransport()
    let engine = DeckEngine(transport: transport, performer: FakePerformer(), commands: commands, configDirectory: testConfigDirectory, ownBundleID: "own", frontmostApp: nil)
    engine.configLoaded(config)
    engine.handle(.connected(DeviceInfo(serial: "", firmware: "")))
    return (engine, transport)
}

private func image(label: String, error: Bool = false) -> Data {
    KeyRenderer.render(KeyAppearance(label: label, error: error)).jpeg
}

@MainActor @Test func firstLineOfOutputBecomesLabel() async {
    let commands = FakeCommands { _, _ in CommandResult(exitCode: 0, stdout: "  12:34  \nsecond line\n") }
    let (engine, transport) = engine(commands)
    await eventually { transport.images.last { $0.key == 0 }?.jpeg == image(label: "12:34") }
    #expect(transport.images.last { $0.key == 0 }?.jpeg == image(label: "12:34"))
    withExtendedLifetime(engine) {}
}

@MainActor @Test func runsRepeatedlyAtInterval() async {
    let commands = FakeCommands { _, call in CommandResult(exitCode: 0, stdout: "run \(call)") }
    let (engine, transport) = engine(commands)
    await eventually({ transport.images.contains { $0.key == 0 && $0.jpeg == image(label: "run 2") } }, timeout: .seconds(3))
    #expect(transport.images.contains { $0.key == 0 && $0.jpeg == image(label: "run 2") })
    withExtendedLifetime(engine) {}
}

@MainActor @Test func slowCommandsNeverOverlap() async {
    // Each run takes 1.5 s with a 1 s interval.
    let commands = FakeCommands { _, call in
        try? await Task.sleep(for: .milliseconds(1500))
        return CommandResult(exitCode: 0, stdout: "\(call)")
    }
    let (engine, _) = engine(commands)
    await eventually({ commands.state.calls["clock"] ?? 0 >= 2 }, timeout: .seconds(5))
    #expect(commands.state.calls["clock"] ?? 0 >= 2)
    #expect(commands.state.maxConcurrent["clock"] == 1)
    withExtendedLifetime(engine) {}
}

@MainActor @Test func notRunWhilePageNotShown() async {
    let commands = FakeCommands { _, _ in CommandResult(exitCode: 0, stdout: "x") }
    let (engine, _) = engine(commands)
    await eventually { commands.state.calls["clock"] == 1 }
    engine.handle(.key(KeyEvent(key: 1, edge: .down)))
    #expect(engine.status.page == "other")
    try? await Task.sleep(for: .milliseconds(1500))
    #expect(commands.state.calls["clock"] == 1)
}

@MainActor @Test func failureKeepsLastLabelAndShowsIndicator() async {
    let commands = FakeCommands { _, call in
        call == 1 ? CommandResult(exitCode: 0, stdout: "good") : CommandResult(exitCode: 1)
    }
    let (engine, transport) = engine(commands)
    await eventually({ transport.images.last { $0.key == 0 }?.jpeg == image(label: "good", error: true) }, timeout: .seconds(3))
    #expect(transport.images.last { $0.key == 0 }?.jpeg == image(label: "good", error: true))
    #expect(engine.status.problems.map(\.source) == [.dynamic(key: 0)])
    #expect(engine.status.problems.first?.message.contains("exited with status 1") == true)
}

@MainActor @Test func recoveryClearsIndicator() async {
    let commands = FakeCommands { _, call in
        call == 1 ? CommandResult(exitCode: 1) : CommandResult(exitCode: 0, stdout: "ok")
    }
    let (engine, transport) = engine(commands)
    await eventually({ transport.images.last { $0.key == 0 }?.jpeg == image(label: "ok") }, timeout: .seconds(3))
    #expect(transport.images.last { $0.key == 0 }?.jpeg == image(label: "ok"))
    #expect(engine.status.problems.isEmpty)
}

@MainActor @Test func timeoutShowsIndicator() async {
    let commands = FakeCommands { _, _ in CommandResult(exitCode: 15, timedOut: true) }
    let (engine, transport) = engine(commands)
    await eventually { !engine.status.problems.isEmpty }
    #expect(engine.status.problems.first?.message.contains("timed out after 10 s") == true)
    #expect(transport.images.last { $0.key == 0 }?.jpeg == image(label: "start", error: true))
}

@MainActor @Test func dynamicCommandGetsTenSecondTimeout() async {
    #expect(DeckEngine.dynamicTimeout == 10)
}

@Test func realHangingCommandIsKilledAtTimeout() async {
    let result = await ShellRunner().run("sleep 60", timeout: 1)
    #expect(result.timedOut)
}

// MARK: - JSON output

private let configuredIcon = Icon.symbol("bitcoinsign.circle")
private let configuredBackground = HexColor(red: 0x10, green: 0x10, blue: 0x10)
private let amber = HexColor(red: 0xc0, green: 0x80, blue: 0)

private func styledConfig() -> DeckConfig {
    DeckConfig(defaultPage: "home", pages: [
        "home": Page(keys: [
            0: KeyDefinition(icon: configuredIcon, label: "start", background: configuredBackground,
                             dynamic: Dynamic(run: "status", every: 1)),
        ]),
    ])
}

private func image(_ appearance: KeyAppearance) -> Data {
    KeyRenderer.render(appearance).jpeg
}

@MainActor @Test func jsonSetsIconLabelAndBackground() async {
    let commands = FakeCommands { _, _ in
        CommandResult(exitCode: 0, stdout: ##"{"label":"on","icon":"sf:lightbulb.fill","background":"#c08000"}"##)
    }
    let (engine, transport) = engine(commands, config: styledConfig())
    let expected = image(KeyAppearance(background: amber, icon: .symbol("lightbulb.fill"), label: "on"))
    await eventually { transport.images.last { $0.key == 0 }?.jpeg == expected }
    #expect(transport.images.last { $0.key == 0 }?.jpeg == expected)
    #expect(engine.status.problems.isEmpty)
}

@MainActor @Test func jsonOmittedFieldsFallBackToConfig() async {
    let commands = FakeCommands { _, _ in CommandResult(exitCode: 0, stdout: #"{"label":"67250"}"#) }
    let (engine, transport) = engine(commands, config: styledConfig())
    let expected = image(KeyAppearance(background: configuredBackground, icon: configuredIcon, label: "67250"))
    await eventually { transport.images.last { $0.key == 0 }?.jpeg == expected }
    #expect(transport.images.last { $0.key == 0 }?.jpeg == expected)
    withExtendedLifetime(engine) {}
}

@MainActor @Test func invalidJSONKeepsLastAppearance() async {
    let commands = FakeCommands { _, call in
        call == 1
            ? CommandResult(exitCode: 0, stdout: ##"{"label":"on","background":"#c08000"}"##)
            : CommandResult(exitCode: 0, stdout: #"{"label":"#)
    }
    let (engine, transport) = engine(commands, config: styledConfig())
    let expected = image(KeyAppearance(background: amber, icon: configuredIcon, label: "on", error: true))
    await eventually({ transport.images.last { $0.key == 0 }?.jpeg == expected }, timeout: .seconds(3))
    #expect(transport.images.last { $0.key == 0 }?.jpeg == expected)
    #expect(engine.status.problems.map(\.source) == [.dynamic(key: 0)])
    #expect(engine.status.problems.first?.message.contains("not valid JSON") == true)
}

@MainActor @Test func plainTextAfterJSONResetsToConfig() async {
    let commands = FakeCommands { _, call in
        call == 1
            ? CommandResult(exitCode: 0, stdout: ##"{"icon":"sf:lightbulb.fill","background":"#c08000"}"##)
            : CommandResult(exitCode: 0, stdout: "plain")
    }
    let (engine, transport) = engine(commands, config: styledConfig())
    let expected = image(KeyAppearance(background: configuredBackground, icon: configuredIcon, label: "plain"))
    await eventually({ transport.images.last { $0.key == 0 }?.jpeg == expected }, timeout: .seconds(3))
    #expect(transport.images.contains { $0.key == 0 && $0.jpeg == image(KeyAppearance(background: amber, icon: .symbol("lightbulb.fill"), label: "start")) })
    #expect(transport.images.last { $0.key == 0 }?.jpeg == expected)
    withExtendedLifetime(engine) {}
}

// MARK: - Full-key image

private func imageConfig() -> DeckConfig {
    DeckConfig(defaultPage: "home", pages: [
        "home": Page(keys: [0: KeyDefinition(image: "/configured.png", label: "start", dynamic: Dynamic(run: "art", every: 1))]),
    ])
}

@MainActor @Test func jsonImageReplacesConfiguredImage() async {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("dynamic-\(UUID().uuidString).png").path
    let commands = FakeCommands { _, _ in CommandResult(exitCode: 0, stdout: "{\"image\":\"\(path)\"}") }
    let (engine, transport) = engine(commands, config: imageConfig())
    // Neither file exists and both render alike, so wait for the problem to name the dynamic path.
    await eventually { engine.status.problems.first?.message.contains(path) == true }
    #expect(engine.status.problems.map(\.source) == [.icon(key: 0)])
    #expect(engine.status.problems.first?.message.contains(path) == true)
    #expect(transport.images.last { $0.key == 0 }?.jpeg == image(KeyAppearance(image: path, label: "start")))
}

@MainActor @Test func emptyJSONImageRemovesConfiguredImage() async {
    let commands = FakeCommands { _, _ in CommandResult(exitCode: 0, stdout: #"{"image":""}"#) }
    let (engine, transport) = engine(commands, config: imageConfig())
    await eventually { engine.status.problems.isEmpty }
    #expect(engine.status.problems.isEmpty)
    #expect(transport.images.last { $0.key == 0 }?.jpeg == image(KeyAppearance(label: "start")))
}

@MainActor @Test func omittedJSONImageKeepsConfiguredImage() async {
    let commands = FakeCommands { _, _ in CommandResult(exitCode: 0, stdout: #"{"label":"on"}"#) }
    let (engine, transport) = engine(commands, config: imageConfig())
    let expected = image(KeyAppearance(image: "/configured.png", label: "on"))
    await eventually { transport.images.last { $0.key == 0 }?.jpeg == expected }
    #expect(transport.images.last { $0.key == 0 }?.jpeg == expected)
    #expect(engine.status.problems.first?.message.contains("image file not found or unreadable: /configured.png") == true)
}
