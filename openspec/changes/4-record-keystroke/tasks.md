# Tasks

Issue #4 has no checklist items, so nothing here duplicates it.

## 1. Key combos and layouts

- [x] 1.1 Change `KeyCombo` to store `key: Key` (`.character` for letters, digits, punctuation, `.named(code)` for the rest), keep `parse` accepting the same names, and add `KeyCombo.text` with one canonical name per named key and modifiers in the order `cmd`, `ctrl`, `alt`, `shift`, `fn`; verify with updated `KeyComboTests` (parse expects keys instead of codes; `text` of `cmd+shift+m`, `ctrl+alt+left`, `f12` matches exactly; `Command+Option+Esc` normalizes to `cmd+alt+esc`; `parse(combo.text) == combo` for every name and every modifier subset) and the updated assertion in `ConfigLoaderTests.swift:56`
- [x] 1.2 Add `Sources/DeckEngine/KeyboardLayout.swift` with the `KeyboardLayout` protocol, `SystemKeyboardLayout` (current ASCII-capable layout through `UCKeyTranslate`, no modifiers, no dead keys, read on every call) and `USKeyboardLayout`; add a fake German layout in `Tests/DeckEngineTests/Fakes.swift`; verify with a test that `USKeyboardLayout` maps every character name to the code `keyCodes` had before, and that the fake German layout maps `z` to 0x10, `y` to 0x06 and has no key for `[`

## 2. Sending

- [x] 2.1 Add `SystemActionPerformer.resolve(_:layout:)`, inject the layout into `SystemActionPerformer`, and return `.failed` with the layout name and character on a miss; verify with `ActionTests` on the fake German layout: `cmd+z` resolves to 0x10, `cmd+left` to 0x7B on every layout, and `cmd+[` fails with the message from "Bracket on a German layout" in `specs/key-actions/spec.md` without posting
- [x] 2.2 Replace "Letters map to US key positions" in `docs/config.md` with the layout rule (characters follow the active layout, non-Latin layouts use the Latin shortcut layout, named keys are layout-independent) and the missing-character error; verify the text matches the requirements in `specs/key-actions/spec.md`

## 3. Event mapping

- [x] 3.1 Add `Sources/StreamDeckApp/Editor/KeyRecorder.swift` with the `Recording` enum and `recording(keyCode:flags:layout:)` from design.md, dropping `.function` for F-keys, arrows, home, end, page up, page down and forward delete; verify with a new `Tests/StreamDeckAppTests/KeyRecorderTests.swift` on the fake German layout covering "Record a combination", "Record a named key", "Record on a German layout" (0x10 → `cmd+z`), "F-key", "Arrow key", "Held fn", "Keypad key" (key code 0x57) and "Letter without a config name" (Ö) in `specs/config-editor/spec.md`

## 4. Recorder view

- [ ] 4.1 Build the recorder view in `KeyRecorder.swift`: idle state shows the value or "Click to record" in secondary style, recording state shows held modifiers, local monitor for `keyDown`, `flagsChanged` and mouse down as in design.md, Esc cancels, unsupported keys show an inline message; verify manually against "Record a combination", "Modifiers only", "Editor shortcut while recording" (Cmd-S records, nothing saves), "Cancel with Esc" and "Keypad key"
- [ ] 4.2 Stop recording on click elsewhere, window resign key, key selection change and view disappearance, removing the monitor in each path; verify manually against "Click elsewhere", and that after switching keys mid-recording and after closing the window mid-recording, typing in the Label field and Cmd-S work again
- [ ] 4.3 Add the clear button and the "Edit as Text" mode with the existing `TextField`; replace the `.keys` case in `ActionEditor` with the recorder and update the hint to name combos macOS keeps for itself (Cmd-Space, Cmd-Tab); verify manually against "New keystroke action", "Clear the value" and "Type a combination", and that a recorded key previews on the device
- [x] 4.4 Describe recording in the Config editor section of `docs/config.md`: click to record, Esc cancels, the fn rule, the active layout decides letters, and Edit as Text for system shortcuts; verify the text matches the requirements in `specs/config-editor/spec.md` and `swift test` passes

## 5. Integration check

- [ ] 5.1 Build with `scripts/bundle.sh`, record `cmd+shift+m`, `f12` and `ctrl+alt+left` on three keys, type `cmd+space` on a fourth, save, and reopen the editor; verify `config.yaml` holds those four values and each key sends its shortcut from the device
- [ ] 5.2 Switch to the German layout: record the key labeled Y and check it saves as `y`; press a device key with `keys: cmd+z` in TextEdit and check it undoes; press one with `keys: cmd+[` and check the menu shows the missing-character error; verify `swift test` passes

## Workflow follow-up

- Archive `streamdeck-menubar-controller`, `1-config-editor` and `3-full-key-image` before this change, since its deltas build on their `key-actions` and `config-editor` specs.
