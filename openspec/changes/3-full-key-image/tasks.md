# Tasks

Issue #3 has no checklist items, so nothing here duplicates it.

## 1. Config model

- [x] 1.1 Extract `resolvePath(_:relativeTo:)` (`~` expansion, relative to the config directory) from `Icon(configValue:relativeTo:)` and use it there; verify the existing `IconTests` still pass and add a test for `resolvePath` with `~/x.png`, `/abs.png` and `art/x.png`
- [x] 1.2 Add `KeyDefinition.image: String?` (resolved absolute path). In `ConfigLoader.parseKey`, allow the `image` field, resolve it with `resolvePath`, and reject values starting with `sf:` with a `ConfigError` that carries page and key; verify with `ConfigLoaderTests` for the "Relative image path" and "Symbol as image" scenarios in `specs/deck-config/spec.md`, and that an unknown field still fails
- [x] 1.3 Add `KeyDocument.image: String?`: read it in `ConfigDocumentYAML`, write it after `icon` in the canonical writer; verify with the exact-output writer test extended by an `image` key, and the round-trip test with a document that has an image
- [x] 1.4 Add `image` to the full example and the key fields table in `docs/config.md`, with the recommended size (square, at least 72x72 px) and a note that the icon box is 48x48 (44x40 with a label); verify `ConfigDocTests` passes with the updated example

## 2. Rendering

- [x] 2.1 Add `KeyAppearance.image: String?` and draw it in `renderUpright` after the background with a new `aspectFill` helper, clipped to the key; verify with `KeyRendererTests`: a solid-color 144x144 image covers every corner pixel, and a 200x100 image with a left half red and right half blue shows both colors and no black border
- [x] 2.2 Draw the label with a drop shadow only when an image was drawn; verify with a `KeyRendererTests` test that a pixel just below a label glyph is darker with an image than the same pixel on a no-image key over a white image area, and that a no-image key renders byte-identical to before (compare against the current output for a label-only key)
- [x] 2.3 On a missing or unreadable image, skip the layer and add `image file not found or unreadable: <path>` to the problems; verify with a `KeyRendererTests` test for the "Missing image file" scenario in `specs/key-rendering/spec.md` (label drawn, problem reported, no placeholder)

## 3. Engine and dynamic output

- [x] 3.1 Add `ImageOverride { path(String), remove }` and `DynamicOutput.image: ImageOverride?`; parse `image` in `DynamicOutput.parse` (string required, `""` means remove, paths through `resolvePath`); verify with `DynamicOutputTests` for "Script sets image", "Script removes image", "Image not a string" and "Relative path in dynamic output"
- [x] 3.2 Merge the image in `DeckEngine.render(key:)` (`.path` → that path, `.remove` → nil, unset → `definition.image`) and route image problems through the existing `.icon(key:)` problem; verify with `DynamicKeyTests`: JSON image replaces the configured one, `""` removes it, an omitted `image` keeps the configured one, and a missing image file shows up in `problems`
- [x] 3.3 Document the `image` JSON field in the "Dynamic keys → Output" table of `docs/config.md`, including `""` to remove; verify the table matches the "Dynamic key JSON output" requirement

## 4. Editor

- [x] 4.1 Add an Image row to `KeyInspector` below Icon: text field, Choose… via `choosePath(types: [.png, .jpeg], …)`, and a remove button; update the dynamic hint text to list `image`; verify manually against "Pick a full-key image" and "Remove a full-key image" in `specs/config-editor/spec.md`, checking the grid and the device

## 5. Integration check

- [ ] 5.1 Build with `scripts/bundle.sh`, configure a key with a photo `image` plus `icon` and `label`, a key with a missing image, and a dynamic key that alternates between `{"image":"art/a.png"}` and `{"image":""}`; verify on the device that the photo fills the key edge to edge with a shadowed label, the missing image is listed in the menu, the dynamic key toggles, and `swift test` passes

## Workflow follow-up

- Archive `streamdeck-menubar-controller`, `2-dynamic-key-json` and `1-config-editor` before archiving this change, so the `deck-config`, `key-rendering` and `config-editor` main specs exist for the MODIFIED deltas.
- Close issue #3 after archive.
