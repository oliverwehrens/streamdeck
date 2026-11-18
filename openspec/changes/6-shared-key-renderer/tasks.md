# Tasks

Issue #6 has no checklist items, so nothing here duplicates it.

## 1. Vendored C and embedded fonts

- [ ] 1.1 Add the `CStb` C target: `stb_truetype.h`, `stb_image.h` and `stb_image_write.h` at pinned upstream commits (recorded in a header comment and `Sources/CStb/README.md` with the license), and `stb.c` with the implementation macros, `STBI_ONLY_PNG`, `STBI_ONLY_JPEG` and `STBI_NO_STDIO`; verify `./scripts/test-linux.sh build --target CStb` succeeds
- [ ] 1.2 Add `scripts/make-material-fonts.sh` per design.md D4 (fontTools in a throwaway Docker container; pinned upstream variable font; `wght=400 GRAD=0 opsz=48`, `FILL=0` and `FILL=1`; subset to the `.codepoints` list; no layout tables). Run it and commit `MaterialSymbolsOutlined-400.ttf`, `MaterialSymbolsOutlined-400-Fill.ttf`, `MaterialSymbols.codepoints` and the Apache-2.0 license under `Sources/CStb/fonts/`, plus Inter SemiBold at a pinned release with its OFL license; verify that running the script twice gives byte-identical files, and record the font sizes in the PR
- [ ] 1.3 Embed the fonts with C23 `#embed` in `Sources/CStb/fonts.c` and expose them through `Sources/CStb/include/fonts.h` (`const unsigned char[]` plus lengths); if a toolchain rejects `#embed`, generate a byte-array `fonts.c` with `scripts/embed-fonts.sh` instead (design D2); verify `./scripts/test-linux.sh build --target CStb` succeeds, and `swift build --target CStb` succeeds on the Mac in 6.2

## 2. Material Symbol icons in the config

- [ ] 2.1 Add `Icon.material(name:filled:)` and parse `ms:<name>` and `ms:<name>.fill` in `Icon(configValue:relativeTo:)`; verify with `IconTests` cases for `ms:play_arrow`, `ms:lightbulb.fill` and `ms:` with an empty name (passed through, reported at render time) on Linux
- [ ] 2.2 Make `ConfigLoader` reject `ms:` in `image` with "Material Symbols belong in icon", like `sf:`; verify with a `ConfigLoaderTests` test that names the page and key
- [ ] 2.3 Verify dynamic JSON accepts `ms:` icons: add a `DynamicOutputTests` case for `{"icon":"ms:lightbulb.fill"}` giving `.material(name: "lightbulb", filled: true)`; `./scripts/test-linux.sh test --filter DeckConfigTests` and `--filter DynamicOutputTests` pass
- [ ] 2.4 Fix every `switch` over `Icon` that the new case breaks (the editor, `FakeRenderer`); verify `./scripts/test-linux.sh build` succeeds (the Mac targets are checked in 6.2)

## 3. Portable renderer

