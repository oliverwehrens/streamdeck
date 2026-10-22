# Spec Delta

## MODIFIED Requirements

### Requirement: Key editing
The inspector SHALL edit every key field: icon (SF Symbol name or image file), image (image file), label, background color, action (one of run, open, keys, media, page) and dynamic (command and interval). The user SHALL be able to clear a key so it is undefined.

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

#### Scenario: Pick a full-key image
- **WHEN** the user picks `~/.config/streamdeck/art/cat.jpg` for key 2's image
- **THEN** the draft has key 2 with `image: art/cat.jpg`, and the grid and the device show it across the whole key

#### Scenario: Remove a full-key image
- **WHEN** key 2 has an image and the user removes it in the inspector
- **THEN** the draft has key 2 without `image`

## ADDED Requirements

### Requirement: Record a keystroke
The Keystroke action's keys field SHALL record a combination: after the user clicks it, the next key pressed with any held modifiers SHALL become the action's value, written as config text that loads to the same combination. A letter, digit or punctuation key SHALL be recorded as the character it types without modifiers on the active layout. Modifiers SHALL be written in the order `cmd`, `ctrl`, `alt`, `shift`, `fn`. While recording, key presses SHALL NOT trigger editor shortcuts.

#### Scenario: Record a combination
- **WHEN** the user clicks the keys field of key 3 and presses Cmd-Shift-M
- **THEN** key 3's action is `keys: cmd+shift+m` and recording stops

#### Scenario: Record a named key
- **WHEN** the user records Ctrl-Option-Left Arrow
- **THEN** the action is `keys: ctrl+alt+left`

#### Scenario: Record on a German layout
- **WHEN** the German layout is active and the user presses Cmd and the key labeled Z
- **THEN** the action is `keys: cmd+z`

#### Scenario: Modifiers only
- **WHEN** the user is recording and presses and releases Cmd and Shift without another key
- **THEN** the field shows the held modifiers while they are down, the value is unchanged, and recording continues

#### Scenario: Editor shortcut while recording
- **WHEN** the user is recording and presses Cmd-S
- **THEN** the action is `keys: cmd+s` and the draft is not saved

#### Scenario: Round trip
- **WHEN** the user records any combination the field accepts
- **THEN** the recorded text, sent on the same layout, sends the same key code and modifiers

### Requirement: Stop recording
Esc SHALL cancel recording and keep the previous value. Clicking outside the field, selecting another key or the window losing focus SHALL stop recording without changing the value.

#### Scenario: Cancel with Esc
- **WHEN** key 3 has `keys: cmd+c`, the user starts recording and presses Esc
- **THEN** key 3 keeps `keys: cmd+c` and recording stops

#### Scenario: Click elsewhere
- **WHEN** the user is recording and clicks the label field
- **THEN** recording stops, the value is unchanged, and the label field receives the click

### Requirement: Unsupported recorded key
When the user presses a key that has no name in the config format, the field SHALL show a message naming the problem and SHALL keep the previous value. Recording SHALL continue.

#### Scenario: Keypad key
- **WHEN** the user is recording and presses keypad 5
- **THEN** the field says the key is not supported, the value is unchanged, and the next supported key press is recorded

#### Scenario: Letter without a config name
- **WHEN** the German layout is active and the user presses the key labeled Ö while recording
- **THEN** the field says the key is not supported and the value is unchanged

### Requirement: Function modifier in recordings
A recording SHALL include `fn` only when the user held the fn key. For F-keys, arrow keys, home, end, page up, page down and forward delete, the recording SHALL NOT include `fn`.

#### Scenario: F-key
- **WHEN** the user records F12 on a keyboard that sends fn with F-keys
- **THEN** the action is `keys: f12`

#### Scenario: Arrow key
- **WHEN** the user records Cmd-Up Arrow
- **THEN** the action is `keys: cmd+up`

#### Scenario: Held fn
- **WHEN** the user holds fn and presses J while recording
- **THEN** the action is `keys: fn+j`

### Requirement: Empty, clear and typed keystrokes
An empty keys field SHALL read "Click to record". The user SHALL be able to clear the value and to type it as text instead of recording it.

#### Scenario: New keystroke action
- **WHEN** the user sets key 3's action type to Keystroke
- **THEN** the keys field reads "Click to record" and the editor shows that key 3 has no combination

#### Scenario: Clear the value
- **WHEN** key 3 has `keys: cmd+c` and the user clicks the clear button
- **THEN** key 3's action value is empty and the field reads "Click to record"

#### Scenario: Type a combination
- **WHEN** the user switches the field to text and types `cmd+space`
- **THEN** key 3's action is `keys: cmd+space`
