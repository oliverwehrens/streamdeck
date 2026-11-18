# Spec Delta

## MODIFIED Requirements

### Requirement: Starter config
The system SHALL create a starter configuration with one page and example keys when no config file exists at startup. On Linux the starter config SHALL use only Material Symbol icons and actions that work on Linux.

#### Scenario: First launch
- **WHEN** the app starts and `~/.config/streamdeck/config.yaml` does not exist
- **THEN** the file is created, it passes validation, and the device shows its example page

#### Scenario: First launch on Linux
- **WHEN** `streamdeckd` starts and `~/.config/streamdeck/config.yaml` does not exist
- **THEN** the file is created, every icon in it draws without a problem, and no key uses `sf:` icons, macOS applications or `fn`
