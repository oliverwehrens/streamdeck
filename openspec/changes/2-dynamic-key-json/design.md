# Design

## Context

`DeckEngine.dynamicFinished` stores the first output line in `dynamicLabels: [Int: String]`, and `render(key:)` uses it in place of `definition.label`. `KeyAppearance` already carries background, icon and label, so the renderer needs no change.

Icon strings are turned into `Icon` values inside `ConfigLoader.parseKey`: the `sf:` prefix becomes `.symbol`, `~` is expanded, and relative paths are resolved against `baseDirectory`. The engine never sees icon strings and does not know the config directory.

## Goals / Non-Goals

**Goals:**
- A script can set label, icon and background in one run.
- Plain-text dynamic keys behave exactly as today.

**Non-Goals:**
- Pushing updates into the app (URL scheme, socket, CLI). Polling stays the only source.
- Mapping output states to appearances in YAML (`states:`).
- Text color, progress bars or other new appearance fields. Unknown JSON fields are ignored, which leaves room for them later.
- A configurable timeout.

## Decisions

### Autodetect JSON by a leading `{`
Output whose first non-whitespace character is `{` is parsed as JSON. Everything else is plain text.
- Alternative: an opt-in `output: json` field. That touches `ConfigLoader`, `ConfigDocument`, the YAML writer and the editor, all of which are being changed in `1-config-editor`. It buys little, because no realistic label starts with `{`.
- Once output starts with `{`, it must parse. It never falls back to plain text, so a broken script shows the error indicator instead of a raw `{"lab` label.

### A pure parser, separate from the engine
A function in `DeckEngine` takes stdout and the config directory and returns either `DynamicOutput { label: String?, icon: Icon?, background: HexColor? }` or an error message. It uses `JSONSerialization`. A `Codable` struct would turn "wrong type" and "unknown field" into decoding errors that are harder to word, and unknown fields must be ignored anyway.
- Plain text maps to `DynamicOutput(label: firstLine)`, so the engine has one code path.
- The parser is unit-tested without the engine or timers.

### Share icon string parsing
Move the `sf:` / `~` / relative-path logic out of `ConfigLoader.parseKey` into a public `Icon(configValue:relativeTo:)` in `DeckConfig`. Both the loader and the parser call it, so both forms resolve the same way.

### Config directory passed to `DeckEngine.init`
`DeckEngine.init` gains `configDirectory: URL`. `AppDelegate` passes `ConfigFile.defaultURL.deletingLastPathComponent()`. Tests pass a temporary directory.
- Alternative: store the directory in `DeckConfig`. It would then take part in `DeckConfig` equality and editor previews, for no benefit.

### Merge in `render(key:)`
`dynamicLabels` becomes `dynamicOutputs: [Int: DynamicOutput]`. `render(key:)` takes each field from the output when present, otherwise from the definition. On a failed run (non-zero exit, timeout, rejected JSON), the stored output is left alone. That keeps the whole last appearance, as the "Dynamic key failure" requirement asks. A successful run replaces the stored output completely, so a field dropped from the next JSON output falls back to YAML.

### Error messages
Rejected output reuses `Problem.Source.dynamic(key:)`. Messages name the reason, e.g. `Key 4 dynamic output is not valid JSON`, `Key 4 dynamic output: background 'yellow' must be #RRGGBB`, `Key 4 dynamic output: label must be a string`.

## Risks / Trade-offs

- [A script's plain-text label starts with `{`] -> It is now rejected as invalid JSON. This is unlikely, and the menu explains it. The script can print the text as `{"label":"..."}`.
- [The engine resolves file icons on every run, so a missing file is reported each run] -> `render(key:)` already deduplicates problems per key. The image is loaded by the renderer as it is today.
- [The `key-rendering` spec only exists in the unarchived `streamdeck-menubar-controller` change] -> Archive that change first. The MODIFIED blocks copy its current requirement text.
