# Spec Delta

## ADDED Requirements

### Requirement: Device access on Linux
On Linux the system SHALL reach the device through its hidraw node. It SHALL NOT need root or any running helper. When it finds the device but cannot open it, it SHALL report the problem with the device node and the reason, and say whether the udev rules are missing.

#### Scenario: Rules installed
- **WHEN** the udev rules are installed and the user is logged in on the machine's seat
- **THEN** `streamdeckd` opens the deck and shows the current page

#### Scenario: Rules missing
- **WHEN** the udev rules are not installed and the deck is attached
- **THEN** the journal says the deck's hidraw node cannot be opened (permission denied) and that the udev rules need installing

### Requirement: Hot-plug on Linux
On Linux the system SHALL detect the device being attached or detached while it runs, within 2 seconds, with the same outcome as on macOS: it restores brightness and redraws the current page on attach.

#### Scenario: Replugged
- **WHEN** the deck is unplugged and plugged back in while `streamdeckd` runs
- **THEN** within 2 seconds the deck shows the page that was active before, at the configured brightness

### Requirement: Resume on Linux
On Linux the system SHALL redraw the current page and restore brightness after the machine resumes from suspend.

#### Scenario: Steam Machine resumes
- **WHEN** the Steam Machine resumes from suspend with the deck attached
- **THEN** within 5 seconds the deck shows the current page at the configured brightness

### Requirement: Coexistence with Steam
On SteamOS, Steam and Steam Input SHALL NOT take over the deck. Key presses SHALL reach only `streamdeckd`, and Steam SHALL NOT show the deck as a controller.

#### Scenario: Game Mode
- **WHEN** the deck is attached in Game Mode and the user presses a key
- **THEN** only the key's configured action happens, and Steam reacts to nothing other than that action
