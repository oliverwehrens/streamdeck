import DeckConfig

// JSON shapes of the config document and its errors, for the web editor's API.
// Every value stays text, as in `ConfigDocument`, so invalid input round-trips unchanged.

public struct DocumentJSON: Codable, Equatable, Sendable {
    public var brightness: String?
    public var defaultPage: String
    public var pages: [PageJSON]
    public var appPages: [AppPageJSON]

    public init(_ document: ConfigDocument) {
        brightness = document.brightness
        defaultPage = document.defaultPage
        pages = document.pages.map(PageJSON.init)
        appPages = document.appPages.map { AppPageJSON(app: $0.bundleID, page: $0.page) }
    }

    public var document: ConfigDocument {
        ConfigDocument(brightness: brightness, defaultPage: defaultPage, pages: pages.map(\.document),
                       appPages: appPages.map { AppPageDocument(bundleID: $0.app, page: $0.page) })
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try container.decodeIfPresent(String.self, forKey: .brightness)
        defaultPage = try container.decodeIfPresent(String.self, forKey: .defaultPage) ?? ""
        pages = try container.decodeIfPresent([PageJSON].self, forKey: .pages) ?? []
        appPages = try container.decodeIfPresent([AppPageJSON].self, forKey: .appPages) ?? []
    }
}

public struct PageJSON: Codable, Equatable, Sendable {
    public var name: String
    /// Key index as text ("0"…"14"), because JSON object keys are strings.
    public var keys: [String: KeyJSON]

    init(_ page: PageDocument) {
        name = page.name
        keys = Dictionary(uniqueKeysWithValues: page.keys.map { (String($0.key), KeyJSON($0.value)) })
    }

    var document: PageDocument {
        PageDocument(name: name, keys: Dictionary(keys.compactMap { key, value in Int(key).map { ($0, value.document) } },
                                                  uniquingKeysWith: { first, _ in first }))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        keys = try container.decodeIfPresent([String: KeyJSON].self, forKey: .keys) ?? [:]
    }
}

public struct KeyJSON: Codable, Equatable, Sendable {
    public var icon: String?
    public var image: String?
    public var label: String?
    public var background: String?
    public var action: ActionJSON?
    public var dynamic: DynamicJSON?

    public init(_ key: KeyDocument) {
        icon = key.icon
        image = key.image
        label = key.label
        background = key.background
        action = key.action.map { ActionJSON(kind: $0.kind.rawValue, value: $0.value) }
        dynamic = key.dynamic.map { DynamicJSON(run: $0.run, every: $0.every) }
    }

    /// Unknown action kinds are dropped; the browser only offers the known ones.
    public var document: KeyDocument {
        KeyDocument(icon: icon, image: image, label: label, background: background,
                    action: action.flatMap { action in ActionDocument.Kind(rawValue: action.kind).map { ActionDocument($0, action.value) } },
                    dynamic: dynamic.map { DynamicDocument(run: $0.run, every: $0.every) })
    }
}

public struct ActionJSON: Codable, Equatable, Sendable {
    public var kind: String
    public var value: String
}

public struct DynamicJSON: Codable, Equatable, Sendable {
    public var run: String
    public var every: String
}

public struct AppPageJSON: Codable, Equatable, Sendable {
    public var app: String
    public var page: String
}

public struct ErrorJSON: Codable, Equatable, Sendable {
    public var message: String
    public var line: Int?
    public var page: String?
    public var key: Int?

    public init(_ error: ConfigError) {
        message = error.message
        line = error.line
        page = error.page
        key = error.key
    }
}
