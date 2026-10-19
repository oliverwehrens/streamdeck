# Spec Delta

## Purpose

Lets the user edit the whole deck configuration in a window instead of hand-editing YAML, previewing each change on the device before saving it to the config file.

## ADDED Requirements

### Requirement: Editor window
The system SHALL provide one editor window. Opening it again while it is open SHALL bring the existing window to the front. The window SHALL show the pages, a 5x3 key grid laid out like the device for the selected page, an inspector for the selected key, and the global settings.

#### Scenario: Open editor
- **WHEN** the user chooses "Edit Config…" from the menu
- **THEN** the editor window opens showing the current config, with `default_page` selected

#### Scenario: Open twice
- **WHEN** the editor window is open and the user chooses "Edit Config…" again
- **THEN** the existing window comes to the front and no second window opens

#### Scenario: Grid matches device
- **WHEN** the selected page defines keys 0 and 14
- **THEN** the grid shows key 0 top-left and key 14 bottom-right, each drawn with its icon, label and background

### Requirement: Key editing
The inspector SHALL edit every key field: icon (SF Symbol name or image file), label, background color, action (one of run, open, keys, media, page) and dynamic (command and interval). The user SHALL be able to clear a key so it is undefined.

#### Scenario: Set an action
- **WHEN** the user selects key 3, chooses action type `media` and picks `mute`
- **THEN** the draft has key 3 with action `media: mute`

#### Scenario: Pick an SF Symbol
- **WHEN** the user opens the symbol picker, searches for `mic` and clicks `microphone.slash.fill`
- **THEN** the key's icon is `sf:microphone.slash.fill` and the picker closes

#### Scenario: Browse symbols by category
- **WHEN** the user opens the symbol picker and chooses the category Media
- **THEN** the picker shows only symbols in that category, each drawn with its name available on hover

#### Scenario: Pick an image file
- **WHEN** the user picks an image inside `~/.config/streamdeck/`
- **THEN** the key's icon is stored as a path relative to that directory

#### Scenario: Clear a key
- **WHEN** the user clears key 3
- **THEN** key 3 is undefined in the draft and the device shows it blank

### Requirement: Page management
The editor SHALL add, rename and delete pages. A page name SHALL be non-empty and unique.

#### Scenario: Add a page
- **WHEN** the user adds a page named `zoom`
- **THEN** the draft has an empty page `zoom` and it is selected

#### Scenario: Duplicate name
- **WHEN** the user renames a page to the name of another page
- **THEN** the rename is refused and the editor says the name is taken

### Requirement: Page rename updates references
Renaming a page SHALL update every `page:` action, `app_pages` entry and `default_page` that names it, in the same edit.

#### Scenario: Rename referenced page
- **WHEN** key 4 on `home` has action `page: media`, `app_pages` maps `com.spotify.client` to `media`, and the user renames `media` to `music`
- **THEN** key 4's action is `page: music` and `com.spotify.client` maps to `music`

### Requirement: Page delete is guarded
Deleting a page that is referenced by `default_page`, a `page:` action or an `app_pages` entry SHALL be refused. The editor SHALL list the references.

#### Scenario: Delete referenced page
- **WHEN** the user deletes `media` while key 4 on `home` has action `page: media`
- **THEN** the page is not deleted and the editor names page `home`, key 4 as a reference

#### Scenario: Delete unreferenced page
- **WHEN** the user deletes a page nothing refers to
- **THEN** the page is removed from the draft

### Requirement: Settings editing
The editor SHALL edit `brightness` (0-100), `default_page` (chosen from existing pages) and the `app_pages` map (bundle ID to existing page). Adding an `app_pages` entry SHALL offer to pick a running or installed application to fill in its bundle ID.

#### Scenario: Map an app
- **WHEN** the user adds an `app_pages` entry by picking Safari and page `browser`
- **THEN** the draft maps `com.apple.Safari` to `browser`

### Requirement: Draft and live preview
Edits SHALL change a draft, not the file. The device SHALL show the draft within 1 second of an edit while the draft is valid. While the draft is invalid, the device SHALL keep showing the last valid draft.

