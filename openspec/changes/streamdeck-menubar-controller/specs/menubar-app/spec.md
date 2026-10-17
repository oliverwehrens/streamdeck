# Spec Delta

## Purpose

Gives the controller a menu-bar presence for status, config access, error reporting, permissions, and launching at login, without a Dock icon or main window.

## ADDED Requirements

### Requirement: Menu-bar only
The app SHALL run as a menu-bar item with no Dock icon and no main window.

#### Scenario: App launched
- **WHEN** the app starts
- **THEN** an icon appears in the menu bar and no Dock icon or window appears

### Requirement: Status display
The menu SHALL show whether the device is connected, the current page name, and whether automatic page switching is on. The menu-bar icon SHALL show a distinct state when the device is disconnected or an error is active.

#### Scenario: Device connected
- **WHEN** the user opens the menu with the device connected on page `home`
- **THEN** the menu shows "Connected" and the page `home`

#### Scenario: Device disconnected
- **WHEN** the device is unplugged
- **THEN** the menu-bar icon changes to its disconnected state

### Requirement: Config commands
The menu SHALL offer "Open Config" (opens the config file in the default editor), "Reveal Config in Finder", and "Reload Config".

#### Scenario: Open config
- **WHEN** the user chooses "Open Config"
- **THEN** `~/.config/streamdeck/config.yaml` opens in the default editor for YAML files

#### Scenario: Manual reload
- **WHEN** the user chooses "Reload Config"
- **THEN** the config is reloaded with the same validation rules as a live reload

### Requirement: Error list
The menu SHALL list current problems: config errors, missing icons, failed commands, missing permissions, and device open failures. Each entry SHALL say what failed and where. An entry SHALL disappear when the problem is resolved.

#### Scenario: Config error shown
- **WHEN** the config fails validation
- **THEN** the menu lists the error with the file line or the page and key it refers to

#### Scenario: Error resolved
- **WHEN** the user fixes the config and it reloads successfully
- **THEN** the config error disappears from the menu

### Requirement: Brightness control in menu
The menu SHALL offer a brightness control that changes the device brightness immediately for the running session. The config value applies again on the next reload or launch.

#### Scenario: Brightness adjusted
- **WHEN** the user moves the brightness control to 20 percent
- **THEN** the device dims to 20 percent immediately

### Requirement: Launch at login
The menu SHALL offer a "Launch at Login" toggle that registers or unregisters the app as a login item.

#### Scenario: Enable launch at login
- **WHEN** the user enables "Launch at Login" and logs out and back in
- **THEN** the app is running and the device shows its page

### Requirement: Quit clears device
On quit, the system SHALL blank all keys and release the device.

#### Scenario: Quit
- **WHEN** the user chooses "Quit"
- **THEN** all keys go dark and the app exits
