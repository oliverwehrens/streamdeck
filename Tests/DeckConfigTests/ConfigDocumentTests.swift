import Foundation
import Testing
@testable import DeckConfig

func readDocument(_ yaml: String) -> Result<ConfigDocument, ConfigErrors> {
    ConfigDocument.read(yaml: yaml)
}

// MARK: - 1.2 Reading

@Test func documentedExampleReadsAsWritten() throws {
    let document = try readDocument(documentedExample()).get()
    #expect(document.brightness == "60")
    #expect(document.defaultPage == "home")
    #expect(document.pages.map(\.name) == ["home", "media", "browser", "xcode"])
    #expect(document.appPages == [
        AppPageDocument(bundleID: "com.apple.Safari", page: "browser"),
        AppPageDocument(bundleID: "com.apple.dt.Xcode", page: "xcode"),
    ])
    let home = try #require(document.page(named: "home"))
    #expect(home.keys[1]?.icon == "icons/zoom.png")
    #expect(home.keys[2]?.background == "#B00020")
    #expect(home.keys[3]?.action == ActionDocument(.keys, "cmd+shift+m"))
    #expect(home.keys[14]?.dynamic == DynamicDocument(run: "date +%H:%M", every: "30s"))
}

@Test func valuesKeepTheirSpelling() throws {
    let document = try readDocument("""
    default_page: home
    pages:
      home:
        keys:
          0: { action: { keys: option+x } }
          1: { dynamic: { run: uptime, every: 0.5m } }
    """).get()
    let keys = try #require(document.page(named: "home")).keys
    #expect(keys[0]?.action == ActionDocument(.keys, "option+x"))
    #expect(keys[1]?.dynamic?.every == "0.5m")
}

@Test func badValuesAreKept() throws {
    let document = try readDocument("""
    brightness: lots
    default_page: missing
    pages:
      home:
        keys:
          0: { background: red, action: { keys: "cmd+" } }
          20: { label: Off the deck }
    """).get()
    let keys = try #require(document.page(named: "home")).keys
    #expect(document.brightness == "lots")
    #expect(document.defaultPage == "missing")
    #expect(keys[0]?.background == "red")
    #expect(keys[0]?.action == ActionDocument(.keys, "cmd+"))
    #expect(keys[20]?.label == "Off the deck")
}

@Test func unknownFieldFails() {
    guard case let .failure(failure) = readDocument("""
    default_page: home
    pages:
      home:
        keys:
          0: { label: Hi, colour: "#000000" }
    """) else {
        Issue.record("expected the read to fail")
        return
    }
    #expect(failure.errors.count == 1)
    #expect(failure.errors.first?.message.contains("colour") == true)
    #expect(failure.errors.first?.key == 0)
}

@Test func invalidYAMLFailsWithLine() {
    guard case let .failure(failure) = readDocument("default_page: home\npages: [\n") else {
        Issue.record("expected the read to fail")
        return
    }
    #expect(failure.errors.first?.line != nil)
}

@Test func actionWithTwoKindsFails() {
    guard case .failure = readDocument("""
    default_page: home
    pages:
      home:
        keys:
          0: { action: { run: ls, open: /tmp } }
    """) else {
        Issue.record("expected the read to fail")
        return
    }
}

// MARK: - 1.3 Writing

