import Foundation
import Yams

public struct ConfigError: Error, Equatable, CustomStringConvertible, Sendable {
    public var message: String
    public var line: Int?
    public var page: String?
    public var key: Int?

    public init(_ message: String, line: Int? = nil, page: String? = nil, key: Int? = nil) {
        self.message = message
        self.line = line
        self.page = page
        self.key = key
    }

    public var description: String {
        var location: [String] = []
        if let line { location.append("line \(line)") }
        if let page { location.append("page '\(page)'") }
        if let key { location.append("key \(key)") }
        return location.isEmpty ? message : "\(location.joined(separator: ", ")): \(message)"
    }
}

public struct ConfigErrors: Error, Equatable, Sendable {
    public var errors: [ConfigError]

    public init(_ errors: [ConfigError]) {
        self.errors = errors
    }
}

/// Parses and validates the YAML config. All problems are collected, not just the first.
public enum ConfigLoader {
    public static func load(contentsOf url: URL) -> Result<DeckConfig, ConfigErrors> {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            return load(yaml: text, baseDirectory: url.deletingLastPathComponent())
        } catch {
            return .failure(ConfigErrors([ConfigError("cannot read \(url.path): \(error.localizedDescription)")]))
        }
    }

    public static func load(yaml: String, baseDirectory: URL) -> Result<DeckConfig, ConfigErrors> {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: yaml) else {
                return .failure(ConfigErrors([ConfigError("config file is empty")]))
            }
            root = node
        } catch let error as YamlError {
            return .failure(ConfigErrors([syntaxError(error)]))
        } catch {
            return .failure(ConfigErrors([ConfigError("invalid YAML: \(error)")]))
        }
        var parser = Parser(baseDirectory: baseDirectory)
        let config = parser.parseRoot(root)
        if let config { parser.checkReferences(config) }
        if let config, parser.errors.isEmpty { return .success(config) }
        return .failure(ConfigErrors(parser.errors))
    }

    private static func syntaxError(_ error: YamlError) -> ConfigError {
        switch error {
        case let .scanner(_, problem, mark, _), let .parser(_, problem, mark, _), let .composer(_, problem, mark, _):
            ConfigError("invalid YAML: \(problem)", line: mark.line)
        default:
            ConfigError("invalid YAML: \(error)")
        }
    }
}

private struct Reference {
    let page: String
    let line: Int?
    let context: String
    /// Where the reference sits, when it is on a key.
    var sourcePage: String?
    var sourceKey: Int?
}

private struct Parser {
    let baseDirectory: URL
    var errors: [ConfigError] = []
    var references: [Reference] = []

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    mutating func parseRoot(_ node: Node) -> DeckConfig? {
        guard let map = mapping(node, what: "config") else { return nil }
        checkFields(map, allowed: ["brightness", "default_page", "pages", "app_pages"], what: "config")

        var brightness = DeckConfig.defaultBrightness
        if let value = map["brightness"] {
            if let int = value.int, (0 ... 100).contains(int) {
                brightness = int
            } else {
                fail("brightness must be a whole number from 0 to 100", value)
            }
        }

        var defaultPage = ""
        if let value = map["default_page"], let name = string(value, what: "default_page") {
            defaultPage = name
            references.append(Reference(page: name, line: value.line, context: "default_page"))
        } else if map["default_page"] == nil {
            fail("default_page is required", node)
        }

        var pages: [String: Page] = [:]
        if let value = map["pages"], let pageMap = mapping(value, what: "pages") {
            for (nameNode, pageNode) in pageMap {
                guard let name = string(nameNode, what: "page name") else { continue }
                if let page = parsePage(pageNode, name: name) { pages[name] = page }
            }
            if pageMap.count == 0 { fail("pages must define at least one page", value) }
        } else if map["pages"] == nil {
            fail("pages is required", node)
        }

        var appPages: [String: String] = [:]
        if let value = map["app_pages"], let appMap = mapping(value, what: "app_pages") {
            for (idNode, pageNode) in appMap {
                guard let bundleID = string(idNode, what: "bundle ID"),
                      let page = string(pageNode, what: "app_pages entry") else { continue }
                appPages[bundleID] = page
                references.append(Reference(page: page, line: pageNode.line, context: "app_pages entry '\(bundleID)'"))
            }
        }

        return DeckConfig(brightness: brightness, defaultPage: defaultPage, pages: pages, appPages: appPages)
    }

