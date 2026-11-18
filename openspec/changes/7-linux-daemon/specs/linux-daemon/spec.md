# Spec Delta

## Purpose

Runs the Stream Deck headless on Linux, for example on a Steam Machine in SteamOS Game Mode. It covers how the service starts and stops, how problems reach the user without a screen, and how it is installed.

## ADDED Requirements

### Requirement: Headless service
On Linux the system SHALL run as `streamdeckd`, a program with no window or tray icon. It SHALL use `~/.config/streamdeck/config.yaml` with the same format, validation and live reload as the macOS app.

#### Scenario: Started without a device
- **WHEN** `streamdeckd` starts with no deck attached
- **THEN** it keeps running, and when the deck is attached it shows the default page

#### Scenario: Config edited over ssh
- **WHEN** the user changes a key label in `config.yaml` over ssh and saves
- **THEN** the deck shows the new label within 1 second

### Requirement: Shutdown clears the device
On SIGTERM or SIGINT the system SHALL blank all keys, release the device and exit with status 0.

#### Scenario: Service stopped
- **WHEN** the user runs `systemctl --user stop streamdeckd`
- **THEN** all keys go dark and the process exits

### Requirement: Problems logged
The system SHALL write a line to standard error when a problem appears and when it clears. Each line names what failed and where, with the same text the macOS menu shows. When the system runs as a systemd service, these lines go to the journal.

#### Scenario: Config error logged
- **WHEN** the user saves `config.yaml` with a key index of 15
- **THEN** `journalctl --user -u streamdeckd` shows the validation error with the page and key

#### Scenario: Problem cleared
- **WHEN** the user fixes the config and saves it
- **THEN** the journal shows that the config error is resolved

### Requirement: Key problems on the deck
On Linux, a key SHALL show the error indicator while it has a problem. That covers its last action failing, an icon or image it cannot draw, and its dynamic command failing. The indicator SHALL go away when the problem clears.

#### Scenario: Failed command
- **WHEN** the user presses a key with `run: "false"`
- **THEN** that key shows the error indicator until a later press of that key succeeds or the config reloads

#### Scenario: Missing image
- **WHEN** a key sets `icon: icons/missing.png` and that file does not exist
- **THEN** the key shows the missing-icon placeholder and the error indicator

### Requirement: Status key
On Linux, while there is a problem that no visible key shows, key 14 SHALL show a status key instead of its configured content. The status key SHALL have a red background, a warning icon, and a short label for the problem, or the number of problems if there are several. Pressing it SHALL log every current problem again and run no action. When those problems clear, key 14 SHALL show its configured content again.

#### Scenario: Config fails at startup
- **WHEN** `streamdeckd` starts and `config.yaml` has invalid YAML
- **THEN** keys 0-13 are blank and key 14 shows the status key labeled `Config`

#### Scenario: Broken edit keeps the last config
- **WHEN** a valid config is showing and the user saves invalid YAML
- **THEN** keys 0-13 keep the last valid config and key 14 shows the status key

#### Scenario: Several problems
- **WHEN** the config fails to load and keystroke actions are unavailable
- **THEN** the status key's label is `2 problems`

#### Scenario: Problem fixed
- **WHEN** the config error is the only problem and the user saves a valid config
- **THEN** key 14 shows its configured key again

### Requirement: Single static binary
The Linux build SHALL be a single executable that runs on x86_64 Linux without any shared libraries. Fonts and icons SHALL be built in.

#### Scenario: Runs on SteamOS
- **WHEN** the binary is copied to a SteamOS machine that has no Swift runtime installed
- **THEN** it starts and drives the deck

### Requirement: User service installation
An install script SHALL put the binary in `~/.local/bin`, install and enable a systemd user unit that starts `streamdeckd` at login and restarts it after a crash, and install udev rules that give the logged-in user access to the deck and to `/dev/uinput`. Only the udev rules step SHALL need root.

#### Scenario: Fresh install
- **WHEN** the user runs the install script on a Steam Machine and enters the sudo password once
- **THEN** the deck shows its page without a reboot, and again after the next reboot

#### Scenario: Crash recovery
- **WHEN** `streamdeckd` is killed with SIGKILL
- **THEN** systemd starts it again within 5 seconds

#### Scenario: SteamOS update
- **WHEN** SteamOS installs a system update and reboots
- **THEN** the deck still works without reinstalling
