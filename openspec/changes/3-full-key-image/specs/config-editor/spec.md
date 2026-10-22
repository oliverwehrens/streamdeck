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