@Test func writesCanonicalYAML() {
    let document = ConfigDocument(brightness: "60", defaultPage: "home", pages: [
        PageDocument(name: "home", keys: [
            10: KeyDocument(label: "Hello", background: "#2D6A4F", action: ActionDocument(.run, "say hello")),
            0: KeyDocument(icon: "sf:terminal", label: "Terminal", action: ActionDocument(.page, "empty")),
            1: KeyDocument(icon: "sf:play.fill", image: "art/cat.jpg", label: "Cat"),
            14: KeyDocument(dynamic: DynamicDocument(run: "date", every: "30s")),
        ]),
        PageDocument(name: "empty"),
    ], appPages: [AppPageDocument(bundleID: "com.apple.Safari", page: "empty")])

    #expect(document.yaml() == """
    # Written by the StreamDeck config editor. Comments added here are not kept.
    brightness: 60
    default_page: home
    app_pages:
      com.apple.Safari: empty
    pages:
      home:
        keys:
          0: {icon: 'sf:terminal', label: Terminal, action: {page: empty}}
          1: {icon: 'sf:play.fill', image: art/cat.jpg, label: Cat}
          10: {label: Hello, background: '#2D6A4F', action: {run: say hello}}
          14: {dynamic: {run: date, every: 30s}}
      empty:
        keys: {}

    """)
}

@Test func omittedFieldsStayOmitted() throws {
    let yaml = ConfigDocument(defaultPage: "home", pages: [PageDocument(name: "home", keys: [0: KeyDocument(label: "Hi")])]).yaml()
    #expect(!yaml.contains("brightness"))
    #expect(!yaml.contains("app_pages"))
    #expect(try load(yaml).get().brightness == DeckConfig.defaultBrightness)
}

@Test(arguments: ["a # b", "key: value", "say \"hi\"", "it's", "~/bin/x.sh", "~", "", "true", "null", "123", "- dash", "[x]", "{y}", "*star", "&anchor", "!tag", "50%", "ümlaut ✓", "line\nbreak"])
func awkwardTextSurvives(_ text: String) throws {
    let document = ConfigDocument(defaultPage: "home", pages: [
        PageDocument(name: "home", keys: [0: KeyDocument(icon: text, label: text, action: ActionDocument(.run, text))]),
    ])
    let readBack = try readDocument(document.yaml()).get()
    #expect(readBack == document)
}

// MARK: - 1.4 Round trip

/// Writes the YAML's document, then checks that loading the output gives the same config
/// and reading it back gives the same document.
private func expectRoundTrip(_ yaml: String) throws {
    let document = try readDocument(yaml).get()
    let written = document.yaml()
    #expect(try readDocument(written).get() == document)
    #expect(try load(written).get() == load(yaml).get())
}

@Test func starterConfigRoundTrips() throws {
    try expectRoundTrip(ConfigFile.starter)
}

@Test func documentedExampleRoundTrips() throws {
    try expectRoundTrip(documentedExample())
}

@Test(arguments: 0 ..< 200)
func generatedDocumentRoundTrips(seed: UInt64) throws {
    var random = SeededRandom(seed: seed)
    let document = generateDocument(&random)
    let written = document.yaml()
    #expect(try readDocument(written).get() == document)
    // Generated documents are valid, so the loader must accept them.
    #expect(throws: Never.self) { try load(written).get() }
}

/// SplitMix64, so failures reproduce from the seed.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let texts = ["Hi", "a # b", "key: value", "say \"hi\"", "it's", "~/bin/x.sh", "true", "123", "- dash", "50%", "ümlaut ✓", "{y}", ""]

private func generateDocument(_ random: inout SeededRandom) -> ConfigDocument {
    let names = Array(["home", "media", "zoom call", "1", "true", "a: b"].shuffled(using: &random).prefix(Int.random(in: 1 ... 4, using: &random)))
    func pick<T>(_ values: [T]) -> T { values.randomElement(using: &random)! }
    func maybe<T>(_ make: () -> T) -> T? { Bool.random(using: &random) ? make() : nil }

    let pages = names.map { name in
        var keys: [Int: KeyDocument] = [:]
        for index in (0 ..< DeckConfig.keyCount).shuffled(using: &random).prefix(Int.random(in: 0 ... 6, using: &random)) {
            keys[index] = KeyDocument(
                icon: maybe { pick(["sf:terminal", "icons/zoom.png", "~/icons/x.png", "/tmp/a b.png"]) },
                image: maybe { pick(["art/cat.jpg", "~/Pictures/a b.png", "/tmp/x.png"]) },
                label: maybe { pick(texts) },
                background: maybe { String(format: "#%06X", Int.random(in: 0 ... 0xFFFFFF, using: &random)) },
                action: maybe {
                    switch pick(ActionDocument.Kind.allCases) {
                    case .run: ActionDocument(.run, pick(texts))
                    case .open: ActionDocument(.open, pick(["https://example.com/?a=1&b=2", "/Applications/Safari.app", "~/Documents"]))
                    case .keys: ActionDocument(.keys, pick(["cmd+shift+m", "option+x", "ctrl+f5", "cmd+;"]))
                    case .media: ActionDocument(.media, pick(MediaKey.allCases).rawValue)
                    case .page: ActionDocument(.page, pick(names + ["back"]))
                    }
                },
                dynamic: maybe { DynamicDocument(run: pick(texts.filter { !$0.isEmpty }), every: pick(["1s", "30s", "0.5m", "2h", "1500ms"])) }
            )
        }
        return PageDocument(name: name, keys: keys)
    }
    return ConfigDocument(
        brightness: maybe { String(Int.random(in: 0 ... 100, using: &random)) },
        defaultPage: pick(names),
        pages: pages,
        appPages: maybe { [AppPageDocument(bundleID: "com.apple.Safari", page: pick(names))] } ?? []
    )
}

// MARK: - 1.5 Page management

private func sampleDocument() -> ConfigDocument {
    ConfigDocument(defaultPage: "home", pages: [
        PageDocument(name: "home", keys: [
            4: KeyDocument(label: "Media", action: ActionDocument(.page, "media")),
            5: KeyDocument(action: ActionDocument(.run, "media")),
        ]),
        PageDocument(name: "media", keys: [
            14: KeyDocument(action: ActionDocument(.page, "back")),
            13: KeyDocument(action: ActionDocument(.page, "media")),
        ]),
        PageDocument(name: "spare"),
    ], appPages: [
        AppPageDocument(bundleID: "com.spotify.client", page: "media"),
        AppPageDocument(bundleID: "com.apple.Safari", page: "home"),
    ])
}

@Test func addPage() throws {
    var document = sampleDocument()
    #expect(try document.addPage(named: " zoom ") == "zoom")
    #expect(document.pages.last == PageDocument(name: "zoom"))
}

@Test func pageNamesMustBeValid() {
    var document = sampleDocument()
    #expect(throws: PageNameError.empty) { try document.addPage(named: "  ") }
    #expect(throws: PageNameError.reserved) { try document.addPage(named: "back") }
    #expect(throws: PageNameError.taken("media")) { try document.addPage(named: "media") }
    #expect(throws: PageNameError.taken("media")) { try document.renamePage("spare", to: "media") }
    #expect(document == sampleDocument())
}

@Test func renameUpdatesReferences() throws {
    var document = sampleDocument()
    try document.renamePage("media", to: "music")
    #expect(document.pages.map(\.name) == ["home", "music", "spare"])
    #expect(document.page(named: "home")?.keys[4]?.action == ActionDocument(.page, "music"))
    #expect(document.page(named: "home")?.keys[5]?.action == ActionDocument(.run, "media"))
    #expect(document.page(named: "music")?.keys[13]?.action == ActionDocument(.page, "music"))
    #expect(document.page(named: "music")?.keys[14]?.action == ActionDocument(.page, "back"))
    #expect(document.appPages.first == AppPageDocument(bundleID: "com.spotify.client", page: "music"))
    #expect(try load(document.yaml()).get().pages["music"] != nil)
}

@Test func renameDefaultPage() throws {
    var document = sampleDocument()
    try document.renamePage("home", to: "start")
    #expect(document.defaultPage == "start")
    #expect(document.appPages.last?.page == "start")
}

@Test func renameToSameNameIsNoChange() throws {
    var document = sampleDocument()
    try document.renamePage("media", to: "media")
    #expect(document == sampleDocument())
}

@Test func deleteReferencedPageIsRefused() {
    var document = sampleDocument()
    let references = document.deletePage("media")
    #expect(references == [.appPage(bundleID: "com.spotify.client"), .key(page: "home", index: 4), .key(page: "media", index: 13)])
    #expect(references.map(\.description).contains("page 'home', key 4"))
    #expect(document == sampleDocument())
}

@Test func deleteUnreferencedPage() {
    var document = sampleDocument()
    #expect(document.deletePage("spare").isEmpty)
    #expect(document.page(named: "spare") == nil)
}

// MARK: - 1.6 Editor-written files

@Test func editorWrittenFileIsRecognized() {
    let yaml = ConfigDocument(defaultPage: "home", pages: [PageDocument(name: "home")]).yaml()
    #expect(ConfigDocument.isEditorWritten(text: yaml))
}

@Test func handEditedFileIsNotEditorWritten() {
    let yaml = ConfigDocument(defaultPage: "home", pages: [PageDocument(name: "home")]).yaml()
    #expect(!ConfigDocument.isEditorWritten(text: "# my notes\n" + yaml))
    #expect(!ConfigDocument.isEditorWritten(text: ConfigFile.starter))
    #expect(!ConfigDocument.isEditorWritten(text: ""))
}
