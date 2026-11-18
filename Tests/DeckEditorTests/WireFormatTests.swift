import DeckConfig
import Foundation
import Testing
@testable import DeckEditor

private func roundTrip(_ document: ConfigDocument) throws -> ConfigDocument {
    let data = try JSONEncoder().encode(DocumentJSON(document))
    return try JSONDecoder().decode(DocumentJSON.self, from: data).document
}

@Test(arguments: [ConfigFile.macStarter, ConfigFile.linuxStarter])
func starterRoundTrips(starter: String) throws {
    let document = try ConfigDocument.read(yaml: starter).get()
    #expect(try roundTrip(document) == document)
}

@Test func invalidValuesSurvive() throws {
    let document = ConfigDocument(brightness: "abc", defaultPage: "home", pages: [
        PageDocument(name: "home", keys: [
            3: KeyDocument(label: "x", background: "red", action: ActionDocument(.keys, "cmd+"),
                           dynamic: DynamicDocument(run: "date", every: "soon")),
            99: KeyDocument(label: "outside"),
        ]),
    ], appPages: [AppPageDocument(bundleID: "steam:570", page: "nowhere")])
    #expect(try roundTrip(document) == document)
}

@Test func missingOptionalFieldsDecodeAsNil() throws {
    let json = #"{"defaultPage":"home","pages":[{"name":"home","keys":{"0":{"label":"Hi"}}}]}"#
    let document = try JSONDecoder().decode(DocumentJSON.self, from: Data(json.utf8)).document
    let key = try #require(document.page(named: "home")?.keys[0])
    #expect(key == KeyDocument(label: "Hi"))
    #expect(document.brightness == nil)
    #expect(document.appPages.isEmpty)
}

@Test func wireShape() throws {
    let document = ConfigDocument(defaultPage: "home", pages: [
        PageDocument(name: "home", keys: [0: KeyDocument(action: ActionDocument(.run, "true"))]),
    ], appPages: [AppPageDocument(bundleID: "com.apple.Safari", page: "home")])
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let text = String(decoding: try encoder.encode(DocumentJSON(document)), as: UTF8.self)
    #expect(text == #"{"appPages":[{"app":"com.apple.Safari","page":"home"}],"defaultPage":"home","pages":[{"keys":{"0":{"action":{"kind":"run","value":"true"}}},"name":"home"}]}"#)
}
