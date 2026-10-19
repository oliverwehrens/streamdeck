# Spec Delta

## MODIFIED Requirements

### Requirement: Live reload
The system SHALL reload the config within 1 second of the file being saved. A config that fails to parse or validate SHALL NOT be applied. The last valid config stays active, and the error is shown in the menu bar. While the config editor has unsaved changes, a reloaded file SHALL NOT replace what the device shows; the editor decides (see config-editor, External changes).

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

#### Scenario: Unsaved editor draft
- **WHEN** the config editor has unsaved changes and the file is saved in a text editor
- **THEN** the device keeps showing the editor's draft until the user chooses in the editor
