# Proposal

## Why

The Stream Deck (Original V2, 15 keys) only does something useful while Elgato's software runs, and that software is closed and heavyweight. A small native macOS menu-bar app that talks to the device over USB HID and reads a plain YAML file removes the dependency and puts the configuration under version control.

## What Changes

- New macOS menu-bar app (Swift) that opens the Stream Deck Original V2 (VID `0x0fd9`, PID `0x006d`) directly over USB HID. It replaces the Elgato app; the two cannot run at the same time.
- Reads key layout, pages, and actions from a YAML file and reloads it on change.
- Renders each key from an icon (SF Symbol or image file) and/or a text label.
- Dynamic keys: a shell command runs on an interval, and its output becomes the key's label.
- Actions fire on key-down: run shell command, open app/file/URL, send keystroke, send media key, switch page.
- Pages: manual navigation (go to page, back) and automatic switching by frontmost application.
- Handles device hot-plug and system sleep/wake.
- Out of scope for this change: long-press, double-press, hold-to-repeat, HTTP actions, app-specific integrations (OBS, Home Assistant), other Stream Deck models, a GUI config editor.

## Capabilities

### New Capabilities

- `deck-device`: Discovering, connecting to, and exchanging input/output with the Stream Deck Original V2, including brightness, hot-plug, and sleep/wake recovery.
- `deck-config`: The YAML configuration format, its validation, its location, and live reload.
- `key-rendering`: How a key's visual (icon, label, background, dynamic output) is produced and shown on the device.
- `key-actions`: What happens when a key is pressed, for each supported action type.
- `page-navigation`: Which page is shown, manual navigation between pages, and automatic switching by frontmost app.
- `menubar-app`: The menu-bar presence: status, reload, opening the config, error reporting, permissions, and launch at login.

### Modified Capabilities

None. The project has no existing specs.

## Impact

- New Swift package / Xcode app target in this repository (greenfield).
- Dependency: Yams (YAML parsing). Everything else uses Apple frameworks (IOKit HID, CoreGraphics, CoreText, ImageIO, AppKit).
- System permissions: Accessibility (for synthesized keystrokes). Input Monitoring should not be required for this vendor-defined HID device; this is verified early.
- The Elgato Stream Deck app must not run at the same time.
