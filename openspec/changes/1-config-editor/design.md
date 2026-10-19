# Design

## Context

Motivation and scope: see proposal.md. Behavior: see `specs/`.

Current state that shapes the approach:
- `ConfigLoader.load(yaml:baseDirectory:)` (`Sources/DeckConfig/ConfigLoader.swift`) is the only validator. It collects all errors, each with an optional line, page and key.
- `DeckConfig` is lossy for writing. `Icon.file` holds the resolved absolute path. `Dynamic.every` is a `TimeInterval`. `KeyCombo` holds a key code, and the `option` alias becomes `alt`. It also cannot hold invalid input such as a half-typed `cmd+`.
- `DeckEngine.configLoaded(_:)` accepts an in-memory config. It resets the session brightness override and keeps the current page if it still exists.
- `DeckEngine.handleKey` runs the action on key-down and ignores keys without an action.
- `Navigation` ignores activation of the app's own bundle ID. When the editor is focused, the device stays on the page of the previous frontmost app.
- The app is AppKit with `LSUIElement = YES` and no windows. `ConfigWatcher` feeds `AppDelegate`, which forwards to the engine.

## Goals / Non-Goals

**Goals:**
- One validation path: the editor validates with `ConfigLoader`, the same code that loads the file.
- Editor logic (document model, reading, writing, rename cascade, delete guard) testable with `swift test`, without a window or a device.

**Non-Goals:**
- Preserving comments or formatting (decided in explore, see proposal).
- Undo/redo across the whole draft. Text fields get the system's per-field undo.
- Drag-and-drop to move or swap keys.
- Editing several config files or profiles.

## Decisions

### D1. The draft is a text-valued `ConfigDocument`, not `DeckConfig`
New type in `DeckConfig`:
```
ConfigDocument
  brightness: Int
  defaultPage: String
  pages: [PageDocument]            // ordered, as shown in the editor
  appPages: [(bundleID, page)]     // ordered
PageDocument { name, keys: [Int: KeyDocument] }
KeyDocument  { icon, label, background: String?
               action: (kind, value: String)?
               dynamic: (run, every: String)? }
```
Every value stays the text the user typed: `icons/zoom.png`, `30s`, `cmd+shift+m`.
- Why: the draft must hold invalid intermediate input, and the writer must emit what the user wrote. Making `DeckConfig` lossless would push raw strings into the engine's model for the editor's sake.
- Alternative: make `DeckConfig` lossless and editable. Rejected: it still cannot represent invalid input, and the engine and renderer would carry fields they never use.

### D2. Validation and preview go document -> YAML -> `ConfigLoader`
```
 ConfigDocument --write--> YAML text --ConfigLoader.load(yaml:)--> DeckConfig | [ConfigError]
       ^                       |                                       |            |
       | read (lenient)        +--> Save writes this text to disk      |            v
       |                                                               v     editor shows errors
  config.yaml                                              engine.configLoaded (preview)
```
The YAML that validation checks is the exact text Save writes. Errors map back to the UI by their `page` and `key` fields. Errors with neither (`default_page`, `app_pages`, `brightness`) show in the settings section.
- Why: no second validator to keep in sync, and Save cannot write something the loader rejects.
- Cost: a full YAML write and parse per edit. The config holds at most a few pages of 15 keys, so this takes well under a millisecond.

### D3. Reading the file into a document
`ConfigDocument.read(yaml:)` composes the file with Yams and copies scalars as text. It is lenient about values (a bad color stays as text, so the editor can show and fix it) and strict only about structure it cannot represent. Structural problems include YAML that doesn't parse, a non-mapping `pages`, and unknown fields. For these, the editor shows the loader's errors and offers "Open Config" instead of an editable draft.
- Why: the editor must open a config with value errors in order to fix them, and must not silently drop data it does not understand.

### D4. Canonical writer builds a Yams `Node` tree
The writer builds `Node` values and serializes them with `Yams.serialize(node:)`. Key definitions and actions use flow style (`{ icon: sf:terminal, label: Terminal, action: { open: ... } }`), matching `docs/config.md`. Keys are sorted by index. Pages and `app_pages` keep document order. Empty fields are omitted. The first line is a fixed header comment:
```
# Written by the StreamDeck config editor. Comments added here are not kept.
```
- Why `Node` over string concatenation: Yams handles quoting of `#`, `:`, leading `~`, and the like.
- Why a header: it marks a file the editor wrote. A first line that differs means the file was hand-edited since, and the next save shows the backup warning. This needs no stored state.
- Alternative: store a hash of the last written file in `UserDefaults`. Rejected: it is invisible to the user and breaks if the app is reinstalled.
- Round-trip guarantee (spec "Save"): a property test writes documents, loads the output, reads it back, and compares.

### D5. `EditorModel` owns the draft and the save state
An `@Observable` `@MainActor` class in the app target:
- `saved: ConfigDocument` (last read or written) and `draft: ConfigDocument`. `isDirty` is `draft != saved`.
- `errors: [ConfigError]` and `lastValid: DeckConfig?`, recomputed 150 ms after the last edit (D2).
- `rename(page:to:)` and `delete(page:)` live on `ConfigDocument` (D1), so they are unit-testable. Rename rewrites `page` actions, `app_pages` values and `defaultPage`. Delete returns the references instead of deleting when any exist.
- `save()` checks the header (D4), confirms and backs up when needed, then writes atomically (`Data.write(options: .atomic)`).

