Issue: #3

# Proposal

## Why

An icon can't fill a key. The renderer fits every icon into a 48x48 box inside the 72x72 key, or 44x40 above a label. Custom artwork such as photos, album art or pre-rendered button tiles comes out small with a black border.

## What Changes

- A key definition gains an optional `image` field: a PNG or JPEG path, drawn edge to edge across the whole key.
- The image fills the key and keeps its aspect ratio: it is scaled to cover 72x72 and cropped at the center. It is drawn over `background` and under `icon` and `label`, which stay where they are today.
- When a key has an image, its label gets a drop shadow so it stays readable on bright images. Keys without an image look as before.
- `image` takes paths only. `~` expands, and relative paths resolve against the config directory, as for `icon`. A value starting with `sf:` is a config error, because SF Symbols belong in `icon`.
- A missing or unreadable image file draws the key without the image (background, icon, label) and reports the file in the menu, like a missing icon.
- Dynamic key JSON output gains an `image` field with the same path rules. `""` removes the image for that run.
- The config editor's key inspector gets an Image field with a file picker that stores paths relative to the config directory. The YAML reader and writer keep the field.
- `docs/config.md` documents `image`, the dynamic `image` field, and the recommended size: square, at least 72x72 px.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `deck-config`: the "Key definition" requirement allows `image`, a file path that must not start with `sf:`.
- `key-rendering`: the "Static key appearance" requirement adds the full-key image layer and the label shadow. A new requirement covers a missing image file. The "Dynamic key JSON output" requirement (from `2-dynamic-key-json`) adds the `image` field.
- `config-editor`: the "Key editing" requirement covers the image field.

## Impact

- `Sources/DeckConfig/Model.swift`, `ConfigLoader.swift`: `KeyDefinition.image`, parsing and validation.
- `Sources/DeckConfig/ConfigDocument.swift`, `ConfigDocumentYAML.swift`: `KeyDocument.image`, read and canonical write.
- `Sources/DeckRender/KeyRenderer.swift`: `KeyAppearance.image`, aspect-fill drawing, label shadow, missing-image problem.
- `Sources/DeckEngine/DynamicOutput.swift`, `DeckEngine.swift`: the JSON `image` field and merging it over the definition.
- `Sources/StreamDeckApp/Editor/KeyInspector.swift`: Image field.
- `docs/config.md`, including the full example that a test loads.
- The specs this change modifies live in the unarchived changes `streamdeck-menubar-controller`, `2-dynamic-key-json` and `1-config-editor`. Those must be archived before this one.
- No new dependencies.
