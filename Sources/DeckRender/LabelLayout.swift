/// Where the glyphs of a label go: the largest size from 14 down to 9 px at which the text fits in
/// at most two lines, wrapping at spaces and between characters of words too long for a line.
/// At 9 px, text that still doesn't fit is truncated with an ellipsis.
struct LabelLayout {
    static let maxSize = 14.0
    static let minSize = 9.0

    struct Glyph: Equatable {
        let glyph: Int32
        /// Pen position from the start of the line, in pixels.
        let x: Double
    }

    struct Line: Equatable {
        let text: String
        let glyphs: [Glyph]
        /// Without trailing whitespace.
        let width: Double
    }

    let font: Font
    let size: Double
    let lines: [Line]
    /// Pixels between baselines.
    let lineHeight: Double
    /// Pixels from the top of a line to its baseline.
    let ascent: Double

    var scale: Double { font.scale(forSize: size) }

    init(_ text: String, width: Double, height: Double, font: Font = .inter) {
        self.font = font
        let characters = Array(text.map { $0 == "\t" ? " " : $0 })
        var size = Self.maxSize
        while true {
            let scale = font.scale(forSize: size)
            let lineHeight = (font.ascent - font.descent + font.lineGap) * scale
            var lines = Self.wrap(characters, width: width, font: font, scale: scale)
            let fits = lines.count <= 2 && lineHeight * Double(lines.count) <= height + 0.001
                && lines.allSatisfy { Self.shape($0, font: font, scale: scale).width <= width }
            if !fits && size <= Self.minSize {
                let maxLines = max(1, min(2, Int(height / max(lineHeight, 1))))
                lines = Self.truncate(lines, maxLines: maxLines, width: width, font: font, scale: scale)
            }
            if fits || size <= Self.minSize {
                self.size = size
                self.lineHeight = lineHeight
                self.ascent = font.ascent * scale
                self.lines = lines.map { Self.shape($0, font: font, scale: scale) }
                return
            }
            size -= 1
        }
    }

    /// Glyphs and pen positions for one line.
    static func shape(_ characters: [Character], font: Font, scale: Double) -> Line {
        var glyphs: [Glyph] = []
        var pen = 0.0, width = 0.0
        var previous: Int32?
        for character in characters {
            for scalar in character.unicodeScalars {
                let glyph = font.glyph(for: scalar)
                if let previous { pen += font.kerning(previous, glyph) * scale }
                glyphs.append(Glyph(glyph: glyph, x: pen))
                pen += font.advance(glyph) * scale
                previous = glyph
            }
            if !character.isWhitespace { width = pen }
        }
        return Line(text: String(characters), glyphs: glyphs, width: width)
    }

    /// Greedy wrap: whole words where they fit, characters where a word alone is too wide.
    /// A newline always breaks the line.
    static func wrap(_ characters: [Character], width: Double, font: Font, scale: Double) -> [[Character]] {
        func fits(_ line: [Character]) -> Bool { shape(line, font: font, scale: scale).width <= width }

        var lines: [[Character]] = []
        var current: [Character] = []
        for (index, paragraph) in characters.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index > 0 {
                lines.append(current)
                current = []
            }
            for word in words(Array(paragraph)) {
                if fits(current + word) {
                    current += word
                    continue
                }
                if !current.isEmpty {
                    lines.append(current)
                    current = []
                }
                if fits(word) {
                    current = word
                    continue
                }
                for character in word {
                    if current.isEmpty || fits(current + [character]) {
                        current.append(character)
                    } else {
                        lines.append(current)
                        current = [character]
                    }
                }
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// Splits text into words, each with the spaces that follow it.
    private static func words(_ characters: [Character]) -> [[Character]] {
        var words: [[Character]] = []
        var current: [Character] = []
        for character in characters {
            if !character.isWhitespace, let last = current.last, last.isWhitespace {
                words.append(current)
                current = []
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// Keeps `maxLines - 1` lines and puts the rest on the last line, cut to end in an ellipsis if it overflows.
    static func truncate(_ lines: [[Character]], maxLines: Int, width: Double, font: Font, scale: Double) -> [[Character]] {
        var kept = Array(lines.prefix(maxLines - 1))
        var rest = Array(lines.dropFirst(maxLines - 1).joined())
        if shape(rest, font: font, scale: scale).width > width {
            while !rest.isEmpty {
                rest.removeLast()
                while let last = rest.last, last.isWhitespace { rest.removeLast() }
                if shape(rest + ["\u{2026}"], font: font, scale: scale).width <= width { break }
            }
            rest.append("\u{2026}")
        }
        kept.append(rest)
        return kept
    }
}
