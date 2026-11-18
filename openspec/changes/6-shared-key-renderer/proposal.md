Issue: #6

# Proposal

## Why

The deck's key images come from `DeckRender`, which uses AppKit, CoreText and ImageIO, so it only exists on macOS. The Linux daemon (#7) and the web editor previews (#9) need the same images. Keys should look the same on both platforms, and a config that names icons should work on both. Today's only built-in icon form, `sf:`, is SF Symbols. Apple doesn't license those for use off Apple platforms, and Linux has no way to draw them.

## What Changes

- `DeckRender` becomes one portable renderer used on macOS and Linux. It's written in pure Swift plus vendored C (stb_truetype, stb_image, stb_image_write), with no system libraries, so it works in a fully static Linux build. It replaces `AppKitKeyRenderer` as the engine's `KeyRendering` and draws the config editor's previews.
- The renderer bundles a text font for labels and the Material Symbols font (Apache-2.0), outlined and filled, both built into the binary.
- New icon form `ms:<name>` for a Material Symbol, for example `ms:play_arrow`. `ms:<name>.fill` draws the filled style. It works on both platforms and in dynamic key JSON output.
- `sf:<name>` keeps working on macOS through a small platform hook that rasterizes the symbol with AppKit. On Linux, an `sf:` icon draws the missing-icon placeholder and is reported as a problem. It doesn't make the config fail to load.
- Today's behaviour stays: icon box sizes, label shrink/wrap/truncate, full-key `image` with aspect-fill, label shadow over images, pressed darkening, error dot, missing-icon placeholder, and a 72x72 JPEG rotated 180° for the device.
- Keys look slightly different on macOS: a different label font, and different antialiasing and kerning.
- The config editor's icon field offers Material Symbols next to SF Symbols and images. You type the name, and the editor marks unknown names.
- `docs/config.md` documents `ms:` and recommends it for configs shared between machines.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `key-rendering`: static appearance and the missing-icon placeholder cover `ms:` icons, and `sf:` icons on Linux. Dynamic JSON `icon` values accept `ms:`. Keys render the same way on macOS and Linux.
- `deck-config`: `icon` accepts `ms:<name>` and `ms:<name>.fill`.
- `config-editor`: the inspector edits Material Symbol icons.

## Impact

- Code: `Sources/DeckRender/KeyRenderer.swift` is rewritten. New C target with the vendored stb headers. `Icon` in `Sources/DeckConfig/Model.swift` gains a Material Symbol case. A new SF Symbol hook goes in `DeckPlatformMac`. `AppDelegate` and `EditorView` switch to the new renderer, and the editor's `KeyInspector` gains a Material Symbols option.
- Build: `DeckRender` and `DeckRenderTests` move out of the macOS-only part of `Package.swift`. The binary grows by the size of the embedded fonts, a few MB.
- Tests: `KeyRendererTests` are rewritten without CoreGraphics and CoreText so they run on Linux too. New tests cover `ms:` parsing, rendering, and `sf:` on Linux.
- Dependencies: vendored public-domain/MIT stb headers, the bundled text font (OFL) and Material Symbols (Apache-2.0), with their licenses in the repo. No new Swift packages.
