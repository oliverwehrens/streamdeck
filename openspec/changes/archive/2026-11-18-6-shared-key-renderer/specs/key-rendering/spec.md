# Spec Delta

## MODIFIED Requirements

### Requirement: Static key appearance
The system SHALL draw each key from its definition in layers: `background` color (default black), then `image` across the whole key, then `icon` centered, then `label` in white text. With both icon and label, the icon sits above the label. With only a label, the label is centered. When the key has an image, the label SHALL have a drop shadow. Symbol icons (`ms:` and `sf:`) SHALL be drawn in white.

#### Scenario: Icon and label
- **WHEN** a key has `icon: sf:play.fill` and `label: Play`
- **THEN** the key shows the play symbol above the text "Play"

#### Scenario: Material Symbol and label
- **WHEN** a key has `icon: ms:play_arrow.fill` and `label: Play`
- **THEN** the key shows the filled Material Symbols play arrow in white above the text "Play"

#### Scenario: Label only
- **WHEN** a key has only `label: Build`
- **THEN** the key shows "Build" centered on a black background

#### Scenario: Undefined key
- **WHEN** a page does not define key 9
- **THEN** key 9 is black

#### Scenario: Image with icon and label
- **WHEN** a key has `image: art/tile.png`, `icon: sf:play.fill` and `label: Play`
- **THEN** the image covers the whole key, the play symbol is drawn on top of it above the text "Play", and the label has a drop shadow

#### Scenario: No image, no shadow
- **WHEN** a key has `label: Build` and no image
- **THEN** the label is drawn without a shadow

### Requirement: Missing icon placeholder
The system SHALL draw a visible placeholder when an icon file, SF Symbol or Material Symbol cannot be found, and report the problem in the menu bar (on macOS) or the daemon's problem list (on Linux). Other keys are unaffected.

#### Scenario: Missing file
- **WHEN** a key references `icons/missing.png` and the file does not exist
- **THEN** the key shows a placeholder mark with its label, and the menu bar lists the missing file

#### Scenario: Unknown Material Symbol
- **WHEN** a key has `icon: ms:no_such_symbol`
- **THEN** the key shows the placeholder mark, and the problem names the unknown Material Symbol

#### Scenario: SF Symbol on Linux
- **WHEN** the system runs on Linux and a key has `icon: sf:play.fill` and `label: Play`
- **THEN** the key shows the placeholder mark above "Play", and the problem says SF Symbols are only available on macOS and suggests an `ms:` icon

### Requirement: Dynamic key icon values
The `icon` field in JSON output SHALL accept the same forms as the config: `ms:<name>` or `ms:<name>.fill` for a Material Symbol, `sf:<name>` for an SF Symbol, or an image file path. A path starting with `~` expands to the home directory. A relative path resolves against the config file's directory. An icon that cannot be loaded SHALL be shown and reported like a missing configured icon.

#### Scenario: Relative image path
- **WHEN** the config lives in `~/.config/streamdeck/` and a dynamic command prints `{"icon":"icons/on.png"}`
- **THEN** the key shows the image `~/.config/streamdeck/icons/on.png`

#### Scenario: Unknown symbol
- **WHEN** a dynamic command prints `{"icon":"sf:no.such.symbol"}`
- **THEN** the key shows the placeholder mark, and the menu bar reports the unknown symbol

#### Scenario: Material Symbol from a script
- **WHEN** a dynamic command prints `{"icon":"ms:lightbulb.fill","label":"on"}`
- **THEN** the key shows the filled Material Symbols light bulb above the label `on`

## ADDED Requirements

### Requirement: Same rendering on every platform
The system SHALL draw keys with the same bundled fonts and the same layout rules on macOS and Linux. For a key without `sf:` icons, the image sent to the device on Linux SHALL match the one on macOS, apart from JPEG encoder noise. Rendering SHALL NOT depend on fonts or graphics libraries installed on the system.

#### Scenario: Shared config
- **WHEN** the same config with `icon: ms:home` and `label: Home` is used on a Mac and on a Steam Machine
- **THEN** the key looks the same on both decks

#### Scenario: No system fonts
- **WHEN** the system runs on a Linux machine with no fonts installed
- **THEN** labels and Material Symbols are drawn normally

### Requirement: Label characters outside the font
Characters in a label that the bundled text font does not contain SHALL be drawn as a fallback mark, without affecting the rest of the label or other keys.

#### Scenario: Emoji in a label
- **WHEN** a key has `label: "Party 🎉"`
- **THEN** the key shows "Party" followed by a fallback mark, and no other key changes
