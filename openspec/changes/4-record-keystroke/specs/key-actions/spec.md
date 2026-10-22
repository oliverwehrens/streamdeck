# Spec Delta

## ADDED Requirements

### Requirement: Keystroke characters follow the keyboard layout
Letters, digits and punctuation in a combo SHALL be sent as the key that types that character without modifiers on the keyboard layout active at the moment of the press. When the active layout cannot type Latin letters, the system SHALL use the Latin layout macOS uses for shortcuts. Named keys such as `return`, `esc`, `space`, `f12` and `left` SHALL be sent the same on every layout.

#### Scenario: Undo on a German layout
- **WHEN** the German layout is active and a key with `keys: cmd+z` is pressed
- **THEN** the frontmost app receives Command and the key labeled Z

#### Scenario: Layout switched
- **WHEN** the user switches from the US to the German layout between two presses of `keys: cmd+y`
- **THEN** each press sends the key labeled Y on the layout active at that moment

#### Scenario: Non-Latin layout
- **WHEN** the Russian layout is active, the last Latin layout was German, and `keys: cmd+z` is pressed
- **THEN** the system sends the key labeled Z on the German layout

#### Scenario: Named key
- **WHEN** any layout is active and `keys: cmd+left` is pressed
- **THEN** the frontmost app receives Command-Left Arrow

### Requirement: Keystroke character missing from the layout
When the active layout has no key that types the combo's character without modifiers, the system SHALL NOT send a keystroke and SHALL report in the menu bar which character the layout cannot type.

#### Scenario: Bracket on a German layout
- **WHEN** the German layout is active and a key with `keys: cmd+[` is pressed
- **THEN** no keystroke is sent and the menu bar says the German layout has no key for `[`
