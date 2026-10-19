import Foundation

/// SF Symbol names, categories and search keywords, read from the plists macOS ships in
/// CoreGlyphs.bundle. There is no public API for this list; see design D10.
struct SymbolCatalog: Sendable {
    struct Category: Hashable, Sendable {
        let key: String
        let icon: String
        let title: String
    }

    static let systemDirectory = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")

    /// Loaded once on first use.
    static let system: SymbolCatalog? = try? SymbolCatalog(directory: systemDirectory)

    /// Suffixes of localized variants, e.g. `character.book.closed.ja`.
    static let localizedSuffixes: Set<String> = [
        "ar", "bn", "el", "gu", "he", "hi", "ja", "km", "kn", "ko", "ml", "mni", "mr", "my",
        "or", "pa", "rtl", "ru", "sat", "si", "ta", "te", "th", "zh",
    ]

    /// In the order the SF Symbols app shows them.
    let names: [String]
    /// Without the "all" pseudo-category.
    let categories: [Category]
    private let categoriesByName: [String: [String]]
    private let keywordsByName: [String: [String]]
    /// Old name to current name, e.g. `mic.slash.fill` to `microphone.slash.fill`.
    private let aliases: [String: String]

    init(directory: URL) throws {
        func plist<T>(_ file: String, as type: T.Type) throws -> T {
            let data = try Data(contentsOf: directory.appendingPathComponent(file))
            guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? T else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            return value
        }
        let order = try plist("symbol_order.plist", as: [String].self)
        names = order.filter { name in
            guard let suffix = name.split(separator: ".").last, name.contains(".") else { return true }
            return !Self.localizedSuffixes.contains(String(suffix))
        }
        let categoryList = (try? plist("categories.plist", as: [[String: String]].self)) ?? []
        categories = categoryList.compactMap { entry in
            guard let key = entry["key"], key != "all" else { return nil }
            return Category(key: key, icon: entry["icon"] ?? "square", title: Self.titles[key] ?? key.capitalized)
        }
        categoriesByName = (try? plist("symbol_categories.plist", as: [String: [String]].self)) ?? [:]
        aliases = (try? plist("name_aliases.strings", as: [String: String].self)) ?? [:]
        // Old names stay searchable, so `mic` still finds symbols renamed to `microphone`.
        var keywords = (try? plist("symbol_search.plist", as: [String: [String]].self)) ?? [:]
        for (old, current) in aliases { keywords[current, default: []].append(old) }
        keywordsByName = keywords
    }

    /// The current name for a symbol that may be written with an old name.
    func currentName(_ name: String) -> String {
        aliases[name] ?? name
    }

    /// Names in `category` (nil for all) where every word of `query` is in the name or a keyword.
    func symbols(matching query: String, category: String? = nil) -> [String] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return names.filter { name in
            if let category, !(categoriesByName[name] ?? []).contains(category) { return false }
            return words.allSatisfy { word in
                name.contains(word) || (keywordsByName[name] ?? []).contains { $0.lowercased().contains(word) }
            }
        }
    }

    private static let titles: [String: String] = [
        "whatsnew": "What's New", "draw": "Draw", "variable": "Variable", "multicolor": "Multicolor",
        "communication": "Communication", "weather": "Weather", "maps": "Maps", "objectsandtools": "Objects & Tools",
        "devices": "Devices", "cameraandphotos": "Camera & Photos", "gaming": "Gaming", "connectivity": "Connectivity",
        "transportation": "Transportation", "automotive": "Automotive", "accessibility": "Accessibility",
        "privacyandsecurity": "Privacy & Security", "human": "Human", "home": "Home", "fitness": "Fitness",
        "nature": "Nature", "editing": "Editing", "textformatting": "Text Formatting", "media": "Media",
        "keyboard": "Keyboard", "commerce": "Commerce", "time": "Time", "health": "Health", "shapes": "Shapes",
        "arrows": "Arrows", "indices": "Indices", "math": "Math",
    ]
}
