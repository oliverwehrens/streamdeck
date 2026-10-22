# Spec Delta

## MODIFIED Requirements

### Requirement: Key definition
A key definition SHALL allow `icon`, `image`, `label`, `background`, `action`, and `dynamic`, all optional. `icon` is an SF Symbol written as `sf:<name>` or an image file path. `image` is an image file path; a value starting with `sf:` SHALL fail validation. `background` is a hex color `#RRGGBB`. `dynamic` holds `run` (shell command) and `every` (duration such as `5s`, `1m`, minimum `1s`).

#### Scenario: Unknown field
- **WHEN** a key definition contains a field that is not one of the allowed fields
- **THEN** validation fails with an error that names the field, page, and key

#### Scenario: Interval too short
- **WHEN** a dynamic key sets `every: 200ms`
- **THEN** validation fails with an error that states the 1 second minimum

#### Scenario: Relative image path
- **WHEN** a key sets `image: art/cat.jpg`
- **THEN** the system loads `~/.config/streamdeck/art/cat.jpg`

#### Scenario: Symbol as image
- **WHEN** a key sets `image: sf:star.fill`
- **THEN** validation fails with an error that names the page and key and says SF Symbols belong in `icon`
