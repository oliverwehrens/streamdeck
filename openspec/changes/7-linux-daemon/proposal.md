Issue: #7

# Proposal

## Why

The shared core (#5) and the shared renderer (#6) build on Linux, but nothing drives a deck there yet. On a Steam Machine running SteamOS, the deck should work headless in Game Mode. It should launch games, send keys to the focused game, control media, and run scripts. It uses the same `config.yaml` as the Mac and you edit it over ssh until the web editor (#9) exists.

## What Changes

- New executable `streamdeckd`, built only on Linux. It runs the existing `DeckEngine` with Linux implementations of the transport, actions and keyboard layout. It reads `~/.config/streamdeck/config.yaml` and reloads it live, as the Mac app does. It has no UI. It blanks the deck and exits on SIGTERM or SIGINT.
- New `DeckPlatformLinux` target, the counterpart of `DeckPlatformMac`:
  - **hidraw transport**: finds the Stream Deck Original V2 (`0fd9:006d`) under `/sys/class/hidraw`, reads input reports, writes images with `write()`, and sets and gets feature reports with `HIDIOCSFEATURE` / `HIDIOCGFEATURE`. It handles hotplug by watching `/dev` with inotify, with no libudev. After a suspend it redraws.
  - **uinput keyboard**: one virtual keyboard device carries `keys` and `media` actions. `cmd` sends Super (`super` and `meta` are new aliases). `fn` has no Linux equivalent: the key reports a problem when pressed. The config still loads, so one config serves both machines.
  - **XKB keyboard layout**: characters map through the active XKB layout. The daemon reads the XKB symbol files itself in Swift, with no libxkbcommon. Non-Latin layouts fall back to `us`, and named keys go through a fixed evdev table.
  - **open**: `steam://` URLs go to the Steam client, everything else to `xdg-open`.
- Problems are shown on the deck. A key whose action, icon or dynamic command failed shows the error dot. Problems that belong to no visible key, such as a config error or a missing uinput permission, replace key 14 with a status key. Every problem is also logged to stderr, which systemd sends to the journal, when it appears and when it clears.
- The Linux starter config uses Material Symbols and Linux actions instead of SF Symbols and macOS apps.
- Packaging: a fully static x86_64 binary built with the Swift Static Linux SDK (musl) in Docker. An install script puts it in `~/.local/bin` with a systemd user unit, plus udev rules for hidraw and uinput that are installed once with sudo.
- Hardware verification on a Steam Machine: Steam Input leaves the device alone, gamescope delivers uinput keys to the focused game, and the udev rules survive a SteamOS update.

## Capabilities

### New Capabilities

- `linux-daemon`: the headless Linux service. It covers startup and shutdown, how problems are shown on the deck and in the journal, the status key, and installation as a systemd user service with udev access.

### Modified Capabilities

- `deck-device`: device access, hotplug, resume after sleep, and the open-failure message on Linux.
- `key-actions`: `keys`, `media` and `open` on Linux. `cmd` maps to Super with the new aliases `super` and `meta`. `fn` fails on Linux. Characters map through the XKB layout, and a Linux permission problem replaces the macOS Accessibility prompt.
- `deck-config`: the starter config depends on the platform.

## Impact

- Code: new `Sources/DeckPlatformLinux`, a small C target `CLinux` that wraps the ioctl and uinput macros Swift can't import, new `Sources/streamdeckd`, and Linux-only test targets. `KeyCombo` gains the `super`/`meta` aliases. `ConfigFile.starter` is chosen by platform. `DeckEngine` gets an opt-in for showing problems on the deck. It's off for the Mac app, so the Mac app doesn't change.
- Build: `Package.swift` gets an `#if os(Linux)` block. New `scripts/build-linux.sh` builds the static binary in Docker with the Static Linux SDK. `scripts/test-linux.sh` also runs the new Linux tests.
- Install: new `scripts/install-linux.sh` and `dist/linux/` (systemd unit, udev rules, modules-load file). README section for the Steam Machine.
- Dependencies: no new Swift packages and no system libraries in the binary. Build-time only: the Swift Static Linux SDK.
- Out of scope: Game Mode page switching and `steam:` app pages (#8), the web editor (#9), and architectures other than x86_64.
