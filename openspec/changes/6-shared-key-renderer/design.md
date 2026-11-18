# Design

## Context

See proposal.md (Why). Where things stand after #5:

- `DeckEngine` owns the rendering port: `KeyAppearance`, `RenderedKey` and `protocol KeyRendering` in `Sources/DeckEngine/Rendering.swift`. The engine doesn't change in this change.
- `Sources/DeckRender/KeyRenderer.swift` is Mac-only: CoreGraphics drawing, CoreText labels, `NSImage(systemSymbolName:)` for `sf:` icons, and ImageIO for PNG/JPEG decoding and JPEG encoding. `AppKitKeyRenderer` wraps it for the engine, and `EditorView` calls `KeyRenderer.preview` for the grid.
- Current geometry, all at 1x on a 72x72 key: icon box 48x48 inset 12 (no label), or x 14…58, 2 px above a 24 px label strip (with label). Labels are 14→9 pt semibold, at most two lines, then truncated with an ellipsis. Over an image, the label gets a shadow: offset 1 px, blur 3, black at 0.8. Error dot: 10 px red circle, 3 px from the top-right corner. Pressed: black at 0.4 over the key. Placeholder: dashed grey square with a "?". Output is JPEG quality 0.9, rotated 180°.
- `Icon` in `DeckConfig` is `.symbol(String)` (SF) or `.file(String)`. `ConfigLoader` and `DynamicOutput` both parse through `Icon(configValue:relativeTo:)`.
- `bundle.sh` copies only the executable into the `.app`. #7 plans a fully static musl binary installed into the home directory.
- This Linux machine has Docker and no Swift. Linux tests run through `scripts/test-linux.sh`. Mac-side work gets verified on a Mac, as in #5.

## Goals / Non-Goals

**Goals:**
- One `DeckRender` target that builds and tests on both platforms and has no system library dependencies beyond the C standard library.
- The binary carries everything it needs to draw keys. Nothing is loaded from disk except the user's own image files.
- Today's geometry and behaviour are kept (see Context), so existing configs look the same apart from the font.

