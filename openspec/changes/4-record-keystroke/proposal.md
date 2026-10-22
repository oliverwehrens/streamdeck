Issue: #4

# Proposal

## Why

The Keystroke action's Keys field is a plain text field with `cmd+shift+m` as a gray placeholder. A new Keystroke action looks filled in but is empty, so validation fails and Save stays disabled. Pressing a combination in the field does nothing. Users expect to record a shortcut by pressing it, as in System Settings.

Sending is also position-based: a letter maps to its US key position. On a German keyboard `cmd+z` sends Command plus the key labeled Y, so the app sees Cmd-Y instead of undo. Recording by the layout can't work until sending uses the layout too, so both change here.

## What Changes

- The Keys field becomes a recorder. Click it, press a combination, and the action's value becomes the config text for it, e.g. `cmd+shift+m`, `f12`, `ctrl+alt+left`.
- While recording, the field shows the modifiers held so far. Pressing modifiers alone writes nothing.
- While recording, every key press goes to the recorder. Editor shortcuts such as Cmd-S and Cmd-W do not fire.
- Esc cancels recording and keeps the previous value. Clicking elsewhere, switching keys or leaving the window stops recording.
- A key that the config format cannot name, such as a keypad key or `ö`, shows an inline message. The value stays unchanged.
- The recorded text uses a fixed modifier order (`cmd`, `ctrl`, `alt`, `shift`, `fn`) and one name per key.
- `fn` is dropped for F-keys, arrows and the navigation keys (home, end, page up, page down, forward delete), because macOS sets it for those keys by itself. For other keys, `fn` is kept when the user holds it.
- The empty state reads "Click to record", not a value-like placeholder.
- A clear button empties the value. An "Edit as Text" button switches to the existing text field for combinations macOS takes before the app sees them, such as `cmd+space` or `cmd+tab`.
- **BREAKING**: letters, digits and punctuation are sent and recorded through the active keyboard layout, not US key positions. `cmd+z` is undo on every Latin layout. With a non-Latin layout active, the Latin layout macOS uses for shortcuts applies. Configs on US layouts behave as before.
- Named keys (`return`, `esc`, `space`, F-keys, arrows and the rest) are the same on every layout.
- A character the active layout cannot type without modifiers, such as `[` on German, sends nothing and shows an error in the menu.
- `docs/config.md` describes recording and the layout rule, replacing "Letters map to US key positions".

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `config-editor`: the "Key editing" requirement is restated. New requirements cover recording a keystroke by layout, cancel, unsupported keys, the `fn` rule, clearing and typing as text.
- `key-actions`: new requirements send keystroke characters through the active layout and report characters the layout cannot type.

## Impact

- `Sources/DeckConfig/KeyCombo.swift`: a combo stores a character or a named key instead of a key code, and gains a canonical text form.
- New `Sources/DeckEngine/KeyboardLayout.swift`: character-to-key-code lookup on the active layout through Carbon's text input source API, with a US table as fallback.
- `Sources/DeckEngine/SystemActionPerformer.swift`: resolves the key at press time and reports a missing character.
- `Sources/StreamDeckApp/Editor/KeyInspector.swift`: the `.keys` case of `ActionEditor` uses the recorder.
- New `Sources/StreamDeckApp/Editor/KeyRecorder.swift`: the recorder view and the event-to-combo mapping.
- Tests in `KeyComboTests`, `ConfigLoaderTests`, `ActionTests` and a new `Tests/StreamDeckAppTests/KeyRecorderTests.swift`.
- `docs/config.md`.
- No new permissions: a local event monitor sees only events sent to this app.
- The requirements this change builds on live in the unarchived changes `streamdeck-menubar-controller` (`key-actions`), `1-config-editor` and `3-full-key-image` (`config-editor`). Those must be archived before this one.
- No new dependencies.
