# Tasks

The checklist in issue #7 is a summary, not a set of checkboxes. Its last bullet ("Verify on hardware") is covered by group 9 here.

## 1. Package and C shim

- [x] 1.1 Add the `#if os(Linux)` block to `Package.swift` with `CLinux`, `DeckPlatformLinux` (depends on `CLinux`, `DeckSupport`, `DeckHID`, `DeckConfig`, `DeckEngine`), the `streamdeckd` executable product, and `DeckPlatformLinuxTests` with a `Fixtures` resource directory. Verify that `./scripts/test-linux.sh build` succeeds with empty placeholder sources, and that the macOS block is unchanged (`git diff Package.swift` shows only the added block)
- [x] 1.2 Add `CLinux` with static inline wrappers for `HIDIOCSFEATURE`/`HIDIOCGFEATURE`, `UI_SET_EVBIT`, `UI_SET_KEYBIT`, `UI_DEV_SETUP`, `UI_DEV_CREATE` and `UI_DEV_DESTROY`, and an `emit(fd, type, code, value)` helper that fills `struct input_event`. Verify with a test that creates and destroys a uinput device when `/dev/uinput` is writable and skips otherwise, and that `./scripts/test-linux.sh build --target CLinux` builds without warnings

## 2. Engine: problems on the deck and `super`/`meta`

- [x] 2.1 Add `super` and `meta` to `KeyCombo.modifierAliases`. Verify with `KeyComboTests`: `super+l` and `meta+l` parse to the same combo as `cmd+l`, and `text` stays `cmd+l`
- [x] 2.2 Add `showsProblemsOnDeck` to `DeckEngine.init` (default `false`) and set the key error dot for action and render problems per design ("Problems on the deck"). Verify with `DeckEngineTests` using `FakeRenderer`: a failed `run` action re-renders that key with `error: true`, a later success clears it, a config reload clears it, a missing icon renders with `error: true`, and with the flag off none of this happens
- [x] 2.3 Add the status key on key 14 and the `onStatusKeyPress` callback. Verify with `DeckEngineTests`: `configFailed` with no config shows the status key labeled `Config` and blanks keys 0-13; a permission problem shows `Keys`; both together show `2 problems`; a `.device` problem shows nothing; pressing key 14 calls `onStatusKeyPress` and runs no action; clearing the problems restores key 14's definition; with the flag off key 14 is never replaced
- [x] 2.4 Verify that the macOS app is unchanged: `AppDelegate` doesn't pass the flag, and `./scripts/test-linux.sh test --filter DeckEngineTests` passes, including the old tests unchanged

## 3. Linux starter config

- [x] 3.1 Make `ConfigFile.starter` platform-selected and write the Linux starter (design "Linux starter config"). Verify with a `DeckRenderTests` test, which has the renderer, that runs on Linux: the starter passes `ConfigLoader`, every key renders with no problems, and it contains no `sf:`, `.app` or `fn`

## 4. hidraw transport

- [x] 4.1 Add the pure helpers: a `/sys/class/hidraw/*/device/uevent` parser (`HID_ID`, `HID_UNIQ`) and a device finder over a sysfs root path. Verify with fixture trees: a deck and an unrelated keyboard finds only the deck's node, the serial comes from `HID_UNIQ`, and an empty root finds nothing
- [x] 4.2 Add `HidrawTransport: DeckTransport` per design (open, reader thread, serial write queue, feature reports through `CLinux`, `EACCES` retry and message, inotify on `/dev`, flush in `stop()`). Verify with tests over a `socketpair` or pipe pair standing in for the node: written image reports match `ReportCodec.imageReports` byte for byte, an input report yields the right key events, closing the other end yields `.disconnected`, and the `EACCES` message names the node and the udev rules
- [x] 4.3 Add `ResumeDetector` with an injectable clock pair. Verify with a test where the boottime-monotonic gap grows by 30 s: the callback fires exactly once, and a 0.5 s growth doesn't fire it

## 5. Keyboard: evdev tables, XKB layout, uinput

- [x] 5.1 Add `EvdevKeys`: macOS named-key code to evdev, modifiers, and media keys per design. Verify with tests that every code in `KeyCombo.canonicalNames` has an evdev entry, that `f20` → `KEY_F20` and `return` → `KEY_ENTER`, and that every `MediaKey` case maps
- [x] 5.2 Add the XKB symbols parser and `XKBLayout: KeyboardLayout` (built-in `us`, includes, variants, Latin fallback, cache), and copy the fixture files (`us`, `de`, `de(nodeadkeys)`, `fr`, `ru`, `latin`, plus the `pc`/`inet` includes they need) from xkeyboard-config with its license into `Tests/DeckPlatformLinuxTests/Fixtures/xkb`. Verify with tests: `de` maps `z` → `KEY_Y` and `y` → `KEY_Z`; `fr` maps `a` → `KEY_Q`; `de` has no key for `[`; `ru` falls back to `us`; a missing symbols directory gives `us`; `de(nodeadkeys)` resolves its include chain
- [x] 5.3 Add layout detection over injectable roots (`/proc`, own environment, `/etc`) with the order from design. Verify with fixture trees: the gamescope environment wins over `00-keyboard.conf`, `00-keyboard.conf` wins over `vconsole.conf`, `de,us` uses `de`, another user's gamescope process is ignored, and nothing found gives `us`
- [x] 5.4 Add `UinputKeyboard` (device setup with the key bits from 5.1, press sequence with `SYN`, failure message). Verify with a test that records the emitted events through an injected writer: `cmd+shift+z` on `de` sends LEFTMETA, LEFTSHIFT, Y down, SYN, then the reverse up, SYN; a failed open gives the udev message

