# Spec Delta

## Purpose

Determines what each key on the device looks like, from static icons and labels to labels driven by the output of a periodically run command.

## ADDED Requirements

### Requirement: Static key appearance
The system SHALL draw each key from its definition: `background` color (default black), then `icon` centered, then `label` in white text. With both icon and label, the icon sits above the label. With only a label, the label is centered.

#### Scenario: Icon and label
- **WHEN** a key has `icon: sf:play.fill` and `label: Play`
- **THEN** the key shows the play symbol above the text "Play"

#### Scenario: Label only
- **WHEN** a key has only `label: Build`
- **THEN** the key shows "Build" centered on a black background

#### Scenario: Undefined key
- **WHEN** a page does not define key 9
- **THEN** key 9 is black

### Requirement: Image icons
The system SHALL accept PNG and JPEG icon files and scale them to fit the key, keeping their aspect ratio.

#### Scenario: Non-square image
- **WHEN** an icon file is 200x100 pixels
- **THEN** it is scaled to fit inside the key without distortion

### Requirement: Long labels
The system SHALL fit labels to the key: reduce the font size down to a minimum, wrap to at most two lines, and truncate with an ellipsis if it still does not fit.

#### Scenario: Label too long
- **WHEN** a key label is "Deploy production environment"
- **THEN** the key shows at most two lines, ending in an ellipsis, with no text outside the key

### Requirement: Missing icon placeholder
The system SHALL draw a visible placeholder when an icon file or SF Symbol cannot be found, and report the problem in the menu bar. Other keys are unaffected.

#### Scenario: Missing file
- **WHEN** a key references `icons/missing.png` and the file does not exist
- **THEN** the key shows a placeholder mark with its label, and the menu bar lists the missing file

### Requirement: Dynamic keys
For a key with `dynamic`, the system SHALL run `run` through the user's shell every `every` interval while the key's page is shown. The first line of standard output, trimmed, replaces the key's `label`. Runs SHALL NOT overlap for the same key.

#### Scenario: Clock key
- **WHEN** a key has `dynamic: { run: "date +%H:%M", every: 30s }` on the current page
- **THEN** the key shows the current time and updates at least every 30 seconds

#### Scenario: Page not shown
- **WHEN** the page containing a dynamic key is not the current page
- **THEN** the key's command is not run

#### Scenario: Slow command
- **WHEN** a dynamic command takes longer than its interval
- **THEN** the next run starts only after the previous one finishes

### Requirement: Dynamic key failure
When a dynamic command exits non-zero or runs longer than 10 seconds, the system SHALL stop that run, keep the last successful label, and mark the key as failed with an error indicator.

#### Scenario: Command fails
- **WHEN** the dynamic command exits with status 1
- **THEN** the key keeps its previous label and shows an error indicator until a later run succeeds

#### Scenario: Command hangs
- **WHEN** the dynamic command is still running after 10 seconds
- **THEN** it is terminated and the key shows the error indicator

### Requirement: Press feedback
The system SHALL briefly darken a key while it is held down, for keys that have an action.

#### Scenario: Key held
- **WHEN** the user holds down a key that has an action
- **THEN** the key appears darkened until it is released
