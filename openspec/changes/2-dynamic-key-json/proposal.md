Issue: #2

# Proposal

## Why

A dynamic key can only change its label: the first line of the command's output replaces it. Status keys, such as a Home Assistant entity or the bitcoin price, read better when the script also sets the icon and background color (yellow bulb when the light is on, red when the price drops).

## What Changes

- When a dynamic command's output starts with `{`, it is parsed as a JSON object with optional `label`, `icon` and `background` fields.
- Each field present replaces the key's YAML value. Fields left out keep the YAML value.
- `icon` uses the same syntax as the config: `sf:<name>` or an image path. Relative paths resolve against the config directory.
- Output that is invalid JSON, or that holds a value of the wrong type or an invalid color, counts as a failed run: the key keeps its last good appearance and shows the error indicator, and the menu shows the reason.
- Plain-text output works as before. No config fields are added, so the loader, the YAML writer and the config editor stay unchanged apart from a hint in the editor.
- `docs/config.md` documents the output format with an example script.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `key-rendering`: the "Dynamic keys" requirement gains JSON output that can set label, icon and background. The "Dynamic key failure" requirement also covers invalid JSON output and keeps the whole last appearance, not only the label.

## Impact

- `Sources/DeckEngine/DeckEngine.swift`: dynamic results hold label, icon and background instead of a label string. `render(key:)` merges them over the key definition.
- `Sources/DeckEngine`: a new parser for command output (plain text or JSON).
- `Sources/DeckConfig`: icon string parsing (`sf:` prefix, `~`, relative paths) moves out of `ConfigLoader` so the engine can reuse it.
- `DeckEngine.init` takes the config directory, passed from `AppDelegate`.
- `Sources/StreamDeckApp/Editor/KeyInspector.swift`: the section title changes from "Dynamic label" to "Dynamic", and the section gets a hint about JSON output.
- `docs/config.md`: the dynamic keys section.
- The `key-rendering` spec lives in the unarchived `streamdeck-menubar-controller` change. That change must be archived before this one.
- No new dependencies. Foundation's `JSONSerialization` is enough.