    mutating func checkReferences(_ config: DeckConfig) {
        for reference in references where config.pages[reference.page] == nil {
            errors.append(ConfigError("\(reference.context) refers to unknown page '\(reference.page)'",
                                      line: reference.line, page: reference.sourcePage, key: reference.sourceKey))
        }
    }

    // MARK: - Pages and keys

    private mutating func parsePage(_ node: Node, name: String) -> Page? {
        guard let map = mapping(node, what: "page '\(name)'") else { return nil }
        checkFields(map, allowed: ["keys"], what: "page", page: name)
        var keys: [Int: KeyDefinition] = [:]
        if let keysNode = map["keys"], let keyMap = mapping(keysNode, what: "keys of page '\(name)'") {
            for (indexNode, keyNode) in keyMap {
                guard let index = indexNode.int else {
                    fail("key index '\(indexNode.string ?? "?")' must be a number from 0 to 14", indexNode, page: name)
                    continue
                }
                guard (0 ..< DeckConfig.keyCount).contains(index) else {
                    fail("key index \(index) is out of range 0-14", indexNode, page: name, key: index)
                    continue
                }
                if let key = parseKey(keyNode, page: name, index: index) { keys[index] = key }
            }
        }
        return Page(keys: keys)
    }

    private mutating func parseKey(_ node: Node, page: String, index: Int) -> KeyDefinition? {
        guard let map = mapping(node, what: "key definition", page: page, key: index) else { return nil }
        checkFields(map, allowed: ["icon", "image", "label", "background", "action", "dynamic"], what: "key", page: page, key: index)
        var key = KeyDefinition()

        if let value = map["icon"], let text = string(value, what: "icon", page: page, key: index) {
            key.icon = Icon(configValue: text, relativeTo: baseDirectory)
        }
        if let value = map["image"], let text = string(value, what: "image", page: page, key: index) {
            if text.hasPrefix("sf:") {
                fail("image '\(text)' must be an image file; SF Symbols belong in icon", value, page: page, key: index)
            } else {
                key.image = resolvePath(text, relativeTo: baseDirectory)
            }
        }
        if let value = map["label"] {
            key.label = string(value, what: "label", page: page, key: index)
        }
        if let value = map["background"], let text = string(value, what: "background", page: page, key: index) {
            if let color = HexColor(hex: text) {
                key.background = color
            } else {
                fail("background '\(text)' must be a hex color like #1E90FF", value, page: page, key: index)
            }
        }
        if let value = map["action"] {
            key.action = parseAction(value, page: page, index: index)
        }
        if let value = map["dynamic"] {
            key.dynamic = parseDynamic(value, page: page, index: index)
        }
        return key
    }