**Non-Goals:**
- A browsing picker for Material Symbols in the macOS editor. You type the name, as with a file path. The web editor (#9) can add browsing.
- Complex text shaping: kerning from GPOS, ligatures, right-to-left text, Indic scripts, color emoji. Characters without a glyph draw the font's fallback box.
- Rounded or Sharp Material Symbols styles, weights other than 400, or grade/optical-size variants.
- Changing the starter config. It keeps its `sf:` icons and macOS paths. #7 decides what the Linux starter config looks like.
- Caching rendered keys or decoded images. Today's renderer doesn't cache either, and 15 keys per page is cheap.

## Decisions

### D1. Targets: a vendored C target plus a portable `DeckRender`

- New C target `CStb`: `stb_truetype.h`, `stb_image.h` and `stb_image_write.h` at pinned upstream commits, plus one `stb.c` that defines the `*_IMPLEMENTATION` macros. stb_image is limited to PNG and JPEG (`STBI_ONLY_PNG`, `STBI_ONLY_JPEG`) and doesn't use stdio (`STBI_NO_STDIO`). Swift reads files into `Data` and calls the `*_from_memory` functions, so file errors stay in Swift.
- `DeckRender` moves out of the `#if os(macOS)` block and depends on `CStb`, `DeckConfig` and `DeckEngine`. It imports only Foundation and `CStb`. `DeckRenderTests` moves out of the block as well.
- `DeckPlatformMac` adds a dependency on `DeckRender` for the SF Symbol hook (D7).

*Alternatives:* a Swift package that wraps FreeType/libpng (needs system libraries or a static build of each; the issue rules that out), or a pure-Swift TrueType rasterizer (much more code for no gain over stb).

### D2. Fonts are compiled into the binary with `#embed`

The font files live in `Sources/CStb/fonts/` with their license files. A C file includes their bytes with C23 `#embed` and exposes them as `const unsigned char[]` with lengths. Swift wraps the bytes in `UnsafeRawBufferPointer`s without copying them.

That makes it impossible to ship a binary whose fonts are missing. It needs no change to `bundle.sh` or the static Linux install, and it avoids `Bundle.module`, whose lookup paths don't fit a hand-assembled `.app` or a single static binary.

*Fallback:* if a Swift toolchain we use ships a clang without `#embed`, `scripts/embed-fonts.sh` generates the same C file as a byte array (`xxd -i`), and that file gets committed. The first task checks `#embed` on both toolchains.

*Alternatives:* SwiftPM resources and `Bundle.module` (fails at runtime when the resource bundle isn't copied), or a Swift `[UInt8]` literal (very slow to type-check at MB sizes).

### D3. Text font: Inter SemiBold

Inter (OFL-1.1), static SemiBold instance, pinned release. It's the closest freely licensed match for SF Pro's metrics and look at 9–14 px, so labels wrap at about the same points as today. It covers Latin, Greek and Cyrillic.

stb_truetype only reads the legacy `kern` table, and Inter keeps its kerning in GPOS, so labels aren't kerned. That's part of the accepted visual change on macOS.

*Alternatives:* Roboto (narrower, looks less like today's labels), or Noto Sans (wider coverage, but much larger, and coverage is a non-goal).

### D4. Material Symbols: two static instances, looked up through the codepoints file

Material Symbols ships as one variable font, and its icons are named through GSUB ligatures. stb_truetype supports neither axis variation nor GSUB. So:

- `scripts/make-material-fonts.sh` runs fontTools in a throwaway Docker container. It instantiates the pinned upstream `MaterialSymbolsOutlined[FILL,GRAD,opsz,wght].ttf` at `wght=400, GRAD=0, opsz=48` with `FILL=0` and `FILL=1`. Then it subsets both to the codepoints in the matching `.codepoints` file and drops the layout tables. The two TTFs and the `.codepoints` file are committed and embedded. `opsz=48` is the design size closest to a 48 px icon box.
- `MaterialSymbols.codepoint(for:)` parses the embedded `.codepoints` file (`name hex` per line) into a dictionary on first use. `MaterialSymbols.contains(_:)` is public, for the editor.
- The glyph is drawn white with its em square scaled to the icon box's shorter side and centered on the box. Centering uses the em square, not the ink bounds, so all icons keep the same optical size, as the font intends.

*Alternatives:* ship the variable font and apply `gvar` deltas ourselves (a lot of code), or implement GSUB ligature lookup (also a lot of code, and the codepoints file already maps every name).

### D5. `Icon` gains a Material Symbol case

`Icon.material(name: String, filled: Bool)`. `Icon(configValue:)` maps `ms:<name>.fill` to `filled: true` and `ms:<name>` to `filled: false`. Material names only use `[a-z0-9_]`, so `.fill` can't clash with a name. `ConfigLoader` rejects `ms:` in `image` the same way it rejects `sf:`. Names aren't checked at load time, which keeps `DeckConfig` free of font data. An unknown name is a render problem, like an unknown SF Symbol today.

### D6. A small raster core in Swift

`DeckRender` gets an internal `Canvas`: a 72x72 premultiplied RGBA buffer of `Float` with a top-left origin. All of today's geometry is converted from CoreGraphics' bottom-left origin. Operations:

- `fill(rect, color)` and `fillEllipse(rect, color)`, antialiased with 4x4 supersampling at the edges.
- `draw(image, in: rect)` with clipping to the key. Bilinear sampling when scaling up. When scaling down, it averages over the source area, so large album art doesn't alias.
- `blend(mask, color, at:)` for glyph coverage masks from stb_truetype.
- `strokeDashedRect` for the placeholder.
- Shadow: the label's masks go into a separate coverage layer. That layer is blurred with three box-blur passes (approximating CG's blur 3), shifted 1 px down, and composited as black at 0.8 before the text.
- Output: converts to 8-bit RGB. `flipped()` reverses the pixel order (a 180° rotation). Encoding uses `stbi_write_jpg_to_func` at quality 90.

`Float` keeps alpha compositing simple and accurate, and a 72x72 key costs nothing at that size.

### D7. Labels: today's algorithm on stb_truetype

`LabelLayout` keeps today's rules. Sizes go from 14 to 9 px. At each size, text wraps greedily at whitespace, and a word wider than the line breaks between characters. A size fits when it gives at most two lines that fit the area's height and width. At 9 px, if it still doesn't fit, the lines are truncated to the allowed count, and the last one ends in "…" when it overflows. Line height is ascent − descent + lineGap at that size. Lines are centered horizontally, and the block is centered vertically, as today.

Glyphs are placed at subpixel x positions (`stbtt_MakeCodepointBitmapSubpixel`), one Unicode scalar at a time. A scalar the font doesn't have maps to glyph 0, Inter's fallback box, which gives the fallback mark the spec asks for. Layout is a pure function from text and area to lines and positions, so it's tested on its own.

### D8. `sf:` through an optional platform hook

```swift
public protocol SFSymbolSource: Sendable {
    /// White symbol rasterized for a box of `pointSize`, or nil if the name is unknown.
    func image(named: String, pointSize: Double) -> RGBAImage?
}
public struct KeyRenderer: KeyRendering {
    public init(sfSymbols: (any SFSymbolSource)? = nil)
    public func render(_ appearance: KeyAppearance) -> RenderedKey
    public func preview(_ appearance: KeyAppearance) -> RGBAImage   // upright, for the editor
}
```

`DeckPlatformMac` adds `AppKitSFSymbolSource`. It moves today's `NSImage(systemSymbolName:)` code there, draws into a bitmap context, and returns the pixels. `AppDelegate` passes it, and so does the editor. The renderer draws the returned image with the existing aspect-fit rule. Two different problems are reported:

- nil source (Linux): `SF Symbols are only available on macOS: sf:<name>. Use an ms: icon instead.`
- unknown name (macOS): `unknown SF Symbol: <name>`, as today.

`KeyRenderer` and `AppKitKeyRenderer` stop being separate types. The static enum goes away, and the tests call an instance.

### D9. Editor previews

`EditorView` keeps one `KeyRenderer(sfSymbols: AppKitSFSymbolSource())` and turns `preview(_:)`'s `RGBAImage` into a `CGImage` with a small helper in `StreamDeckApp`, through `CGDataProvider` and `CGImage(width:height:…)`. Previews and the device then come from the same pixels, before JPEG encoding.

`KeyInspector`'s icon kind picker gets a fourth case, **Material Symbol**. It has a name field, a **Filled** toggle, and the same unknown-name marker the SF field uses, backed by `MaterialSymbols.contains`. The stored string is `ms:<name>` or `ms:<name>.fill`.

## Risks / Trade-offs

- [Keys look different on macOS: font, no kerning, different antialiasing] → Accepted in the issue. The geometry is unchanged. Compare a screenshot of the editor grid before and after, on the Mac verification step.
- [Binary size grows by the fonts (Inter about 300 KB, each Material instance about 1–2 MB after subsetting)] → Measure in the font task, and record the sizes in the PR. If the fonts are too large, subsetting the codepoints further is a follow-up that needs no API change.
- [Toolchain without `#embed`] → Fallback in D2, checked first.
- [stb_image decodes the user's own image files, and stb has had CVEs with malformed inputs] → Inputs are files the user configured on their own machine. Pin a recent upstream commit and allow only PNG and JPEG.
- [Inter's fallback box looks different from CoreText's font fallback, which drew real emoji] → In the spec ("Label characters outside the font"), and documented in `docs/config.md`.
- [Material Symbols upstream renames or drops icons between releases] → Pinned release, regenerated only on purpose with the script.
- [The SF Symbol hook rasterizes off the main thread] → It does that today through `NSImage`. No change in threading.
- [The Mac side can't be built on this machine] → As in #5, the last task is a Mac build, a full `swift test` and a smoke test, recorded in the PR.

## Migration Plan

No config migration. Existing `sf:` configs render as before on macOS, apart from the visual change. Rollback is a revert.
