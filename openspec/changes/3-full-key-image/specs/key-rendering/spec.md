# Spec Delta

## MODIFIED Requirements

### Requirement: Static key appearance
The system SHALL draw each key from its definition in layers: `background` color (default black), then `image` across the whole key, then `icon` centered, then `label` in white text. With both icon and label, the icon sits above the label. With only a label, the label is centered. When the key has an image, the label SHALL have a drop shadow.

#### Scenario: Icon and label
- **WHEN** a key has `icon: sf:play.fill` and `label: Play`
- **THEN** the key shows the play symbol above the text "Play"

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

### Requirement: Dynamic key JSON output
JSON output SHALL be one object with optional fields `label` (string), `icon` (string), `image` (string) and `background` (string `#RRGGBB`). Each present field replaces the key's configured value. Omitted fields keep the configured value. Unknown fields SHALL be ignored. An empty `label` hides the label. An empty `image` removes the image. Output that is not a JSON object, or a known field with the wrong type or an invalid color, SHALL be rejected.

#### Scenario: Script sets all fields
- **WHEN** a dynamic command prints `{"label":"on","icon":"sf:lightbulb.fill","background":"#c08000"}`
- **THEN** the key shows the `lightbulb.fill` symbol and the label `on` on a `#c08000` background

#### Scenario: Omitted field keeps configured value
- **WHEN** a key is configured with `icon: sf:bitcoinsign.circle` and `background: "#000000"`, and its command prints `{"label":"67250","background":"#802020"}`
- **THEN** the key shows the `bitcoinsign.circle` symbol and the label `67250` on a `#802020` background

#### Scenario: Unknown field
- **WHEN** a dynamic command prints `{"label":"ok","progress":0.5}`
- **THEN** the key shows the label `ok`, and no problem is reported

#### Scenario: Invalid color
- **WHEN** a dynamic command prints `{"background":"yellow"}`
- **THEN** the output is rejected as a failed run, and the menu names the invalid `background` value

#### Scenario: Plain text unchanged
- **WHEN** a dynamic command prints `12:34`
- **THEN** the key's label becomes `12:34`, and its icon and background stay as configured

#### Scenario: Script sets image
- **WHEN** a dynamic command prints `{"image":"/tmp/cover.jpg","label":"Song"}`
- **THEN** the image covers the whole key and the label `Song` is drawn on top with a drop shadow

#### Scenario: Script removes image
- **WHEN** a key is configured with `image: art/idle.png` and its command prints `{"image":""}`
- **THEN** the key is drawn without an image

#### Scenario: Image not a string
- **WHEN** a dynamic command prints `{"image":42}`
- **THEN** the output is rejected as a failed run, and the menu says `image` must be a string

## ADDED Requirements

### Requirement: Full-key image fill
The system SHALL accept PNG and JPEG files for `image` and scale each to cover the whole key while keeping its aspect ratio, cropping the overflow equally from both sides. Paths in dynamic JSON output follow the same rules as configured paths: `~` expands, and relative paths resolve against the config file's directory.

#### Scenario: Square image
- **WHEN** a key's image is 144x144 pixels
- **THEN** it covers the key with no border

#### Scenario: Wide image
- **WHEN** a key's image is 200x100 pixels
- **THEN** it is scaled to the key's height, the left and right edges are cropped equally, and it is not distorted

#### Scenario: Relative path in dynamic output
- **WHEN** the config lives in `~/.config/streamdeck/` and a dynamic command prints `{"image":"art/on.png"}`
- **THEN** the key shows `~/.config/streamdeck/art/on.png` across the whole key

### Requirement: Missing image
When an image file cannot be found or read, the system SHALL draw the key without the image (background, icon and label as defined) and report the file in the menu bar. Other keys are unaffected.

#### Scenario: Missing image file
- **WHEN** a key has `image: art/missing.png`, `label: Cat`, and the file does not exist
- **THEN** the key shows the label `Cat` on its background, and the menu bar lists the missing image file
