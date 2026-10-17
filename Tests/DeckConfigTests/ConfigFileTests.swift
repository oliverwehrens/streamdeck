import Foundation
import Testing
@testable import DeckConfig

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("deckconfig-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func starterConfigIsWrittenAndValid() throws {
    let url = try temporaryDirectory().appendingPathComponent("nested/config.yaml")
    #expect(try ConfigFile.createStarterIfMissing(at: url))
    let config = try ConfigLoader.load(contentsOf: url).get()
    #expect(config.pages[config.defaultPage]?.keys.isEmpty == false)
}

@Test func existingConfigIsNotOverwritten() throws {
    let url = try temporaryDirectory().appendingPathComponent("config.yaml")
    try "mine".write(to: url, atomically: true, encoding: .utf8)
    #expect(try ConfigFile.createStarterIfMissing(at: url) == false)
    #expect(try String(contentsOf: url, encoding: .utf8) == "mine")
}

@Test func defaultLocation() {
    #expect(ConfigFile.defaultURL.path.hasSuffix("/.config/streamdeck/config.yaml"))
}
