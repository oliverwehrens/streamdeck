import Foundation
import Testing
@testable import DeckConfig

/// The first ```yaml block in docs/config.md.
func documentedExample() throws -> String {
    let doc = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/config.md")
    let text = try String(contentsOf: doc, encoding: .utf8)
    let start = try #require(text.range(of: "```yaml\n"))
    let end = try #require(text.range(of: "```", range: start.upperBound ..< text.endIndex))
    return String(text[start.upperBound ..< end.lowerBound])
}

/// The documented example must be a valid config.
@Test func documentedExampleIsValid() throws {
    let config = try ConfigLoader.load(yaml: documentedExample(), baseDirectory: base).get()
    #expect(config.pages.count == 4)
    #expect(config.appPages.count == 2)
    #expect(config.pages["home"]?.keys[14]?.dynamic != nil)
}
