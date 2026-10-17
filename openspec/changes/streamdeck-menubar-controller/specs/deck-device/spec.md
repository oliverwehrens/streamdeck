# Spec Delta

## Purpose

Connects to the Stream Deck Original V2 over USB HID, reports key state changes, writes key images and brightness, and keeps the connection alive across hot-plug and system sleep.

## ADDED Requirements

### Requirement: Supported device
The system SHALL support the Stream Deck Original V2 identified by USB vendor ID `0x0fd9` and product ID `0x006d`. Other Stream Deck models SHALL be ignored.

#### Scenario: Supported device connected
- **WHEN** a device with VID `0x0fd9` and PID `0x006d` is attached
- **THEN** the system opens it and reports it as connected, including its serial number and firmware version

#### Scenario: Unsupported model connected
- **WHEN** a Stream Deck with a different product ID is attached
- **THEN** the system does not open it and the device stays untouched

### Requirement: Key down and key up events
The system SHALL report a key-down event when a key changes from released to pressed and a key-up event when it changes from pressed to released, each with the key index 0-14. Keys are numbered left to right, top to bottom.

#### Scenario: Single key pressed and released
- **WHEN** the user presses and releases the top-left key
- **THEN** the system reports key-down for key 0, then key-up for key 0

#### Scenario: Two keys held together
- **WHEN** the user presses key 3 and, while holding it, presses key 7
- **THEN** the system reports key-down for key 3, then key-down for key 7, and no duplicate event for key 3

### Requirement: Key image output
The system SHALL display a 72x72 pixel image on any single key, upright as seen by the user, without changing the other keys.

#### Scenario: Image appears upright
- **WHEN** the system sends an image with an arrow pointing up to key 0
- **THEN** the top-left key shows the arrow pointing up

#### Scenario: Other keys unchanged
- **WHEN** the system updates key 5
- **THEN** keys other than 5 keep their current images

### Requirement: Brightness control
The system SHALL set the display brightness to a percentage from 0 to 100. Values outside that range SHALL be clamped.

#### Scenario: Brightness set
- **WHEN** brightness 30 is requested
- **THEN** the device display dims to 30 percent

#### Scenario: Out-of-range value
- **WHEN** brightness 150 is requested
- **THEN** the device brightness is set to 100

### Requirement: Hot-plug
The system SHALL detect when the device is attached or detached while running. On attach it SHALL restore brightness and redraw the current page.

#### Scenario: Device unplugged and replugged
- **WHEN** the device is unplugged and plugged back in while the app runs
- **THEN** the app shows the device as disconnected, then connected, and the device shows the page that was active before

#### Scenario: App started without device
- **WHEN** the app starts with no device attached and the device is attached later
- **THEN** the app connects and shows the current page without a restart

### Requirement: Sleep and wake recovery
The system SHALL redraw the current page and restore brightness after the Mac wakes from sleep.

#### Scenario: Wake from sleep
- **WHEN** the Mac wakes from sleep with the device attached
- **THEN** within 3 seconds the device shows the current page at the configured brightness

### Requirement: Exclusive use conflict
The system SHALL report an error when it cannot open the device, and name the Elgato Stream Deck app as the likely cause when that app is running.

#### Scenario: Elgato app running
- **WHEN** the Elgato Stream Deck app is running and the device cannot be opened
- **THEN** the menu bar shows an error that tells the user to quit the Elgato app
