# Spec Delta

## Purpose

Edits the deck's `config.yaml` from a web browser on another device, such as a laptop or phone on the same network as a headless daemon. The deck previews the edits live.

## ADDED Requirements

### Requirement: Editor in the browser
When the web editor is enabled, the daemon SHALL serve it at `/` on its listen address. Once paired, a current desktop or mobile browser SHALL open it with nothing to install. The editor SHALL show the pages, a 5×3 grid of the selected page's keys, an inspector for the selected key, the settings, and Save and Revert.

#### Scenario: Open the editor
- **WHEN** a paired browser opens `http://steammachine.local:3325/`
- **THEN** it shows the editor with the default page selected

#### Scenario: Phone-sized screen
- **WHEN** the editor is opened on a 390-pixel-wide phone screen
- **THEN** the grid, inspector and Save button can all be reached without scrolling sideways

### Requirement: One shared draft
Edits SHALL change one draft held by the daemon, not the file. Every browser with the editor open SHALL show the current draft and SHALL show another browser's edit within 1 second. Unsaved edits SHALL survive a browser reload, but not a daemon restart.

#### Scenario: Two browsers
- **WHEN** the editor is open on a laptop and a phone, and the laptop changes key 0's label to `Term`
- **THEN** the phone shows `Term` on key 0 within 1 second and `config.yaml` is unchanged

#### Scenario: Reload the page
- **WHEN** the user has unsaved edits and reloads the browser tab
- **THEN** the editor shows the same unsaved edits

### Requirement: Key editing in the browser
The inspector SHALL edit every key field: icon (Material Symbol with outlined or filled style, SF Symbol name, or image path), image path, label, background color, action (run, open, keys, media, page) and dynamic (command and interval). Image and icon files SHALL be entered as paths, relative to the config directory or absolute on the daemon's machine. The user SHALL be able to clear a key.

#### Scenario: Set an action
- **WHEN** the user selects key 3, chooses action type `media` and picks `mute`
- **THEN** the draft has key 3 with action `media: mute`

#### Scenario: Image path
- **WHEN** the user enters `art/cat.jpg` as key 2's image
- **THEN** the draft has key 2 with `image: art/cat.jpg`, and the deck and the grid show it across the whole key if the file exists in the config directory

#### Scenario: Clear a key
- **WHEN** the user clears key 3
- **THEN** key 3 is undefined in the draft and the deck shows it blank

### Requirement: Page and settings editing in the browser
The editor SHALL add, rename and delete pages under the same rules as the Mac editor: renaming SHALL update every reference, and deleting a page that is still referenced SHALL be refused with a list of the references. The editor SHALL edit `brightness`, `default_page` and `app_pages`. `app_pages` entries SHALL be entered as an application identifier and a page.

#### Scenario: Rename a page
- **WHEN** key 5 on `home` has `page: media` and the user renames `media` to `music`
- **THEN** key 5's action becomes `page: music`

#### Scenario: Delete a referenced page
- **WHEN** the user deletes `media` while key 5 on `home` points to it
- **THEN** the page stays, and the editor names `page 'home', key 5` as the reason

#### Scenario: Reserved name
- **WHEN** the user adds a page named `back`
- **THEN** the editor refuses the name and explains that `back` is reserved

### Requirement: Validation in the browser
The editor SHALL validate the draft with the same rules as loading the file. Each error SHALL show next to the page, key or setting it refers to. Save SHALL be disabled while any error exists.

#### Scenario: Error on a key
- **WHEN** key 2's action is `keys: cmd+` in the draft
- **THEN** key 2 is marked in the grid, the inspector shows that the combination has only modifiers, and Save is disabled

### Requirement: Live preview on the deck
While a browser has the editor open, the deck SHALL show the draft within 1 second of an edit while the draft is valid. While the draft is invalid, the deck SHALL keep showing the last valid draft.

#### Scenario: Preview a label
- **WHEN** the user changes key 0's label to `Term` in the browser
- **THEN** the deck shows `Term` within 1 second and `config.yaml` is unchanged

#### Scenario: Invalid draft
- **WHEN** the user types `cmd+` as a key combination
- **THEN** the deck keeps showing the last valid draft

### Requirement: Grid shows the deck's images
The key grid SHALL show the images the daemon renders for the deck, so the grid and the deck match exactly. The images SHALL appear even when no deck is connected.

#### Scenario: Long label
- **WHEN** key 5 has `label: Deploy production environment`
- **THEN** the grid and the deck show the same lines, font size and ellipsis

#### Scenario: No deck attached
- **WHEN** no deck is connected and the user edits key 0
- **THEN** the grid shows key 0 as the deck would draw it

### Requirement: Deck follows the active editor
While a browser tab with the editor is visible, the deck SHALL show the page selected in it. If several are visible, the one used most recently SHALL decide. While no editor tab is visible, the deck SHALL show the page that normal navigation selects, still using the draft.

#### Scenario: Select a page
- **WHEN** the editor tab is visible and the user selects page `media`
- **THEN** the deck shows page `media`

#### Scenario: Tab hidden
- **WHEN** the user switches to another tab
- **THEN** the deck returns to the page normal navigation selects

### Requirement: Select a key from the deck
While a browser tab with the editor is visible, pressing a deck key SHALL select that key in that tab and SHALL NOT run its action. While no editor tab is visible, deck keys SHALL behave normally.

#### Scenario: Press while editing
- **WHEN** the editor tab is visible and the user presses key 7 on the deck
- **THEN** key 7 is selected in the editor and its action does not run

#### Scenario: Editor tab hidden
- **WHEN** the editor is open but its tab is hidden and the user presses key 7
- **THEN** key 7 runs its action

