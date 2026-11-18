import DeckConfig
import DeckEngine
import Foundation
import Testing
@testable import DeckRender

/// The Linux starter must draw without problems on a renderer that has no SF Symbols.
@Test func linuxStarterRendersWithoutProblems() throws {
    let directory = FileManager.default.temporaryDirectory
    let config = try ConfigLoader.load(yaml: ConfigFile.linuxStarter, baseDirectory: directory).get()
    let renderer = KeyRenderer()
    var keys = 0
    for (name, page) in config.pages {
        for (index, key) in page.keys {
            let appearance = KeyAppearance(background: key.background ?? .black, icon: key.icon, image: key.image, label: key.label)
            let rendered = renderer.render(appearance)
            #expect(rendered.problems.isEmpty, "page \(name), key \(index): \(rendered.problems)")
            if case .symbol = key.icon { Issue.record("page \(name), key \(index) uses an SF Symbol") }
            if case let .keys(combo) = key.action { #expect(!combo.modifiers.contains(.fn)) }
            keys += 1
        }
    }
    #expect(keys > 10)
}
