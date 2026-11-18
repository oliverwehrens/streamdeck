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

/// The key lines in the Linux section load as a page.
@Test func documentedLinuxKeysAreValid() throws {
    let doc = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/config.md")
    let text = try String(contentsOf: doc, encoding: .utf8)
    let section = try #require(text.range(of: "### Linux"))
    let start = try #require(text.range(of: "```yaml\n", range: section.upperBound ..< text.endIndex))
    let end = try #require(text.range(of: "```", range: start.upperBound ..< text.endIndex))
    let keys = text[start.upperBound ..< end.lowerBound].split(separator: "\n").map { "      " + $0 }.joined(separator: "\n")
    let yaml = "default_page: home\npages:\n  home:\n    keys:\n" + keys + "\n"
    let config = try ConfigLoader.load(yaml: yaml, baseDirectory: base).get()
    let home = try #require(config.pages["home"])
    #expect(home.keys[0]?.action == .open("steam://rungameid/570"))
    #expect(home.keys[2]?.action == .keys(try KeyCombo.parse("cmd+l").get()))
}
