import Foundation
import Testing
@testable import DeckConfig

/// The browser's keystroke recorder (Sources/CWebAssets/web/keys.js) is tested against the config's key names.
/// This test keeps Tests/web/fixtures/key-names.json in step: it rewrites a stale file and fails, so the change gets committed.
@Test func webKeyNamesFixtureIsCurrent() throws {
    let names = KeyCombo.canonicalNames.values.sorted()
    let characters = KeyCombo.usCharacterCodes.keys.map(String.init).sorted()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let expected = String(decoding: try encoder.encode(["names": names, "characters": characters]), as: UTF8.self) + "\n"

    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("web/fixtures/key-names.json")
    let current = try? String(contentsOf: url, encoding: .utf8)
    if current != expected {
        try Data(expected.utf8).write(to: url)
        Issue.record("\(url.path) was stale and has been rewritten; commit it")
    }
}
