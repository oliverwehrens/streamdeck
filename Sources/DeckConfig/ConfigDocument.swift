import Foundation

/// The config as the user wrote it, for editing. Every value is kept as text, so the document
/// can hold invalid input and write back exactly what was typed. Validate with `ConfigLoader`.
public struct ConfigDocument: Equatable, Sendable {
    /// nil when the field is omitted (the loader then uses the default).
    public var brightness: String?
    public var defaultPage: String
    /// In the order they appear in the file and the editor.
    public var pages: [PageDocument]
    public var appPages: [AppPageDocument]

    public init(brightness: String? = nil, defaultPage: String, pages: [PageDocument], appPages: [AppPageDocument] = []) {
        self.brightness = brightness
        self.defaultPage = defaultPage
        self.pages = pages
        self.appPages = appPages
    }

    public func page(named name: String) -> PageDocument? {
        pages.first { $0.name == name }
    }
}

public struct PageDocument: Equatable, Sendable {
    public var name: String
    public var keys: [Int: KeyDocument]

    public init(name: String, keys: [Int: KeyDocument] = [:]) {
        self.name = name
        self.keys = keys
    }
}

public struct KeyDocument: Equatable, Sendable {
    public var icon: String?
    public var label: String?
    public var background: String?
    public var action: ActionDocument?
    public var dynamic: DynamicDocument?

    public init(icon: String? = nil, label: String? = nil, background: String? = nil, action: ActionDocument? = nil, dynamic: DynamicDocument? = nil) {
        self.icon = icon
        self.label = label
        self.background = background
        self.action = action
        self.dynamic = dynamic
    }
}

public struct ActionDocument: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case run, open, keys, media, page
    }

    public var kind: Kind
    public var value: String

    public init(_ kind: Kind, _ value: String) {
        self.kind = kind
        self.value = value
    }
}

public struct DynamicDocument: Equatable, Sendable {
    public var run: String
    public var every: String

    public init(run: String, every: String) {
        self.run = run
        self.every = every
    }
}

public struct AppPageDocument: Equatable, Sendable {
    public var bundleID: String
    public var page: String

    public init(bundleID: String, page: String) {
        self.bundleID = bundleID
        self.page = page
    }
}

// MARK: - Page management

public enum PageNameError: Error, Equatable, Sendable {
    case empty
    /// `back` is the page action that returns to the previous page.
    case reserved
    case taken(String)
}

/// A place in the config that names a page.
public enum PageReference: Equatable, Sendable, CustomStringConvertible {
    case defaultPage
    case key(page: String, index: Int)
    case appPage(bundleID: String)

    public var description: String {
        switch self {
        case .defaultPage: "default page"
        case let .key(page, index): "page '\(page)', key \(index)"
        case let .appPage(bundleID): "app page for \(bundleID)"
        }
    }
}

extension ConfigDocument {
    /// Adds an empty page at the end. Returns the trimmed name it was added under.
    @discardableResult
    public mutating func addPage(named name: String) throws(PageNameError) -> String {
        let name = try checkedName(name, replacing: nil)
        pages.append(PageDocument(name: name))
        return name
    }

    /// Renames a page and every `page` action, `app_pages` entry and `default_page` that names it.
    public mutating func renamePage(_ old: String, to new: String) throws(PageNameError) {
        let new = try checkedName(new, replacing: old)
        guard new != old, let position = pages.firstIndex(where: { $0.name == old }) else { return }
        pages[position].name = new
        for pageIndex in pages.indices {
            for (keyIndex, key) in pages[pageIndex].keys where key.action == ActionDocument(.page, old) {
                pages[pageIndex].keys[keyIndex]?.action?.value = new
            }
        }
        for index in appPages.indices where appPages[index].page == old {
            appPages[index].page = new
        }
        if defaultPage == old { defaultPage = new }
    }

    /// Everything that names `page`, in file order.
    public func references(to page: String) -> [PageReference] {
        var references: [PageReference] = []
        if defaultPage == page { references.append(.defaultPage) }
        for appPage in appPages where appPage.page == page {
            references.append(.appPage(bundleID: appPage.bundleID))
        }
        for source in pages {
            for index in source.keys.keys.sorted() where source.keys[index]?.action == ActionDocument(.page, page) {
                references.append(.key(page: source.name, index: index))
            }
        }
        return references
    }

    /// Deletes the page if nothing names it. Returns the references that prevent deletion, or [] when deleted.
    @discardableResult
    public mutating func deletePage(_ name: String) -> [PageReference] {
        let blocking = references(to: name)
        guard blocking.isEmpty else { return blocking }
        pages.removeAll { $0.name == name }
        return []
    }

    private func checkedName(_ name: String, replacing old: String?) throws(PageNameError) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .empty }
        guard name != "back" else { throw .reserved }
        guard name == old || page(named: name) == nil else { throw .taken(name) }
        return name
    }
}
