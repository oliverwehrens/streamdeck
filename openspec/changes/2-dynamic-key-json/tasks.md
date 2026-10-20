# Tasks

Issue #2 has two checklist items. Groups 1-3 deliver "Parse JSON output and merge it over the key definition". Task 4.1 delivers "Document the output format in docs/config.md". Tick the issue items when those tasks are done.

## 1. Shared icon parsing

- [x] 1.1 Move the `sf:` / `~` / relative-path logic from `ConfigLoader.parseKey` into a public `Icon(configValue:relativeTo:)` in `DeckConfig`, and call it from the loader; verify with `DeckConfigTests` unit tests for `sf:name`, `~/x.png`, `/abs.png` and `icons/x.png`, and verify `swift test --filter DeckConfigTests` still passes

## 2. Output parser

- [x] 2.1 Add `DynamicOutput { label, icon, background }` and a parser in `DeckEngine` that takes stdout and a config directory and returns the output or an error message; plain text maps to the trimmed first line as `label`; verify with unit tests that the existing first-line behavior (`"  12:34  \nsecond"` -> `12:34`) is unchanged
- [x] 2.2 Handle output starting with `{` after leading whitespace: parse it as a JSON object with `JSONSerialization`, read `label`, `icon` and `background`, ignore unknown fields, and reject non-objects, wrong types and invalid colors with messages that name the field; verify with unit tests for each scenario under "Dynamic key JSON output" and "Dynamic key icon values" in `specs/key-rendering/spec.md`, plus truncated JSON and a top-level array

## 3. Engine integration

- [x] 3.1 Add `configDirectory: URL` to `DeckEngine.init`, pass `ConfigFile.defaultURL.deletingLastPathComponent()` from `AppDelegate`, and update the test helpers in `Tests/DeckEngineTests`; verify `swift build` succeeds and existing tests pass
- [x] 3.2 Replace `dynamicLabels` with `dynamicOutputs: [Int: DynamicOutput]`. In `dynamicFinished`, store the parsed output on success. Treat a parse error like a failed run: keep the stored output, set the error indicator, and add a `.dynamic(key:)` problem. In `render(key:)`, merge each field over the definition. Verify with `DynamicKeyTests` tests: JSON sets icon, label and background; omitted fields fall back to YAML; invalid JSON after a good run keeps the last appearance with the error indicator and the problem message; a later plain-text run resets icon and background to YAML; all existing `DynamicKeyTests` pass

## 4. Docs and editor

- [ ] 4.1 Extend the "Dynamic keys" section of `docs/config.md` with the JSON format, field rules, failure behavior and the Home Assistant example script, and update the `dynamic` row in the key fields table; verify by running the example's `echo` lines through a dynamic key on the device
- [ ] 4.2 Rename the inspector section "Dynamic label" to "Dynamic" in `KeyInspector.swift`, with a one-line hint that the command can print plain text or JSON with `label`, `icon`, `background`; verify by opening the editor and checking the section

## 5. Integration check

- [ ] 5.1 Build with `./scripts/bundle.sh`, install, and configure two keys: one printing `{"icon":"sf:lightbulb.fill","background":"#c08000","label":"on"}`, and one that alternates between valid JSON and `{"label":`; verify on the device that the first shows the yellow bulb, and that the second keeps its last appearance with a red dot and the reason in the menu

## Workflow follow-up

- Archive `streamdeck-menubar-controller` before archiving this change, so the `key-rendering` main spec exists for the MODIFIED delta.
- Close issue #2 after archive.
