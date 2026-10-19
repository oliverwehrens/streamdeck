import Foundation
import Testing
@testable import DeckConfig

let base = URL(fileURLWithPath: "/Users/test/.config/streamdeck")

func load(_ yaml: String) -> Result<DeckConfig, ConfigErrors> {
    ConfigLoader.load(yaml: yaml, baseDirectory: base)
}

func errors(_ yaml: String) -> [ConfigError] {
    if case let .failure(failure) = load(yaml) { return failure.errors }
    Issue.record("expected the config to fail")
    return []
}

// MARK: - 3.1 Model and decoding

@Test func minimalConfigLoads() throws {
    let config = try load("""
    default_page: home
    pages:
      home:
        keys:
          0: { label: Hi }
    """).get()
    #expect(config.brightness == 70)
    #expect(config.defaultPage == "home")
    #expect(config.pages["home"]?.keys[0] == KeyDefinition(label: "Hi"))
    #expect(config.pages["home"]?.keys[1] == nil)
    #expect(config.appPages.isEmpty)
}

@Test func fullKeyDefinitionDecodes() throws {
    let config = try load("""
    brightness: 40
    default_page: home
    app_pages:
      com.apple.Safari: home
    pages:
      home:
        keys:
          0: { icon: sf:play.fill, label: Play, background: "#1E90FF", action: { media: playpause } }
          1: { icon: icons/zoom.png, action: { keys: cmd+shift+m } }
          2: { icon: /abs/x.png, action: { run: "say hi" } }
          3: { action: { open: "https://example.com" } }
          4: { action: { page: back } }
          5: { dynamic: { run: "date +%H:%M", every: 30s } }
    """).get()
    let keys = try #require(config.pages["home"]?.keys)
    #expect(config.brightness == 40)
    #expect(config.appPages == ["com.apple.Safari": "home"])
    #expect(keys[0] == KeyDefinition(icon: .symbol("play.fill"), label: "Play",
                                     background: HexColor(red: 0x1E, green: 0x90, blue: 0xFF), action: .media(.playpause)))
    #expect(keys[1]?.icon == .file("/Users/test/.config/streamdeck/icons/zoom.png"))
    #expect(keys[1]?.action == .keys(KeyCombo(modifiers: [.cmd, .shift], keyCode: 0x2E)))
    #expect(keys[2]?.icon == .file("/abs/x.png"))
    #expect(keys[2]?.action == .run("say hi"))
    #expect(keys[3]?.action == .open("https://example.com"))
    #expect(keys[4]?.action == .page(.back))
    #expect(keys[5]?.dynamic == Dynamic(run: "date +%H:%M", every: 30))
}

@Test func unknownKeyFieldIsRejected() {
    let found = errors("""
    default_page: home
    pages:
      home:
        keys:
          3: { label: Hi, colour: red }
    """)
    #expect(found.count == 1)
    #expect(found.first?.message.contains("unknown field 'colour'") == true)
    #expect(found.first?.page == "home")
    #expect(found.first?.key == 3)
    #expect(found.first?.line == 5)
}

@Test func unknownTopLevelFieldIsRejected() {
    #expect(errors("default_page: home\npages: { home: { keys: {} } }\ntheme: dark\n").first?.message.contains("unknown field 'theme'") == true)
}

@Test func invalidYAMLReportsLine() {
    let found = errors("default_page: home\npages:\n  home: [unclosed\n")
    #expect(found.count == 1)
    #expect(found.first?.message.hasPrefix("invalid YAML") == true)
    #expect(found.first?.line != nil)
}

// MARK: - 3.2 Validation rules

@Test func keyIndexOutOfRange() {
    let found = errors("default_page: home\npages:\n  home:\n    keys:\n      15: { label: X }\n")
    #expect(found.first?.message.contains("out of range") == true)
    #expect(found.first?.page == "home")
    #expect(found.first?.key == 15)
}

@Test func unknownPageInAction() {
    let found = errors("default_page: home\npages:\n  home:\n    keys:\n      0: { action: { page: media } }\n")
    #expect(found.count == 1)
    #expect(found.first?.message.contains("unknown page 'media'") == true)
    #expect(found.first?.page == "home")
    #expect(found.first?.key == 0)
    #expect(found.first?.description.contains("page 'home', key 0: page action") == true)
}

@Test func unknownDefaultPage() {
    #expect(errors("default_page: nope\npages: { home: { keys: {} } }\n").first?.message.contains("default_page refers to unknown page 'nope'") == true)
}

@Test func unknownPageInAppPages() {
    let found = errors("default_page: home\napp_pages: { com.apple.Safari: web }\npages: { home: { keys: {} } }\n")
    #expect(found.first?.message.contains("'com.apple.Safari' refers to unknown page 'web'") == true)
}

@Test func missingRequiredFields() {
    let found = errors("brightness: 10\n")
    #expect(found.map(\.message).contains("default_page is required"))
    #expect(found.map(\.message).contains("pages is required"))
}

@Test func intervalBelowMinimum() {
    let found = errors("default_page: h\npages:\n  h:\n    keys:\n      0: { dynamic: { run: date, every: 200ms } }\n")
    #expect(found.first?.message.contains("1 second minimum") == true)
}

@Test func intervalNotADuration() {
    #expect(errors("default_page: h\npages: { h: { keys: { 0: { dynamic: { run: date, every: soon } } } } }\n")
        .first?.message.contains("must be a duration") == true)
}

@Test func twoActionTypesOnOneKey() {
    let found = errors("default_page: h\npages: { h: { keys: { 2: { action: { run: ls, open: /tmp } } } } }\n")
    #expect(found.first?.message.contains("more than one type") == true)
    #expect(found.first?.key == 2)
}

@Test func emptyAction() {
    #expect(errors("default_page: h\npages: { h: { keys: { 2: { action: {} } } } }\n").first?.message.contains("action needs one of") == true)
}

@Test func badHexColor() {
    #expect(errors("default_page: h\npages: { h: { keys: { 0: { background: blue } } } }\n").first?.message.contains("hex color") == true)
}

@Test func unknownComboKey() {
    let found = errors("default_page: h\npages: { h: { keys: { 0: { action: { keys: cmd+banana } } } } }\n")
    #expect(found.first?.message.contains("unknown key 'banana'") == true)
}

@Test func unknownMediaKey() {
    #expect(errors("default_page: h\npages: { h: { keys: { 0: { action: { media: louder } } } } }\n").first?.message.contains("unknown media key 'louder'") == true)
}

@Test func brightnessOutOfRange() {
    #expect(errors("brightness: 120\ndefault_page: h\npages: { h: { keys: {} } }\n").first?.message.contains("0 to 100") == true)
}

@Test func collectsAllErrors() {
    let found = errors("default_page: h\npages: { h: { keys: { 0: { foo: 1 }, 20: { label: x } } } }\n")
    #expect(found.count == 2)
}

@Test func errorDescriptionIncludesLocation() {
    #expect(ConfigError("bad", line: 4, page: "home", key: 2).description == "line 4, page 'home', key 2: bad")
}