### D6. The editor arbitrates between the watcher and the engine
`AppDelegate` sends watcher updates to `EditorModel` while the window is open, and to the engine otherwise.
```
 watcher update --> editor open?
                      no  --> engine.configLoaded / configFailed   (today's path)
                      yes --> text == last text written by editor? --> ignore (own save)
                              draft clean?  --> re-read document, engine gets file config
                              draft dirty?  --> prompt: Reload from disk | Keep my changes
                              file invalid? --> keep draft, show "file on disk has errors"
```
On window close (after save or discard), the engine gets the watcher's current file config (`ConfigWatcher.config`). This restores the device after a discarded draft.

### D7. Engine: editor overrides for page and key presses
Two additions to `DeckEngine`, both nil by default:
- `editorPage: String?`: when set, the engine renders this page instead of `navigation.currentPage`. Navigation keeps tracking apps underneath, so clearing it returns to the right page (spec "Device shows the edited page").
- `onEditorKeyPress: ((Int) -> Void)?`: when set, `handleKey` calls it on key-down before the action lookup and returns. Keys without an action can be selected this way too.

`EditorWindowController` sets both on `windowDidBecomeKey` and clears them on `windowDidResignKey` and on close.
- Why in the engine: page choice and key dispatch already live there. A separate path around it would duplicate rendering.
- Alternative: a `Navigation` event for the editor page. Rejected: it would mix a UI-focus concern into the navigation state machine and its history rules.

### D8. AppKit-managed window hosting SwiftUI
`EditorWindowController` (AppKit) owns one `NSWindow` with an `NSHostingController` around the SwiftUI view. On open: `NSApp.setActivationPolicy(.regular)`, `activate`, `makeKeyAndOrderFront`. On close: `.accessory`. `windowShouldClose` runs the save/discard/cancel prompt.
- Why not a SwiftUI `Window` scene: the app uses an AppKit `main.swift` and `NSApplicationDelegate`. Mixing in the SwiftUI `App` lifecycle would mean rewriting startup.
- Layout: `NavigationSplitView` with a sidebar (pages plus a Settings entry), the key grid and an inspector.

### D9. Field editors
- **Icon**: segmented control for SF Symbol or file. Symbol is a text field with live preview, marked invalid when `NSImage(systemSymbolName:)` returns nil, plus a **Choose…** button that opens the symbol picker (D10). File uses `NSOpenPanel` for PNG/JPEG. Paths inside the config directory are stored relative, other paths are stored with `~` abbreviated.
- **Background**: SwiftUI `ColorPicker`, converted to sRGB `#RRGGBB`. A "None" toggle omits the field.
- **Action**: a picker for the kind, then a kind-specific field: a text field for `run`; a text field plus Choose… for `open`; a text field for `keys` showing parse errors inline; a picker for `media`; a picker of pages plus `back` for `page`.
- **Dynamic**: a toggle, a command field, and an interval field with a unit hint.
- **App pages**: the add button lists running apps (`NSWorkspace.runningApplications`) plus "Choose App…" (`NSOpenPanel` in `/Applications`, read `Bundle(url:).bundleIdentifier`).
- **Grid cells**: rendered by `KeyRenderer` from the last valid preview config, so the grid looks like the device. If the draft is invalid, cells fall back to the last valid render, and keys with errors get a red outline.

### D10. Symbol picker reads the system's symbol catalog
macOS has no public API that lists SF Symbol names. The names, categories and search keywords ship as plists in `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources`: `symbol_order.plist`, `categories.plist`, `symbol_categories.plist`, `symbol_search.plist` and `name_aliases.strings`. Old names from the aliases (e.g. `mic.slash.fill`, now `microphone.slash.fill`) are searchable, and the current icon is highlighted under its new name. `SymbolCatalog` loads them once, drops localized variants (suffixes such as `.ar`, `.hi`, `.rtl`, `.ja`). The list comes from the installed macOS, so every name in it can be drawn. The picker is a popover with a search field (matching names and keywords), a category menu, and a lazy grid of symbols with the name as tooltip. A click sets `sf:<name>` and closes the popover.
- Why: the list always matches the installed macOS, with nothing to bundle or update.
- Alternative: bundle a curated name list. Rejected: it goes stale with each macOS release and would have far fewer symbols.
- Fallback: if the files are missing or unreadable, the picker says so and the text field still works.

## Risks / Trade-offs

- [The CoreGlyphs plists are undocumented and may change format or move in a future macOS] -> Loading is defensive (D10 fallback). A test reads the real files, so a format change shows up as a failing test rather than an empty picker.

- [Preview restarts dynamic keys on every edit, so their commands rerun as you type] -> 150 ms debounce, and the engine is only called when the loaded `DeckConfig` differs from the last previewed one.
- [`configLoaded` clears the session brightness override from the menu slider] -> Acceptable. The editor's brightness setting is the value the user is editing.
- [Yams flow-style output may quote or wrap differently than expected] -> The round-trip test (D4) catches meaning changes. Cosmetic differences don't matter, since the file is canonical.
- [Users who keep hand-editing lose comments on the next editor save] -> Warning plus `config.yaml.bak` on every save over a file without the header (D4). `docs/config.md` states it.
- [Keys pressed while the editor is focused don't run actions, which may surprise] -> The inspector header says "Press a key on the deck to select it". Focus changes restore normal behavior immediately.
- [Activation-policy switching can leave the Dock icon behind if the window is closed by an unusual path] -> Reset the policy in `windowWillClose`, which every close path hits.

## Migration Plan

No data migration. The first editor save over a hand-written file creates `config.yaml.bak`. Rollback is to quit the app and copy `config.yaml.bak` back.

`streamdeck-menubar-controller` must be archived before this change, so the `menubar-app` and `deck-config` deltas have base specs.
