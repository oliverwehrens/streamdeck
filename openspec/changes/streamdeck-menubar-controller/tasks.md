# Tasks

## 1. Package setup

- [x] 1.1 Create `Package.swift` (swift-tools 6.0, macOS 14 minimum) with library targets `DeckHID`, `DeckConfig`, `DeckRender`, `DeckEngine`, executable `StreamDeckApp`, one test target per library, and the Yams dependency; verify `swift build` and `swift test` succeed on the empty targets
- [x] 1.2 Write `scripts/bundle.sh` that builds release, assembles `StreamDeck.app` with `Info.plist` (`LSUIElement`, bundle ID `de.wehrens.streamdeck`), and signs with the Apple Development identity; verify `codesign --verify --deep --strict` passes and the app launches with no Dock icon

## 2. Device I/O (deck-device)

- [x] 2.1 Spike: open the device via `IOHIDManager` (VID `0x0fd9`, PID `0x006d`) with the Elgato app quit, log raw input reports and read firmware/serial; verify on hardware, and record in `docs/protocol.md` whether the input buffer includes the report ID and whether an Input Monitoring prompt appears
- [x] 2.2 Implement the report codec: input-report diffing into `KeyEvent` down/up, image packet splitting with the 8-byte header, brightness clamping and feature-report encoding; verify with unit tests on captured bytes from 2.1, including two simultaneous keys and an image needing several packets
- [x] 2.3 Implement `DeckTransport` protocol and IOKit transport with hot-plug callbacks, serial write queue, `setImage`, `setBrightness`, `reset`; verify on hardware that a solid-color JPEG appears on key 0 and that unplug/replug emits disconnect/connect
- [ ] 2.4 Ignore non-matching product IDs and report open failures, naming the Elgato app when `com.elgato.StreamDeck` is running; verify with a unit test of the error message selection, and manually with the Elgato app running

## 3. Configuration (deck-config)

- [x] 3.1 Define the Codable config model (brightness, default_page, pages, keys 0-14, icon, label, background, action, dynamic, app_pages) and decode with Yams, rejecting unknown fields; verify with unit tests for the minimal config and for an unknown field
- [x] 3.2 Implement validation (key range, page references, interval minimum 1 s, one action per key, hex color, key-combo names via the parser from 5.3) returning located errors; verify with one unit test per validation rule in the spec
- [x] 3.3 Write the starter config on first launch; verify with a test that writes to a temp directory and confirms the result passes validation
- [x] 3.4 Implement the FSEvents watcher on the config directory with keep-last-valid reload semantics; verify with a test that does a direct write, an atomic rename-save, and an invalid save, and checks that only valid configs are delivered
- [x] 3.5 Document the config format in `docs/config.md` with a full example covering every field; verify the example in the doc passes validation in a test that loads it from the doc

## 4. Rendering (key-rendering)

- [x] 4.1 Implement the renderer: background, SF Symbol or file icon (aspect-fit), label with shrink/two-line wrap/ellipsis, press overlay, error dot, both-axis flip, JPEG encode; verify with pixel-level unit tests (flip position, background color, non-square icon fit, long label stays inside the key)
- [x] 4.2 Render a placeholder for missing icons and report the missing path; verify with a unit test that renders a missing file and checks the reported error
- [ ] 4.3 Check rendering on the device with a test page (icon+label, label only, long label, SF Symbol, PNG, background colors); tune font sizes if needed and verify by visual check on hardware

## 5. Engine and actions (page-navigation, key-actions)

- [x] 5.1 Implement the navigation state machine (`reduce(state, event)`) for page actions, back, app activation, own-app ignore, auto-switch toggle, and config reload; verify with unit tests covering every page-navigation scenario
- [x] 5.2 Implement the engine: press interpreter (fire on down, feedback on down/up), page rendering with per-key JPEG cache diffing, applying brightness; verify with a fake `DeckTransport` that a page switch sends only changed keys and that holding a key fires once
- [ ] 5.3 Implement the key-combo parser and virtual-key table, and CGEvent keystroke posting with the Accessibility check; verify parser unit tests (valid combos, unknown key), and manually that `cmd+space` opens Spotlight
- [ ] 5.4 Implement media key posting for all listed names behind the same Accessibility check; verify manually that `playpause` and `volumeup` work
- [ ] 5.5 Implement `run` (login shell, background, stderr captured on failure) and `open` (NSWorkspace for URL/file/app) actions; verify with a unit test that a failing command reports its exit status and stderr, and manually that a URL and an app open
- [x] 5.6 Implement dynamic keys: per-key task loop, no overlap, 10 s timeout, keep last label on failure with error indicator, cancel when page leaves; verify with unit tests using a fake clock or short intervals for slow, failing, and hanging commands
- [ ] 5.7 Wire `NSWorkspace` frontmost-app notifications and wake notifications into the engine (1 s delay, cache invalidation, full redraw); verify manually by switching apps and by sleeping and waking the Mac

## 6. Menu-bar app (menubar-app)

- [ ] 6.1 Build the `NSStatusItem` menu: connection status, current page, auto-switch toggle, Open/Reveal/Reload Config, Quit; verify manually that each item works and that the icon changes when unplugged
- [ ] 6.2 Add the error list fed by config, render, action, permission, and device errors, with entries removed when resolved; verify manually by breaking and fixing the config
- [ ] 6.3 Add the brightness slider menu item; verify manually that the device dims while dragging and that the config value applies again after a reload
- [ ] 6.4 Add "Launch at Login" via `SMAppService.mainApp`; verify by enabling it, logging out and in, and seeing the device light up
- [ ] 6.5 Blank keys and release the device on quit; verify manually that all keys go dark on Quit
- [ ] 6.6 Write `README.md` covering build (`scripts/bundle.sh`), install to `/Applications`, quitting the Elgato app, and granting Accessibility; verify by following it from a clean checkout

## 7. Integration check

- [ ] 7.1 Run the app with a real config (two app-mapped pages, a media page, a dynamic clock key, keystroke and shell keys) for a working session including one sleep/wake and one replug; verify every spec scenario marked manual behaves as specified and `swift test` passes
