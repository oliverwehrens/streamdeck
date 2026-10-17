# Spec Delta

## Purpose

Defines what happens when a key is pressed, for each supported action type: shell commands, opening things, keystrokes, media keys, and page switches.

## ADDED Requirements

### Requirement: Trigger on key-down
The system SHALL run a key's action once when the key goes down. Releasing the key SHALL NOT trigger anything. A key without an action does nothing.

#### Scenario: Press
- **WHEN** the user presses a key with an action
- **THEN** the action runs once, at the moment of key-down

#### Scenario: Key held
- **WHEN** the user holds a key down for several seconds
- **THEN** the action has run exactly once

### Requirement: One action per key
A key definition SHALL hold at most one action, written as exactly one of `run`, `open`, `keys`, `media`, or `page`.

#### Scenario: Two action types on one key
- **WHEN** a key's action contains both `run` and `open`
- **THEN** config validation fails with an error that names the page and key

### Requirement: Shell command action
`run: <command>` SHALL execute the command through the user's login shell in the background. The app SHALL stay responsive while the command runs. A non-zero exit SHALL be reported in the menu bar with the command's standard error.

#### Scenario: Command runs
- **WHEN** a key with `run: "say hello"` is pressed
- **THEN** the Mac speaks "hello" and other keys stay responsive meanwhile

#### Scenario: Command fails
- **WHEN** a key with `run: "false"` is pressed
- **THEN** the menu bar shows that the command failed with its exit status

### Requirement: Open action
`open: <target>` SHALL open a URL, file, folder, or application the same way Finder or the `open` command would.

#### Scenario: Open URL
- **WHEN** a key with `open: https://example.com` is pressed
- **THEN** the default browser opens the URL

#### Scenario: Open application
- **WHEN** a key with `open: /Applications/Safari.app` is pressed
- **THEN** Safari launches or comes to the front

### Requirement: Keystroke action
`keys: <combo>` SHALL send the key combination to the frontmost application. A combo is modifiers (`cmd`, `shift`, `alt`, `ctrl`, `fn`) and one key joined by `+`, for example `cmd+shift+m`. Key names cover letters, digits, `f1`-`f20`, and named keys such as `space`, `return`, `tab`, `esc`, `left`.

#### Scenario: Shortcut sent
- **WHEN** a key with `keys: cmd+space` is pressed
- **THEN** the frontmost app receives Command-Space as if typed on the keyboard

#### Scenario: Unknown key name
- **WHEN** a key sets `keys: cmd+banana`
- **THEN** config validation fails with an error that names the unknown key

### Requirement: Accessibility permission
When a keystroke or media key action runs without the Accessibility permission, the system SHALL NOT send the event and SHALL tell the user how to grant the permission.

#### Scenario: Permission missing
- **WHEN** a keystroke key is pressed and the app lacks Accessibility permission
- **THEN** no keystroke is sent and the menu bar shows a prompt that opens the Accessibility settings

#### Scenario: Media key without permission
- **WHEN** a media key is pressed and the app lacks Accessibility permission
- **THEN** no media event is sent and the same prompt is shown

### Requirement: Media key action
`media: <name>` SHALL send a system media key. Supported names: `playpause`, `next`, `previous`, `volumeup`, `volumedown`, `mute`, `brightnessup`, `brightnessdown`.

#### Scenario: Play/pause
- **WHEN** a key with `media: playpause` is pressed while Music is playing
- **THEN** playback pauses, the same as pressing the keyboard's play/pause key

### Requirement: Page action
`page: <name>` SHALL switch to the named page. `page: back` SHALL return to the previous page in the navigation history (see page-navigation).

#### Scenario: Switch page
- **WHEN** a key with `page: media` is pressed
- **THEN** the device shows the `media` page