#### Scenario: Preview a label
- **WHEN** the user changes key 0's label to `Term`
- **THEN** the device shows `Term` within 1 second and `config.yaml` is unchanged

#### Scenario: Invalid draft
- **WHEN** the user types `cmd+` as a key combination
- **THEN** the device keeps showing the last valid draft

### Requirement: Validation display
The editor SHALL validate the draft with the same rules as loading the file. Each error SHALL show next to the page, key or setting it refers to. Save SHALL be disabled while any error exists.

#### Scenario: Error on a key
- **WHEN** key 2's action is `keys: cmd+` in the draft
- **THEN** key 2 is marked in the grid, the inspector shows that the combination has only modifiers, and Save is disabled

### Requirement: Save
Save SHALL write the draft to `config.yaml` atomically, in a canonical format. Saving SHALL NOT preserve comments or the original formatting. A saved file SHALL load to a config equal to the draft.

#### Scenario: Round trip
- **WHEN** the user saves a valid draft
- **THEN** loading `config.yaml` yields the same pages, keys, settings, relative icon paths and interval units as the draft

#### Scenario: Save applies
- **WHEN** the user saves
- **THEN** the draft has no unsaved changes and the device keeps showing the same config

### Requirement: First overwrite backup
Before the first save over a file the editor did not write, the editor SHALL warn that comments and formatting will be lost. On confirm, it SHALL copy the existing file to `config.yaml.bak` before writing.

#### Scenario: Hand-written file
- **WHEN** `config.yaml` was edited by hand and the user saves from the editor
- **THEN** the editor warns once, and after confirmation `config.yaml.bak` holds the previous file

#### Scenario: Cancel the warning
- **WHEN** the user cancels the warning
- **THEN** neither file changes and the draft keeps its edits

#### Scenario: Editor-written file
- **WHEN** the file was last written by the editor and the user saves again
- **THEN** no warning appears and no backup is written

### Requirement: Revert and close
Revert SHALL discard the draft, reload `config.yaml`, and return the device to it. Closing the window with unsaved changes SHALL ask to save, discard or cancel.

#### Scenario: Revert
- **WHEN** the user has unsaved edits and chooses Revert
- **THEN** the editor and the device show the config from `config.yaml`

#### Scenario: Close with unsaved edits
- **WHEN** the user closes the window with unsaved edits and chooses Discard
- **THEN** the window closes and the device shows the config from `config.yaml`

### Requirement: External changes
When `config.yaml` changes on disk while the editor is open, the editor SHALL reload it if the draft has no unsaved changes. If the draft has unsaved changes, the editor SHALL ask whether to reload from disk or keep the draft.

#### Scenario: No unsaved edits
- **WHEN** the editor is open with no unsaved edits and the file is changed in a text editor
- **THEN** the editor shows the new file content

#### Scenario: Keep the draft
- **WHEN** the draft has unsaved edits, the file changes on disk, and the user chooses to keep the draft
- **THEN** the draft and the device are unchanged, and the next save shows the overwrite warning

#### Scenario: Invalid file on disk
- **WHEN** the file on disk changes to invalid YAML while the editor is open
- **THEN** the editor keeps its draft and shows that the file on disk has errors

### Requirement: Device shows the edited page
While the editor window is focused, the device SHALL show the page selected in the editor. When the window loses focus or closes, the device SHALL return to the page normal navigation selects.

#### Scenario: Select a page
- **WHEN** the editor window is focused and the user selects page `media`
- **THEN** the device shows page `media`

#### Scenario: Leave the editor
- **WHEN** the user switches from the editor to Safari, which `app_pages` maps to `browser`
- **THEN** the device shows page `browser`

### Requirement: Select key from device
While the editor window is focused, pressing a device key SHALL select that key in the editor and SHALL NOT run its action. When the window is not focused, keys SHALL behave normally.

#### Scenario: Press while editing
- **WHEN** the editor window is focused and the user presses key 7 on the device
- **THEN** key 7 is selected in the editor and its action does not run

#### Scenario: Editor in background
- **WHEN** the editor window is open but another app is focused and the user presses key 7
- **THEN** key 7 runs its action
