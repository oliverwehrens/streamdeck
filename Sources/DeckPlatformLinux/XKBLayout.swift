import DeckConfig
import DeckEngine
import Foundation

/// XKB key names of the alphanumeric block and their evdev codes (XKB keycode − 8), from xkeyboard-config `keycodes/evdev`.
enum XKBKeycodes {
    static let evdev: [String: UInt16] = {
        var codes: [String: UInt16] = ["TLDE": 41, "BKSL": 43, "LSGT": 86, "AB11": 89, "AE13": 124]
        for index in 1 ... 12 { codes[String(format: "AE%02d", index)] = UInt16(1 + index) }    // 2...13
        for index in 1 ... 12 { codes[String(format: "AD%02d", index)] = UInt16(15 + index) }   // 16...27
        for index in 1 ... 12 { codes[String(format: "AC%02d", index)] = UInt16(29 + index) }   // 30...41 (AC12 = BKSL position)
        for index in 1 ... 10 { codes[String(format: "AB%02d", index)] = UInt16(43 + index) }   // 44...53
        codes["AC12"] = 43
        return codes
    }()
}

/// Level-1 keysyms of one XKB layout, as parsed from its symbols file.
public struct XKBSymbols: Equatable, Sendable {
    /// XKB key name (without `<>`) to level-1 keysym name.
    public var keys: [String: String] = [:]

    /// The `us` layout, built in so keystrokes work without `/usr/share/X11/xkb`.
    public static let us: XKBSymbols = {
        var keys: [String: String] = ["TLDE": "grave", "AE11": "minus", "AE12": "equal", "AD11": "bracketleft",
                                      "AD12": "bracketright", "BKSL": "backslash", "AC10": "semicolon",
                                      "AC11": "apostrophe", "AB08": "comma", "AB09": "period", "AB10": "slash"]
        for (index, digit) in "1234567890".enumerated() { keys[String(format: "AE%02d", index + 1)] = String(digit) }
        for (index, letter) in "qwertyuiop".enumerated() { keys[String(format: "AD%02d", index + 1)] = String(letter) }
        for (index, letter) in "asdfghjkl".enumerated() { keys[String(format: "AC%02d", index + 1)] = String(letter) }
        for (index, letter) in "zxcvbnm".enumerated() { keys[String(format: "AB%02d", index + 1)] = String(letter) }
        return XKBSymbols(keys: keys)
    }()

    /// The characters the config can name, by keysym name.
    static let characters: [String: Character] = {
        var names: [String: Character] = [
            "grave": "`", "minus": "-", "equal": "=", "bracketleft": "[", "bracketright": "]", "backslash": "\\",
            "semicolon": ";", "apostrophe": "'", "comma": ",", "period": ".", "slash": "/",
        ]
        for character in "abcdefghijklmnopqrstuvwxyz0123456789" { names[String(character)] = character }
        return names
    }()

    /// The character a keysym name types, if the config can name it. Handles `U0061` forms.
    static func character(forKeysym name: String) -> Character? {
        if let character = characters[name] { return character }
        if name.count == 1, let upper = name.first, upper.isUppercase, upper.isASCII {
            return nil  // `Q` on level 1 means a shifted letter; not a config character without modifiers.
        }
        if name.hasPrefix("U"), let scalar = UInt32(name.dropFirst(), radix: 16).flatMap(Unicode.Scalar.init) {
            let character = Character(scalar)
            return characters.values.contains(character) ? character : nil
        }
        return nil
    }

    /// Characters to evdev codes. Where several keys type a character, the first in key-name order wins.
    public var evdevCodes: [Character: UInt16] {
        var codes: [Character: UInt16] = [:]
        for name in keys.keys.sorted() {
            guard let code = XKBKeycodes.evdev[name], let keysym = keys[name],
                  let character = Self.character(forKeysym: keysym), codes[character] == nil else { continue }
            codes[character] = code
        }
        return codes
    }
}

/// Parses the subset of XKB symbols files that keyboard layouts use: `xkb_symbols` blocks, `include`, and `key`.
public struct XKBSymbolsParser: Sendable {
    public let symbolsDirectory: String
    static let maxIncludeDepth = 8

    public init(symbolsDirectory: String = "/usr/share/X11/xkb/symbols") {
        self.symbolsDirectory = symbolsDirectory
    }

    /// Symbols for `layout` and optional `variant`, or nil when the file or variant does not exist.
    public func symbols(layout: String, variant: String?) -> XKBSymbols? {
        var result = XKBSymbols()
        guard apply(file: layout, variant: variant, into: &result, depth: 0) else { return nil }
        return result
    }

    private func apply(file: String, variant: String?, into result: inout XKBSymbols, depth: Int) -> Bool {
        guard depth < Self.maxIncludeDepth, !file.contains("/"), !file.contains(".."),
              let text = try? String(contentsOfFile: "\(symbolsDirectory)/\(file)", encoding: .utf8),
              let body = Self.block(in: Self.stripComments(text), variant: variant)
        else { return false }
        for statement in Self.statements(body) {
            switch statement {
            case let .include(spec):
                for (includedFile, includedVariant) in Self.parseInclude(spec) {
                    // Missing includes (level3, keypad, ...) only add keys we don't use.
                    _ = apply(file: includedFile, variant: includedVariant, into: &result, depth: depth + 1)
                }
            case let .key(name, keysym):
                result.keys[name] = keysym
            }
        }
        return true
    }

    enum Statement: Equatable {
        case include(String)
        case key(name: String, keysym: String)
    }

