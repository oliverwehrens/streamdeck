import Foundation
import Yams

extension ConfigDocument {
    /// First line of every file the editor writes. A file without it was edited by hand.
    public static let header = "# Written by the StreamDeck config editor. Comments added here are not kept."

    public static func isEditorWritten(text: String) -> Bool {
        text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) == header
    }

    // MARK: - Reading

    /// Reads a config file as text values. Bad values are kept for the editor to show and fix;
    /// only structure the document cannot represent fails, such as invalid YAML or unknown fields.
    public static func read(yaml: String) -> Result<ConfigDocument, ConfigErrors> {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: yaml) else {
                return .failure(ConfigErrors([ConfigError("config file is empty")]))
            }
            root = node
        } catch {
            // The loader produces the located syntax error.
            if case let .failure(failure) = ConfigLoader.load(yaml: yaml, baseDirectory: URL(fileURLWithPath: "/")) {
                return .failure(failure)
            }
            return .failure(ConfigErrors([ConfigError("invalid YAML: \(error)")]))
        }
        var reader = DocumentReader()
        let document = reader.readRoot(root)
        if let document, reader.errors.isEmpty { return .success(document) }
        return .failure(ConfigErrors(reader.errors))
    }

    // MARK: - Writing

    /// The canonical YAML for this document, starting with `header`.
    public func yaml() -> String {
        var root: [(Node, Node)] = []
        if let brightness { root.append((scalar("brightness"), scalar(brightness))) }
        root.append((scalar("default_page"), scalar(defaultPage)))
        if !appPages.isEmpty {
            root.append((scalar("app_pages"), .mapping(.init(appPages.map { (scalar($0.bundleID), scalar($0.page)) }))))
        }
        let pageNodes = pages.map { page -> (Node, Node) in
            let keys = page.keys.keys.sorted().map { index in (scalar(String(index)), Self.keyNode(page.keys[index]!)) }
            let keysNode: Node = .mapping(.init(keys, .implicit, keys.isEmpty ? .flow : .block))
            return (scalar(page.name), .mapping(.init([(scalar("keys"), keysNode)])))
        }
        root.append((scalar("pages"), .mapping(.init(pageNodes))))

        // Serializing a tree of plain scalars and mappings cannot fail.
        let body = try! Yams.serialize(node: .mapping(.init(root)), width: -1, allowUnicode: true)
        return Self.header + "\n" + body
    }

    private static func keyNode(_ key: KeyDocument) -> Node {
        var pairs: [(Node, Node)] = []
        if let icon = key.icon { pairs.append((scalar("icon"), scalar(icon))) }
        if let label = key.label { pairs.append((scalar("label"), scalar(label))) }
        if let background = key.background { pairs.append((scalar("background"), scalar(background))) }
        if let action = key.action {
            pairs.append((scalar("action"), flow([(scalar(action.kind.rawValue), scalar(action.value))])))
        }
        if let dynamic = key.dynamic {
            pairs.append((scalar("dynamic"), flow([(scalar("run"), scalar(dynamic.run)), (scalar("every"), scalar(dynamic.every))])))
        }
        return flow(pairs)
    }
}

private func scalar(_ text: String) -> Node {
    .scalar(.init(text))
}

private func flow(_ pairs: [(Node, Node)]) -> Node {
    .mapping(.init(pairs, .implicit, .flow))
}

/// Copies a composed YAML tree into a `ConfigDocument`, reporting structure it cannot hold.
private struct DocumentReader {
    var errors: [ConfigError] = []

    mutating func readRoot(_ node: Node) -> ConfigDocument? {
        guard let map = mapping(node, what: "config") else { return nil }
        checkFields(map, allowed: ["brightness", "default_page", "pages", "app_pages"], what: "config")
        var document = ConfigDocument(defaultPage: "", pages: [])
        if let value = map["brightness"] { document.brightness = string(value, what: "brightness") }
        if let value = map["default_page"] { document.defaultPage = string(value, what: "default_page") ?? "" }
        if let value = map["app_pages"], let appMap = mapping(value, what: "app_pages") {
            for (idNode, pageNode) in appMap {
                guard let bundleID = string(idNode, what: "bundle ID"),
                      let page = string(pageNode, what: "app_pages entry") else { continue }
                document.appPages.append(AppPageDocument(bundleID: bundleID, page: page))
            }
        }
        if let value = map["pages"], let pageMap = mapping(value, what: "pages") {
            for (nameNode, pageNode) in pageMap {
                guard let name = string(nameNode, what: "page name") else { continue }
                if let page = readPage(pageNode, name: name) { document.pages.append(page) }
            }
        }
        return document
    }

    private mutating func readPage(_ node: Node, name: String) -> PageDocument? {
        guard let map = mapping(node, what: "page '\(name)'") else { return nil }
        checkFields(map, allowed: ["keys"], what: "page", page: name)
        var page = PageDocument(name: name)
        guard let keysNode = map["keys"], let keyMap = mapping(keysNode, what: "keys of page '\(name)'") else { return page }
        for (indexNode, keyNode) in keyMap {
            guard let index = indexNode.int else {
                fail("key index '\(indexNode.string ?? "?")' must be a number from 0 to 14", indexNode, page: name)
                continue
            }
            if let key = readKey(keyNode, page: name, index: index) { page.keys[index] = key }
        }
        return page
    }

    private mutating func readKey(_ node: Node, page: String, index: Int) -> KeyDocument? {
        guard let map = mapping(node, what: "key definition", page: page, key: index) else { return nil }
        checkFields(map, allowed: ["icon", "label", "background", "action", "dynamic"], what: "key", page: page, key: index)
        var key = KeyDocument()
        if let value = map["icon"] { key.icon = string(value, what: "icon", page: page, key: index) }
        if let value = map["label"] { key.label = string(value, what: "label", page: page, key: index) }
        if let value = map["background"] { key.background = string(value, what: "background", page: page, key: index) }
        if let value = map["action"], let actionMap = mapping(value, what: "action", page: page, key: index) {
            let kinds = ActionDocument.Kind.allCases
            checkFields(actionMap, allowed: Set(kinds.map(\.rawValue)), what: "action", page: page, key: index)
            let present = kinds.filter { actionMap[$0.rawValue] != nil }
            if present.count == 1, let kind = present.first,
               let text = string(actionMap[kind.rawValue]!, what: kind.rawValue, page: page, key: index) {
                key.action = ActionDocument(kind, text)
            } else if present.count != 1 {
                fail("action needs exactly one of: \(kinds.map(\.rawValue).joined(separator: ", "))", value, page: page, key: index)
            }
        }
        if let value = map["dynamic"], let dynamicMap = mapping(value, what: "dynamic", page: page, key: index) {
            checkFields(dynamicMap, allowed: ["run", "every"], what: "dynamic", page: page, key: index)
            let run = dynamicMap["run"].flatMap { string($0, what: "dynamic.run", page: page, key: index) }
            let every = dynamicMap["every"].flatMap { string($0, what: "dynamic.every", page: page, key: index) }
            key.dynamic = DynamicDocument(run: run ?? "", every: every ?? "")
        }
        return key
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
        errors.append(ConfigError(message, line: node.mark?.line, page: page, key: key))
    }
}
