# Tasks

Issue #1 has no checklist items, so none are referenced here.

## 1. Config document model (D1, D3, D4)

- [x] 1.1 Add `ConfigDocument`, `PageDocument` and `KeyDocument` to `DeckConfig` with text-valued fields, ordered pages and ordered `app_pages`; verify `swift build` succeeds and the types are `Equatable`
- [x] 1.2 Implement `ConfigDocument.read(yaml:)` that copies values as text and fails only on structure it cannot represent (bad YAML, non-mapping sections, unknown fields); verify with unit tests: the `docs/config.md` example reads with relative icon paths, `30s` and `option+x` kept as written; a bad color reads as text; an unknown field fails
- [x] 1.3 Implement the canonical writer with a Yams `Node` tree: header comment, flow-style keys and actions, keys sorted by index, document order for pages and `app_pages`, empty fields omitted; verify with a unit test of the exact output for a small document, and a test that labels containing `#`, `:`, `"` and a leading `~` survive
- [x] 1.4 Add the round-trip test: for the starter config, the `docs/config.md` example and a set of generated documents, write, load with `ConfigLoader`, read back, and compare both the document and the `DeckConfig`; verify `swift test --filter DeckConfigTests` passes
- [x] 1.5 Implement `rename(page:to:)` (updates `page` actions, `app_pages` values, `defaultPage`; rejects empty and duplicate names) and `delete(page:)` (returns references instead of deleting); verify with unit tests for each scenario in the spec requirements "Page management", "Page rename updates references" and "Page delete is guarded"
- [x] 1.6 Add `isEditorWritten(text:)` (header check); verify with unit tests for editor-written, hand-edited and starter files

## 2. Engine hooks (D7)

- [x] 2.1 Add `editorPage: String?` to `DeckEngine`, rendering that page when set while navigation keeps tracking apps; verify with a `DeckEngineTests` test that sets it, activates another app, clears it, and checks the page shown matches the app's mapped page
- [x] 2.2 Add `onEditorKeyPress: ((Int) -> Void)?`, called on key-down before the action lookup, including for keys without an action; verify with a test using the fake transport and performer that no action runs and the callback receives the key
- [x] 2.3 Skip `configLoaded` work when the new config equals the current one, so identical previews don't restart dynamic keys; verify with a test that a second identical `configLoaded` starts no new dynamic command

## 3. Editor model (D2, D5, D6)

- [ ] 3.1 Create `EditorModel` (`@Observable`, `@MainActor`) holding `saved`, `draft`, `isDirty`, `errors` and `lastValid`, with a 150 ms debounced validate-and-preview via document -> YAML -> `ConfigLoader.load(yaml:)` -> engine; verify by running the app: a label edit shows on the device within 1 second and `config.yaml` is unchanged
- [ ] 3.2 Implement `save()`: refuse when errors exist, warn and write `config.yaml.bak` when the file lacks the editor header, write atomically, update `saved`; verify manually against the "First overwrite backup" scenarios (hand-edited file warns once, cancel leaves both files untouched, second save has no warning)
- [ ] 3.3 Implement Revert and the close prompt (Save / Discard / Cancel); on close, return the device to `ConfigWatcher.config`; verify manually against the "Revert and close" scenarios
- [ ] 3.4 Route watcher updates through `EditorModel` while the window is open: ignore its own save, reload silently when clean, prompt when dirty, keep the draft when the file is invalid; verify manually against each "External changes" scenario and the deck-config "Unsaved editor draft" scenario by editing `config.yaml` in a text editor

## 4. Editor window and menu (D8, D9)

- [ ] 4.1 Add `EditorWindowController` with one `NSWindow` hosting SwiftUI, switching activation policy to `.regular` on open and `.accessory` in `windowWillClose`, and setting or clearing the engine hooks on key/resign-key; add "Edit Config…" to the menu; verify manually: the Dock icon appears and disappears, Cmd-Tab reaches the window, a second "Edit Config…" focuses the same window
- [ ] 4.2 Build the layout: sidebar with pages (add, rename, delete with reference list) and Settings, a 5x3 key grid drawn with `KeyRenderer` from the last valid preview, error outlines on keys; verify manually that the grid matches the device and that a referenced page cannot be deleted
- [ ] 4.3 Build the key inspector: icon (symbol field with preview and validity, file picker storing relative paths inside the config directory), label, background with None, action picker with kind-specific fields, dynamic, Clear key; inline errors from `ConfigError` page/key; verify manually by recreating every key of the `docs/config.md` example in the editor and comparing the saved file's loaded config
- [ ] 4.4 Build the settings view: brightness slider, default page picker, `app_pages` table with running-app list and Choose App…; verify manually by mapping Safari to a page and switching to Safari after closing the editor
- [ ] 4.5 Wire device key presses to select keys and the device to show the selected page while the window is focused; verify manually against the "Device shows the edited page" and "Select key from device" scenarios
- [x] 4.6 Update `docs/config.md` and `README.md`: describe "Edit Config…", the live preview, and that saving from the editor drops comments and writes `config.yaml.bak`; verify the docs example test from the earlier change still passes
- [ ] 4.7 Add the SF Symbol picker (D10): `SymbolCatalog` loading names, categories and keywords from the system's CoreGlyphs plists without localized variants, and a popover with search, category menu and a grid; verify with tests that the catalog loads, excludes `.ar` variants, and that searching `mic` finds `microphone.slash.fill`, and old names such as `mic.slash.fill` resolve; then manually that clicking a symbol sets the key's icon

## 5. Integration

- [ ] 5.1 Build with `scripts/bundle.sh`, start from a fresh `config.yaml` (starter), edit keys, pages and settings, save, quit, relaunch; verify the device and the editor show the saved config and `swift test` passes

## Workflow follow-up

- Archive `streamdeck-menubar-controller` before archiving this change, so the `menubar-app` and `deck-config` deltas have base specs.
- After archiving, close issue #1 per the project's archive guidance.