    static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard let range = line.range(of: "//") else { return String(line) }
            return String(line[..<range.lowerBound])
        }.joined(separator: "\n")
    }

    /// The body of the named `xkb_symbols` block, or of the default one (marked `default`, else the first).
    static func block(in text: String, variant: String?) -> String? {
        let pattern = try! NSRegularExpression(pattern: #"((?:\w+\s+)*)xkb_symbols\s+"([^"]+)"\s*\{"#)
        let nsText = text as NSString
        var candidates: [(name: String, isDefault: Bool, bodyStart: Int)] = []
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let flags = nsText.substring(with: match.range(at: 1))
            let name = nsText.substring(with: match.range(at: 2))
            candidates.append((name, flags.split(whereSeparator: \.isWhitespace).contains("default"), match.range.upperBound))
        }
        let chosen: (name: String, isDefault: Bool, bodyStart: Int)?
        if let variant, !variant.isEmpty {
            chosen = candidates.first { $0.name == variant }
        } else {
            chosen = candidates.first { $0.isDefault } ?? candidates.first
        }
        guard let chosen else { return nil }
        // The block ends at the brace that balances its opening one.
        let utf16 = Array(nsText.substring(from: chosen.bodyStart).utf16)
        var depth = 1
        for (index, unit) in utf16.enumerated() {
            if unit == UInt16(UInt8(ascii: "{")) { depth += 1 }
            if unit == UInt16(UInt8(ascii: "}")) {
                depth -= 1
                if depth == 0 { return String(decoding: utf16[..<index], as: UTF16.self) }
            }
        }
        return nil
    }

    static func statements(_ body: String) -> [Statement] {
        let pattern = try! NSRegularExpression(
            pattern: #"include\s+"([^"]+)"|(?:(?:replace|override|augment)\s+)?key\s*<(\w+)>\s*\{([^}]*)\}"#)
        let nsBody = body as NSString
        return pattern.matches(in: body, range: NSRange(location: 0, length: nsBody.length)).compactMap { match in
            if match.range(at: 1).location != NSNotFound {
                return .include(nsBody.substring(with: match.range(at: 1)))
            }
            let name = nsBody.substring(with: match.range(at: 2))
            guard let keysym = levelOne(nsBody.substring(with: match.range(at: 3))) else { return nil }
            return .key(name: name, keysym: keysym)
        }
    }

    /// The first keysym of a key body: `[ q, Q ]`, `symbols[Group1]= [ q, Q ]`, or with `type[...]="..."` around it.
    static func levelOne(_ keyBody: String) -> String? {
        var text = keyBody
        if let range = text.range(of: #"symbols\s*\[\s*[Gg]roup1\s*\]\s*=\s*"#, options: .regularExpression) {
            text = String(text[range.upperBound...])
        } else {
            text = text.replacingOccurrences(of: #"actions\s*\[[^\]]*\]\s*=\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\w+\s*\[[^\]]*\]\s*=\s*"[^"]*""#, with: "", options: .regularExpression)
        }
        guard let open = text.firstIndex(of: "["), let close = text[open...].firstIndex(of: "]") else { return nil }
        let first = text[text.index(after: open) ..< close].split(separator: ",").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return first.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `latin(type4)`, `pc+us(basic)`, `us|inet(evdev)`: file and variant pairs in order.
    static func parseInclude(_ spec: String) -> [(String, String?)] {
        spec.split(whereSeparator: { $0 == "+" || $0 == "|" }).compactMap { part in
            let part = part.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { return nil }
            // A `:2` group suffix moves keys to another group; only group 1 matters.
            if part.contains(":") { return nil }
            if let open = part.firstIndex(of: "("), part.hasSuffix(")") {
                return (String(part[..<open]), String(part[part.index(after: open) ..< part.index(before: part.endIndex)]))
            }
            return (part, nil)
        }
    }
}

/// The keyboard layout for characters in combos on Linux, resolved on every call. Codes are evdev codes.
public struct XKBLayout: KeyboardLayout {
    public struct Selection: Equatable, Sendable {
        public var layout: String
        public var variant: String?

        public init(layout: String, variant: String? = nil) {
            self.layout = layout
            self.variant = variant
        }

        public var name: String { variant.map { "\(layout)(\($0))" } ?? layout }
    }

    private let parser: XKBSymbolsParser
    private let select: @Sendable () -> Selection
    private let cache = Cache()

    public init(parser: XKBSymbolsParser = XKBSymbolsParser(), select: @escaping @Sendable () -> Selection = { LayoutDetection().current() }) {
        self.parser = parser
        self.select = select
    }

    public var name: String { resolved().name }
    public func keyCode(typing character: Character) -> UInt16? { resolved().keyCode(typing: character) }
    public func character(forKeyCode code: UInt16) -> Character? { resolved().character(forKeyCode: code) }

    /// The active layout as a table, falling back to `us` when it is missing or types no Latin letters.
    public func resolved() -> TableKeyboardLayout {
        let selection = select()
        return cache.layout(for: selection) {
            let codes = parser.symbols(layout: selection.layout, variant: selection.variant)?.evdevCodes ?? [:]
            guard codes.keys.contains(where: { $0.isLetter }) else { return Self.us }
            return TableKeyboardLayout(name: selection.name, codes: codes)
        }
    }

    public static let us = TableKeyboardLayout(name: "us", codes: XKBSymbols.us.evdevCodes)

    final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var layouts: [String: TableKeyboardLayout] = [:]

        func layout(for selection: Selection, make: () -> TableKeyboardLayout) -> TableKeyboardLayout {
            lock.lock()
            defer { lock.unlock() }
            if let cached = layouts[selection.name] { return cached }
            let layout = make()
            layouts[selection.name] = layout
            return layout
        }
    }
}