### Requirement: Leaving the editor
When no browser has had the editor open for 60 seconds, the deck SHALL return to the config in `config.yaml`. The draft SHALL be kept, and the next browser to open the editor SHALL see it and preview it on the deck again.

#### Scenario: Phone locked
- **WHEN** the user has unsaved edits and locks the phone for 2 minutes
- **THEN** the deck shows the saved config, and after unlocking the editor shows the unsaved edits and the deck previews them again

#### Scenario: Short interruption
- **WHEN** the user reloads the editor tab
- **THEN** the deck keeps showing the draft

### Requirement: Save from the browser
Save SHALL write the draft to `config.yaml` atomically, in the same canonical format as the Mac editor. A saved file SHALL load to a config equal to the draft.

#### Scenario: Save applies
- **WHEN** the user saves a valid draft
- **THEN** every open editor shows no unsaved changes, and the deck keeps showing the same config

### Requirement: First overwrite backup from the browser
Before the first save over a file the editor did not write, the editor SHALL warn that comments and formatting will be lost. On confirmation, the daemon SHALL copy the existing file to `config.yaml.bak` before writing.

#### Scenario: Hand-written file
- **WHEN** `config.yaml` was edited over ssh and the user saves from the browser
- **THEN** the browser warns once, and after confirmation `config.yaml.bak` holds the previous file

#### Scenario: Cancel the warning
- **WHEN** the user cancels the warning
- **THEN** neither file changes and the draft keeps its edits

### Requirement: Revert in the browser
Revert SHALL discard the draft, reload `config.yaml`, and return the deck and every open editor to it.

#### Scenario: Revert
- **WHEN** the user has unsaved edits and chooses Revert
- **THEN** the editors and the deck show the config from `config.yaml`

### Requirement: External changes in the browser
When `config.yaml` changes on disk, the editor SHALL load it if the draft has no unsaved changes. If the draft has unsaved changes, the editor SHALL ask whether to load the file or keep the draft. If the file on disk is invalid, the editor SHALL keep the draft and show the file's errors.

#### Scenario: No unsaved edits
- **WHEN** the editor is open with no unsaved edits and the file is changed over ssh
- **THEN** the editor shows the new file content within 1 second

#### Scenario: Keep the draft
- **WHEN** the draft has unsaved edits, the file changes on disk, and the user chooses to keep the draft
- **THEN** the draft and the deck are unchanged, and the next save shows the overwrite warning

#### Scenario: Invalid file on disk
- **WHEN** the file on disk changes to invalid YAML while the editor is open
- **THEN** the editor keeps its draft and shows that the file on disk has errors

### Requirement: Problems in the browser
The editor SHALL list the daemon's current problems, with the same text the daemon logs, and SHALL update the list when problems appear or clear.

#### Scenario: Missing keystroke permission
- **WHEN** the daemon can't create its virtual keyboard
- **THEN** the editor lists the problem with the udev message

#### Scenario: Failed action
- **WHEN** a key with `run: "false"` is pressed while no editor tab is visible
- **THEN** the editor lists that key's failure

### Requirement: Record a keystroke in the browser
After the user clicks the Keys field, the next key pressed with any held modifiers SHALL become the action's value, as config text. Modifiers SHALL be written in the order `cmd`, `ctrl`, `alt`, `shift`. A letter, digit or punctuation key SHALL be recorded as the character it types without modifiers on the browser's keyboard layout. The Meta or Windows key SHALL be recorded as `cmd`.

#### Scenario: Record a combination
- **WHEN** the user clicks the keys field of key 3 and presses Ctrl-Shift-M
- **THEN** key 3's action is `keys: ctrl+shift+m` and recording stops

#### Scenario: Named key
- **WHEN** the user records Ctrl-Alt-Left Arrow
- **THEN** the action is `keys: ctrl+alt+left`

#### Scenario: German layout
- **WHEN** the browser's machine uses a German layout and the user presses Ctrl and the key labeled Z
- **THEN** the action is `keys: ctrl+z`

#### Scenario: Shifted digit
- **WHEN** the user records Shift-1 on a US layout
- **THEN** the action is `keys: shift+1`

### Requirement: Stop or reject a browser recording
Esc SHALL cancel recording and keep the previous value. Clicking elsewhere SHALL stop recording without changing the value. A key with no name in the config format SHALL show a message and keep recording. The user SHALL be able to clear the value or type it as text, which is the way to enter `fn` and combinations the browser does not pass to pages.

#### Scenario: Cancel with Esc
- **WHEN** key 3 has `keys: ctrl+c`, the user starts recording and presses Esc
- **THEN** key 3 keeps `keys: ctrl+c` and recording stops

#### Scenario: Unsupported key
- **WHEN** the user is recording and presses keypad 5
- **THEN** the field says the key is not supported, the value is unchanged, and the next supported key is recorded

#### Scenario: Type a combination
- **WHEN** the user switches the field to text and types `fn+f`
- **THEN** key 3's action is `keys: fn+f`

### Requirement: Material Symbols picker
The icon field SHALL offer a picker that shows every Material Symbol the daemon can draw, drawn in the browser, searchable by name, with the name available for each. Choosing one SHALL set the icon to `ms:<name>`, or `ms:<name>.fill` when the filled style is on.

#### Scenario: Search and choose
- **WHEN** the user opens the picker for key 4, searches `home`, turns on Filled and clicks `home`
- **THEN** key 4's icon is `ms:home.fill` and the picker closes

#### Scenario: Unknown typed name
- **WHEN** the user types `hoem` as the Material Symbol name
- **THEN** the inspector marks the name as unknown, and the grid shows the placeholder for that key
