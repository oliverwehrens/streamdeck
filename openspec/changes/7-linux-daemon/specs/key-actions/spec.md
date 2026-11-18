# Spec Delta

## MODIFIED Requirements

### Requirement: Keystroke action
`keys: <combo>` SHALL send the key combination to the frontmost application. A combo is modifiers (`cmd`, `shift`, `alt`, `ctrl`, `fn`) and one key joined by `+`, for example `cmd+shift+m`. `super` and `meta` SHALL be accepted as aliases for `cmd`. Key names cover letters, digits, `f1`-`f20`, and named keys such as `space`, `return`, `tab`, `esc`, `left`.

#### Scenario: Shortcut sent
- **WHEN** a key with `keys: cmd+space` is pressed
- **THEN** the frontmost app receives Command-Space as if typed on the keyboard

#### Scenario: Unknown key name
- **WHEN** a key sets `keys: cmd+banana`
- **THEN** config validation fails with an error that names the unknown key

#### Scenario: Super alias
- **WHEN** a key sets `keys: super+l`
- **THEN** the config loads, and the combo is the same as `cmd+l`

## ADDED Requirements

### Requirement: Keystrokes on Linux
On Linux, `keys` and `media` actions SHALL be sent as a virtual keyboard to the focused window, including a game running under gamescope. `cmd` SHALL send Super (the Windows/Steam logo key). `alt`, `ctrl` and `shift` SHALL send the left key of that name.

#### Scenario: Key reaches a game
- **WHEN** a game is running in SteamOS Game Mode and a key with `keys: f5` is pressed
- **THEN** the game receives F5 as if typed on a USB keyboard

#### Scenario: Super combo
- **WHEN** a key with `keys: cmd+d` is pressed on a Linux desktop
- **THEN** the focused window receives Super-D

### Requirement: Fn key on Linux
On Linux a combo containing `fn` SHALL NOT be sent. The config SHALL still load. Pressing the key SHALL report that `fn` has no Linux equivalent, naming the page and key.

#### Scenario: Shared config with fn
- **WHEN** the config has a key with `keys: fn+f` and `streamdeckd` loads it
- **THEN** the config loads, and the other keys work

#### Scenario: Fn key pressed
- **WHEN** that key is pressed on Linux
- **THEN** no keystroke is sent and the key shows the error indicator, and the journal says `fn` has no Linux equivalent

### Requirement: Keyboard layout on Linux
On Linux, characters in a combo SHALL be sent as the key that types them without modifiers on the system's XKB layout and variant, read at each press. When that layout cannot type Latin letters, the system SHALL use the `us` layout. When it cannot tell which layout is active, it SHALL use `us`. Named keys SHALL be sent the same on every layout.

#### Scenario: Undo on a German layout
- **WHEN** the system keyboard layout is `de` and a key with `keys: ctrl+z` is pressed
- **THEN** the focused window receives Control and the key labeled Z on a German keyboard

#### Scenario: Character the layout cannot type
- **WHEN** the layout is `de` and a key with `keys: ctrl+[` is pressed
- **THEN** no keystroke is sent and the problem says the layout `de` has no key for `[`

#### Scenario: Non-Latin layout
- **WHEN** the layout is `ru` and a key with `keys: ctrl+c` is pressed
- **THEN** the system sends Control and the key labeled C on the `us` layout

### Requirement: Keystroke permission on Linux
On Linux, when the virtual keyboard cannot be created, `keys` and `media` actions SHALL NOT send anything. The system SHALL report one problem that says `/dev/uinput` is not accessible and that the udev rules need installing. Other action types SHALL keep working.

#### Scenario: uinput not accessible
- **WHEN** `/dev/uinput` is not writable for the user and a keystroke key is pressed
- **THEN** nothing is sent, the status key shows the problem, and the journal says to install the udev rules

### Requirement: Media keys on Linux
On Linux, each `media` name SHALL send the matching standard media key: play/pause, next track, previous track, volume up, volume down, mute, brightness up, brightness down.

#### Scenario: Volume
- **WHEN** a key with `media: volumeup` is pressed in Game Mode
- **THEN** the system volume goes up, the same as the volume-up key on a USB keyboard

### Requirement: Open action on Linux
On Linux, an `open` target starting with `steam://` SHALL be passed to the Steam client. Any other URL, file or folder SHALL be opened with `xdg-open`. A target that is not a URL and does not exist SHALL fail with the same message as on macOS.

#### Scenario: Launch a game
- **WHEN** Steam is running and a key with `open: steam://rungameid/570` is pressed
- **THEN** Steam starts the game with AppID 570

#### Scenario: Open a web page
- **WHEN** a key with `open: https://example.com` is pressed on a Linux desktop
- **THEN** the default browser opens the URL

#### Scenario: Missing file
- **WHEN** a key with `open: ~/nothing-here.txt` is pressed and the file does not exist
- **THEN** the key reports `cannot open '~/nothing-here.txt': no such file`
