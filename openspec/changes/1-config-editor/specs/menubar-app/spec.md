# Spec Delta

## MODIFIED Requirements

### Requirement: Menu-bar only
The app SHALL run as a menu-bar item with no Dock icon and no main window. While the config editor window is open, the app SHALL show a Dock icon and appear in the app switcher. When the editor window closes, the Dock icon SHALL disappear.

#### Scenario: App launched
- **WHEN** the app starts
- **THEN** an icon appears in the menu bar and no Dock icon or window appears

#### Scenario: Editor open
- **WHEN** the user opens the config editor
- **THEN** a Dock icon appears and the editor window can be reached with Cmd-Tab

#### Scenario: Editor closed
- **WHEN** the user closes the config editor
- **THEN** the Dock icon disappears and the menu-bar icon stays

### Requirement: Config commands
The menu SHALL offer "Edit Config…" (opens the config editor), "Open Config" (opens the config file in the default editor), "Reveal Config in Finder", and "Reload Config".

#### Scenario: Edit config
- **WHEN** the user chooses "Edit Config…"
- **THEN** the config editor window opens and comes to the front

#### Scenario: Open config
- **WHEN** the user chooses "Open Config"
- **THEN** `~/.config/streamdeck/config.yaml` opens in the default editor for YAML files

#### Scenario: Manual reload
- **WHEN** the user chooses "Reload Config"
- **THEN** the config is reloaded with the same validation rules as a live reload
