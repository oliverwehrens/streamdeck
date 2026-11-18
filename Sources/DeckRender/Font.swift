import CStb

/// A TrueType font compiled into the binary, read through stb_truetype.
///
/// The font bytes are static data, and stb_truetype only reads `info` after `init`,
/// so one instance is shared between threads.
final class Font: @unchecked Sendable {
    private let info: UnsafeMutablePointer<stbtt_fontinfo>
    let unitsPerEm: Double
    /// Ascent above the baseline, descent below it (negative) and gap between lines, in font units.
    let ascent: Double
    let descent: Double
    let lineGap: Double

    /// `bytes` must stay valid for the life of the process.
    init(bytes: UnsafePointer<UInt8>) {
        info = .allocate(capacity: 1)
        guard stbtt_InitFont(info, bytes, stbtt_GetFontOffsetForIndex(bytes, 0)) != 0 else {
            fatalError("embedded font is not a valid TrueType font")
        }
        var ascent: Int32 = 0, descent: Int32 = 0, lineGap: Int32 = 0
        stbtt_GetFontVMetrics(info, &ascent, &descent, &lineGap)
        self.ascent = Double(ascent)
        self.descent = Double(descent)
        self.lineGap = Double(lineGap)
        // stbtt has no direct accessor; this scale maps one em to 1 px.
        unitsPerEm = 1 / Double(stbtt_ScaleForMappingEmToPixels(info, 1))
    }

    deinit {
        info.deallocate()
    }

    static let inter: Font = {
        var size = 0
        return Font(bytes: deck_font_inter_semibold(&size))
    }()

    static let materialOutlined: Font = {
        var size = 0
        return Font(bytes: deck_font_material_outlined(&size))
    }()

    static let materialFilled: Font = {
        var size = 0
        return Font(bytes: deck_font_material_filled(&size))
    }()

    /// The scale from font units to pixels for a font size of `size` px per em.
    func scale(forSize size: Double) -> Double {
        size / unitsPerEm
    }

    /// The glyph for a character; 0 (the font's fallback glyph) when the font doesn't have it.
    func glyph(for scalar: Unicode.Scalar) -> Int32 {
        stbtt_FindGlyphIndex(info, Int32(scalar.value))
    }

    /// Advance width in font units.
    func advance(_ glyph: Int32) -> Double {
        var advance: Int32 = 0, bearing: Int32 = 0
        stbtt_GetGlyphHMetrics(info, glyph, &advance, &bearing)
        return Double(advance)
    }

    /// Kerning between two glyphs in font units, from the legacy `kern` table if the font has one.
    func kerning(_ left: Int32, _ right: Int32) -> Double {
        Double(stbtt_GetGlyphKernAdvance(info, left, right))
    }

    /// Rasterizes a glyph whose origin (on the baseline) is at (x, y) in pixels, adding it to `mask`.
    func draw(_ glyph: Int32, scale: Double, x: Double, y: Double, into mask: inout Mask, opacity: Float = 1) {
        let originX = x.rounded(.down), originY = y.rounded(.down)
        let shiftX = Float(x - originX), shiftY = Float(y - originY)
        var x0: Int32 = 0, y0: Int32 = 0, x1: Int32 = 0, y1: Int32 = 0
        stbtt_GetGlyphBitmapBoxSubpixel(info, glyph, Float(scale), Float(scale), shiftX, shiftY, &x0, &y0, &x1, &y1)
        let width = Int(x1 - x0), height = Int(y1 - y0)
        guard width > 0, height > 0 else { return }
        let bitmap = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        defer { bitmap.deallocate() }
        stbtt_MakeGlyphBitmapSubpixel(info, bitmap, Int32(width), Int32(height), Int32(width),
                                      Float(scale), Float(scale), shiftX, shiftY, glyph)
        mask.add(bitmap, width: width, height: height, left: Int(originX) + Int(x0), top: Int(originY) + Int(y0), scale: opacity)
    }
}