- [ ] 3.1 Move `DeckRender` and `DeckRenderTests` out of the `#if os(macOS)` block in `Package.swift` and depend on `CStb`; add `RGBAImage` (width, height, RGBA8 bytes) and the internal `Canvas` per design D6 (fill, antialiased ellipse, image draw with bilinear upscaling and area-average downscaling, mask blend, dashed rect, flip, JPEG quality 90 through `stbi_write_jpg_to_func`), plus PNG/JPEG decoding through `stbi_load_from_memory`; verify with `DeckRenderTests` on Linux: a solid fill reads back exactly, a flipped image has the top-left pixel at the bottom-right, a 144x144 checkerboard downscaled to 72x72 averages to mid grey, and the JPEG decodes back to 72x72
- [ ] 3.2 Add `LabelLayout` per design D7 on the embedded Inter (14→9 px, greedy wrap at whitespace, character breaks for long words, at most two lines, ellipsis truncation, glyph 0 for missing characters); port the label tests from the old `KeyRendererTests` (short label at 14 px, "Deploy production environment" in at most two lines ending in "…", very long text stays inside the width) and add one for `"Party 🎉"` (laid out, with glyph 0 for the emoji); verify on Linux
- [ ] 3.3 Add `MaterialSymbols` per design D4 (lazy codepoints dictionary, `contains`, glyph rasterization from the outlined or filled font, em square scaled to the box and centered); verify with tests that `contains("home")` is true and `contains("hoem")` is false, and that `ms:square` and `ms:square.fill` draw white pixels in the icon box, with more of them for the filled one
- [ ] 3.4 Rewrite `KeyRenderer` as the `KeyRendering` struct from design D8 with today's layers and geometry (background, aspect-filled image, icon box, label with shadow over images, error dot, pressed overlay, placeholder) and the problem messages for missing files, unknown Material Symbols and `sf:` without a source; delete `AppKitKeyRenderer` and the CoreGraphics code; port the remaining old `KeyRendererTests` (blank key, background color, flip, file icon aspect-fit, pressed darkens, missing icon placeholder and problem, full-key image fill and crop, missing image, label shadow over image) without CoreGraphics, CoreText or ImageIO, and add tests for an unknown `ms:` name and `sf:play.fill` with no source (placeholder and the macOS-only message); verify `./scripts/test-linux.sh test --filter DeckRenderTests` passes and `grep -rE "import (AppKit|CoreGraphics|CoreText|ImageIO)" Sources/DeckRender Tests/DeckRenderTests` finds nothing

## 4. macOS hook and app wiring

- [ ] 4.1 Add `AppKitSFSymbolSource` to `DeckPlatformMac` (depends on `DeckRender`): today's `NSImage(systemSymbolName:)` code, white palette, drawn into a bitmap context and returned as `RGBAImage`; move the SF Symbol test there (`square.fill` draws white pixels, an unknown name returns nil, and the renderer reports `unknown SF Symbol`); verify in 6.2
- [ ] 4.2 `AppDelegate` passes `KeyRenderer(sfSymbols: AppKitSFSymbolSource())`; `EditorView` uses one shared renderer instance and converts `preview(_:)` to `CGImage` through a small helper in `StreamDeckApp`; verify in 6.2 with an `EditorModelTests` or helper test that the converted image is 72x72 and its top-left pixel matches the `RGBAImage`
- [ ] 4.3 Add the **Material Symbol** kind to `KeyInspector`'s icon editor per design D9 (name field, Filled toggle, unknown-name marker through `MaterialSymbols.contains`, stores `ms:<name>` or `ms:<name>.fill`, and recognizes both when an existing key is selected); verify on the Mac in 6.3 with the spec's "Enter a Material Symbol" and "Unknown Material Symbol name" scenarios

## 5. Documentation

- [ ] 5.1 Update `docs/config.md`: document `ms:<name>` and `ms:<name>.fill` in the `icon` row, the dynamic `icon` row and the examples (with a link to the Material Symbols catalog and a note that names use underscores), recommend `ms:` for configs shared between macOS and Linux, say that `sf:` works only on macOS, and note that label characters outside the bundled font show a box; verify every `sf:` mention in the file has been checked and the examples still load (paste them into a `ConfigLoaderTests` fixture or run them through the loader)
- [ ] 5.2 Update the README: the project layout table (`Sources/CStb`, `DeckRender` now portable), the license section with Inter (OFL) and Material Symbols (Apache-2.0), and one `ms:` example next to the `sf:` ones; verify every directory under `Sources/` has a row

## 6. Integration

- [ ] 6.1 Run the whole suite on Linux; verify `./scripts/test-linux.sh` passes with no warnings from `DeckRender` or `CStb` in Swift 6 language mode
- [ ] 6.2 On a Mac: `./scripts/bundle.sh` and the full `swift test`; verify both pass and record the result and the app binary size before and after in the PR
- [ ] 6.3 On a Mac: smoke test of the installed app with a config that mixes `sf:`, `ms:`, `ms:….fill`, a file icon, a full-key image with a label, a long label and a dynamic key; verify the deck and the editor grid match, a screenshot of the editor before and after is attached to the PR, and the editor's Material Symbol field behaves as specified

## Workflow follow-up

- Archive the change after review and close #6.
