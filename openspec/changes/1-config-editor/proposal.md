Issue: #1

# Proposal

## Why

The only way to change the deck today is to hand-edit `~/.config/streamdeck/config.yaml`. That means remembering the field names, the key numbering, the action syntax and the SF Symbol names. Issue #1 asks for a UI to edit the key config.

## What Changes

- New editor window, opened from the menu bar, that edits the whole config:
  - **Keys**: a 5x3 grid mirroring the deck, with an inspector for icon, label, background, action and dynamic settings of the selected key.
  - **Pages**: add, rename and delete. Renaming a page updates every `page:` action, `app_pages` entry and `default_page` that points at it. Deleting a page that is still referenced is refused, and the editor lists the references.
  - **Settings**: brightness, default page, and the `app_pages` map.
- The editor holds a draft. Every draft change is previewed live on the device. The file changes only on **Save**. **Revert** drops the draft and returns the device to the saved config.
- Save writes the config in a canonical format generated from the model. **BREAKING** for hand-edited files: comments, key order and formatting are not preserved. Before the first save that overwrites a file the editor did not write, the editor warns once and copies the original to `config.yaml.bak`.
- Save is disabled while the draft is invalid. Errors come from the existing validator and show next to the field they refer to.
- If the file changes on disk while the draft has unsaved edits, the editor asks whether to reload from disk or keep the draft. Without unsaved edits, it reloads silently.
- Pressing a physical key while the editor window is focused selects that key in the editor instead of running its action.
- The app shows a Dock icon while the editor window is open, so the window can be focused and switched to with Cmd-Tab. It returns to menu-bar only when the window closes.
- Values keep the form the user wrote them in: icon file paths stay relative, and dynamic intervals keep their unit.

## Capabilities

### New Capabilities
- `config-editor`: The editor window. Covers the draft and its live preview, saving and reverting, canonical writing, validation display, page and settings editing, external-change handling, and key selection from the device.

### Modified Capabilities
- `menubar-app`: "Menu-bar only" now allows a Dock icon while the editor window is open. "Config commands" adds "Edit Config…".
- `deck-config`: "Live reload" now defers to the editor's draft. While the editor has unsaved edits, a change on disk does not replace what the device shows.

Both capabilities are defined by the in-progress change `streamdeck-menubar-controller` and are not yet in `openspec/specs/`. That change must be archived before this one, so these deltas have a base to modify.

## Impact

- `Sources/DeckConfig`: a new editable document model that holds values as text, with YAML reading and canonical writing. `DeckConfig` and `ConfigLoader` stay as they are.
- `Sources/DeckEngine`: a way to route key presses to the editor instead of running actions.
- `Sources/StreamDeckApp`: new SwiftUI editor window, activation-policy switching, a menu item, and routing of watcher updates through the editor while a draft is open.
- No new package dependencies. SwiftUI and AppKit ship with macOS 14. Yams already handles YAML output.
- `docs/config.md`: describes the editor and states that saving from it drops comments.
