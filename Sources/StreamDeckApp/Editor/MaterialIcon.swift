/// A Material Symbol icon as the inspector edits it: `ms:<name>` or `ms:<name>.fill`.
struct MaterialIcon: Equatable {
    var name: String
    var filled: Bool

    init(name: String, filled: Bool) {
        self.name = name
        self.filled = filled
    }

    /// Nil unless the text starts with `ms:`.
    init?(configValue text: String) {
        guard text.hasPrefix("ms:") else { return nil }
        let rest = text.dropFirst(3)
        filled = rest.hasSuffix(".fill")
        name = String(filled ? rest.dropLast(5) : rest)
    }

    var configValue: String {
        "ms:" + name + (filled ? ".fill" : "")
    }
}
