# Spec Delta

## Purpose

Defines where the YAML configuration lives, what it may contain, how it is validated, and how changes to it take effect while the app runs.

## ADDED Requirements

### Requirement: Config file location
The system SHALL read its configuration from `~/.config/streamdeck/config.yaml`. Relative file paths inside the configuration SHALL resolve against the directory containing that file.

#### Scenario: Relative icon path
- **WHEN** a key sets `icon: icons/zoom.png`
- **THEN** the system loads `~/.config/streamdeck/icons/zoom.png`

### Requirement: Starter config
The system SHALL create a starter configuration with one page and example keys when no config file exists at startup.

#### Scenario: First launch
- **WHEN** the app starts and `~/.config/streamdeck/config.yaml` does not exist
- **THEN** the file is created, it passes validation, and the device shows its example page

### Requirement: Config structure
The config SHALL contain an optional `brightness` (0-100, default 70), a required `default_page`, a required `pages` map of page name to page, and an optional `app_pages` map of application bundle ID to page name. A page has a `keys` map from key index (0-14) to key definition.

#### Scenario: Minimal valid config
- **WHEN** the config has `default_page: home` and a `home` page with one key
- **THEN** the config loads, and every undefined key on that page is blank

#### Scenario: Key index out of range
- **WHEN** a page defines key `15`
- **THEN** validation fails with an error that names the page and the key index

### Requirement: Key definition
A key definition SHALL allow `icon`, `label`, `background`, `action`, and `dynamic`, all optional. `icon` is an SF Symbol written as `sf:<name>` or an image file path. `background` is a hex color `#RRGGBB`. `dynamic` holds `run` (shell command) and `every` (duration such as `5s`, `1m`, minimum `1s`).

#### Scenario: Unknown field
- **WHEN** a key definition contains a field that is not one of the allowed fields
- **THEN** validation fails with an error that names the field, page, and key

#### Scenario: Interval too short
- **WHEN** a dynamic key sets `every: 200ms`
- **THEN** validation fails with an error that states the 1 second minimum

### Requirement: Reference validation
Validation SHALL fail when `default_page`, a `page` action, or an `app_pages` entry names a page that does not exist.

#### Scenario: Unknown page referenced
- **WHEN** a key's action is `page: media` and no page `media` exists
- **THEN** validation fails with an error that names the missing page and where it is referenced

### Requirement: Live reload
The system SHALL reload the config within 1 second of the file being saved. A config that fails to parse or validate SHALL NOT be applied. The last valid config stays active, and the error is shown in the menu bar.

#### Scenario: Valid edit
- **WHEN** the user changes a key label and saves the file
- **THEN** the device shows the new label within 1 second, without restarting the app

#### Scenario: Broken edit
- **WHEN** the user saves the file with invalid YAML
- **THEN** the device keeps showing the previous config, and the menu bar shows the parse error with its line number

#### Scenario: Current page removed
- **WHEN** a reload removes the page currently shown
- **THEN** the device switches to the frontmost application's mapped page, or to `default_page` when that application has no mapping (see page-navigation, Initial page)

#### Scenario: Atomic save by editor
- **WHEN** an editor saves by writing a temporary file and renaming it over the config
- **THEN** the change is detected and reloaded like a direct write