    private mutating func parseAction(_ node: Node, page: String, index: Int) -> Action? {
        let kinds = ["run", "open", "keys", "media", "page"]
        guard let map = mapping(node, what: "action", page: page, key: index) else { return nil }
        checkFields(map, allowed: Set(kinds), what: "action", page: page, key: index)
        let present = kinds.filter { map[$0] != nil }
        guard present.count == 1, let kind = present.first, let valueNode = map[kind] else {
            let message = present.isEmpty
                ? "action needs one of: \(kinds.joined(separator: ", "))"
                : "action has more than one type (\(present.joined(separator: ", "))); use exactly one"
            fail(message, node, page: page, key: index)
            return nil
        }
        guard let value = string(valueNode, what: kind, page: page, key: index) else { return nil }

        switch kind {
        case "run":
            return .run(value)
        case "open":
            return .open(value)
        case "keys":
            switch KeyCombo.parse(value) {
            case let .success(combo):
                return .keys(combo)
            case let .failure(error):
                fail(Self.describe(error, in: value), valueNode, page: page, key: index)
                return nil
            }
        case "media":
            guard let media = MediaKey(rawValue: value) else {
                let names = MediaKey.allCases.map(\.rawValue).joined(separator: ", ")
                fail("unknown media key '\(value)'; use one of: \(names)", valueNode, page: page, key: index)
                return nil
            }
            return .media(media)
        default:
            if value == "back" { return .page(.back) }
            references.append(Reference(page: value, line: valueNode.line, context: "page action", sourcePage: page, sourceKey: index))
            return .page(.named(value))
        }
    }

    private mutating func parseDynamic(_ node: Node, page: String, index: Int) -> Dynamic? {
        guard let map = mapping(node, what: "dynamic", page: page, key: index) else { return nil }
        checkFields(map, allowed: ["run", "every"], what: "dynamic", page: page, key: index)
        guard let runNode = map["run"], let everyNode = map["every"] else {
            fail("dynamic needs both 'run' and 'every'", node, page: page, key: index)
            return nil
        }
        guard let run = string(runNode, what: "dynamic.run", page: page, key: index),
              let everyText = string(everyNode, what: "dynamic.every", page: page, key: index) else { return nil }
        guard let every = Self.parseDuration(everyText) else {
            fail("every '\(everyText)' must be a duration like 500ms, 5s, 1m or 1h", everyNode, page: page, key: index)
            return nil
        }
        guard every >= Dynamic.minimumInterval else {
            fail("every '\(everyText)' is below the 1 second minimum", everyNode, page: page, key: index)
            return nil
        }
        return Dynamic(run: run, every: every)
    }

    // MARK: - Helpers

    static func parseDuration(_ text: String) -> TimeInterval? {
        let units: [(String, TimeInterval)] = [("ms", 0.001), ("s", 1), ("m", 60), ("h", 3600)]
        for (suffix, factor) in units where text.hasSuffix(suffix) {
            if let number = Double(text.dropLast(suffix.count)), number >= 0 { return number * factor }
        }
        return nil
    }

    static func describe(_ error: KeyCombo.ParseError, in text: String) -> String {
        switch error {
        case .empty: "keys must not be empty"
        case let .unknownKey(name): "unknown key '\(name)' in '\(text)'"
        case .missingKey: "keys '\(text)' has only modifiers; add a key"
        case let .multipleKeys(a, b): "keys '\(text)' has two keys ('\(a)' and '\(b)'); use one key plus modifiers"
        }
    }

    private mutating func mapping(_ node: Node, what: String, page: String? = nil, key: Int? = nil) -> Node.Mapping? {
        if let map = node.mapping { return map }
        fail("\(what) must be a mapping", node, page: page, key: key)
        return nil
    }

    private mutating func string(_ node: Node, what: String, page: String? = nil, key: Int? = nil) -> String? {
        if let scalar = node.scalar { return scalar.string }
        fail("\(what) must be a single value", node, page: page, key: key)
        return nil
    }

    private mutating func checkFields(_ map: Node.Mapping, allowed: Set<String>, what: String, page: String? = nil, key: Int? = nil) {
        for (fieldNode, _) in map {
            guard let field = fieldNode.string, !allowed.contains(field) else { continue }
            let expected = allowed.sorted().joined(separator: ", ")
            fail("unknown field '\(field)' in \(what); allowed: \(expected)", fieldNode, page: page, key: key)
        }
    }

    private mutating func fail(_ message: String, _ node: Node, page: String? = nil, key: Int? = nil) {
        errors.append(ConfigError(message, line: node.line, page: page, key: key))
    }
}

private extension Node {
    var line: Int? { mark?.line }
}
