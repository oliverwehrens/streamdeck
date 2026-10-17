import Foundation
import Testing
@testable import DeckConfig

/// The first ```yaml block in docs/config.md must be a valid config.
@Test func documentedExampleIsValid() throws {
    let doc = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/config.md")
    let text = try String(contentsOf: doc, encoding: .utf8)
    let start = try #require(text.range(of: "```yaml\n"))
    let end = try #require(text.range(of: "```", range: start.upperBound ..< text.endIndex))
    let yaml = String(text[start.upperBound ..< end.lowerBound])

    let config = try ConfigLoader.load(yaml: yaml, baseDirectory: base).get()
    #expect(config.pages.count == 4)
    #expect(config.appPages.count == 2)
    #expect(config.pages["home"]?.keys[14]?.dynamic != nil)
}