## 6. Actions

- [x] 6.1 Add `LinuxActionPerformer` (`run` through `ShellRunner`, `keys`/`media` through `UinputKeyboard` and `XKBLayout`, `fn` and `noKey` failures, `open` routing). Use an injectable process launcher. Verify with tests: `steam://rungameid/570` runs `steam steam://rungameid/570`, `https://example.com` runs `xdg-open`, `~/nothing-here.txt` fails with the macOS message, a non-zero exit includes stderr, `fn+f` fails with "fn has no Linux equivalent" and sends nothing, and `keys` without uinput fails with the udev message
- [x] 6.2 Update `docs/config.md` with Linux behavior: `super`/`meta`, `cmd` = Super, `fn` is macOS only, the layout rule, `open` with `steam://` (how to find an AppID: the store page URL or `steamdb.info`), `xdg-open`, and `ms:` icons for shared configs. Verify that every example in the new text loads through `ConfigLoader` in a test

## 7. Daemon

- [x] 7.1 Add `Sources/streamdeckd/main.swift`: wiring, `dispatchMain`, SIGTERM/SIGINT through dispatch signal sources, the uinput permission problem at startup, resume → `redrawAll`, `onStatusKeyPress` logging. Verify by running it in Docker with no device and an invalid config: it logs the config problem, stays up, and exits 0 within 1 s of `docker stop`
- [x] 7.2 Add problem-diff logging (`problem:`, `resolved:`, `connected`, `disconnected` lines on line-buffered stderr) as a pure function from old and new status to lines. Verify with tests: an added problem gives one `problem:` line, a removed one gives one `resolved:` line, and an unchanged status gives nothing

## 8. Static build and installation

- [x] 8.1 Add `scripts/build-linux.sh` (pinned Static Linux SDK URL and checksum next to `SWIFT_VERSION`, SDK installed into the cache, release build of `streamdeckd`, copied to `build/linux/`, static-link check). Verify that the script succeeds, `file build/linux/streamdeckd` says "statically linked", the binary runs in a bare `alpine` and a bare `debian:stable-slim` container with `--help`-less startup logging the missing device, and record the binary size here. Recorded: 57 MB stripped (138 MB with debug info); runs in bare `alpine:3.20` and `debian:stable-slim`. Needed Yams 6.2.2 (5.x does not compile against the musl SDK) and hand-written kernel constants in `CLinux` (the musl sysroot has no uapi headers)
- [x] 8.2 Add `dist/linux/streamdeckd.service`, `dist/linux/70-streamdeck.rules`, `dist/linux/uinput.conf` and `scripts/install-linux.sh` (install, upgrade, `--uninstall`). Verify with `systemd-analyze verify` on the unit, `udevadm verify` on the rules where available, and `shellcheck` on the script
- [x] 8.3 Add a README "Steam Machine (Linux)" section: build, copy over scp, set the `deck` password, install, check `journalctl --user -u streamdeckd -f`, uninstall. Update the project layout table with `DeckPlatformLinux`, `CLinux`, `streamdeckd` and `dist/linux`. Verify that every directory under `Sources/` has a row and that the commands match the scripts' actual flags

## 9. Hardware verification (Steam Machine, SteamOS)

- [ ] 9.1 Fresh install with the README steps. Verify the deck shows the starter page without a reboot and again after a reboot, and that `systemctl --user status streamdeckd` is active
- [ ] 9.2 In Game Mode with a game running: verify that Steam doesn't list the deck as a controller, that key presses cause no Steam Input reaction, that `keys: f12` takes a Steam screenshot, that a `keys:` combo reaches the game, that `media: volumeup` changes the volume, and that `open: steam://rungameid/<id>` launches a game. Resolve the design's open questions (`steam` vs `xdg-open`, key press timing) and record the answers here
- [ ] 9.3 Switch the system layout to `de`. Verify that `keys: ctrl+z` reaches a text field as Ctrl+Z, and record which detection source found the layout
- [ ] 9.4 Hotplug, suspend/resume, `kill -9`, a broken config edit over ssh, and removed udev rules. Verify each against its spec scenario (deck-device, linux-daemon), with the status key and journal lines as specified
- [ ] 9.5 Install a SteamOS update (or switch channel to force one) and reboot. Verify the deck still works without reinstalling
- [ ] 9.6 On a Mac: `./scripts/bundle.sh` and the full `swift test` with Yams 6.2.2 and the engine changes. Verify that both pass, and that the app behaves as before (no status key, no new error dots), with a broken config edit and a failing `run` key

## Workflow follow-up

- Archive the change once group 9 is recorded, and close issue #7 with `gh issue close 7 --comment "Archived as 7-linux-daemon"`.
