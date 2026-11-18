import CStb

/// Material Symbols (Outlined, weight 400), compiled into the binary.
/// Names are looked up in the codepoints file that ships with the font.
public enum MaterialSymbols {
    /// Name to codepoint, parsed on first use.
    private static let codepoints: [String: Unicode.Scalar] = {
        var size = 0
        let bytes = UnsafeBufferPointer(start: deck_material_codepoints(&size), count: size)
        var result: [String: Unicode.Scalar] = [:]
        for line in String(decoding: bytes, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: " ")
            guard fields.count == 2, let value = UInt32(fields[1], radix: 16), let scalar = Unicode.Scalar(value) else { continue }
            result[String(fields[0])] = scalar
        }
        return result
    }()

    /// Whether `name` (such as `play_arrow`, without `ms:` or `.fill`) is a Material Symbol.
    public static func contains(_ name: String) -> Bool {
        codepoints[name] != nil
    }

    /// Adds the symbol's coverage to `mask`, its em square scaled to the shorter side of `box` and
    /// centered on it. Returns false for an unknown name.
    static func draw(_ name: String, filled: Bool, in box: Rect, into mask: inout Mask) -> Bool {
        guard let scalar = codepoints[name] else { return false }
        let font = filled ? Font.materialFilled : Font.materialOutlined
        let glyph = font.glyph(for: scalar)
        guard glyph != 0 else { return false }
        let side = min(box.width, box.height)
        let scale = font.scale(forSize: side)
        // The em square spans the advance horizontally and ascent to descent vertically.
        let emWidth = font.advance(glyph) * scale
        let emHeight = (font.ascent - font.descent) * scale
        let x = box.midX - emWidth / 2
        let baseline = box.midY - emHeight / 2 + font.ascent * scale
        font.draw(glyph, scale: scale, x: x, y: baseline, into: &mask)
        return true
    }
}
