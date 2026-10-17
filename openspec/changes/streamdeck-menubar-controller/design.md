# Design

## Context

Greenfield repository. Target machine: macOS 27, Xcode 27.1, Swift 6.4, Apple Silicon, with an Apple Development signing identity available. The device is a Stream Deck Original V2 (PID `0x006d`), which uses Elgato's second-generation HID protocol. Motivation and scope: see proposal.md. Behavior: see the specs in `specs/`.

Protocol facts the design relies on. They come from the open-source `python-elgato-streamdeck` and `@elgato-stream-deck/node` implementations and are verified on the device in task group 2:

| Purpose | Report |
|---|---|
| Key state (input) | ID `0x01`, 3 more header bytes, then 15 bytes, `1` = pressed |
| Key image (output) | ID `0x02`, header `[0x02, 0x07, key, isLast, lenLo, lenHi, pageLo, pageHi]`, payload up to 1016 bytes, report padded to 1024 |
| Brightness (feature) | `[0x03, 0x08, percent]`, padded to 32 bytes |
| Reset (feature) | `[0x03, 0x02]` |
| Firmware / serial (get feature) | `0x05` / `0x06` |
| Image format | 72x72 JPEG, flipped horizontally and vertically |

## Goals / Non-Goals

**Goals:**
- Pure logic (protocol encoding, config validation, navigation, key-combo parsing, label layout) testable with `swift test`, without a device or a GUI.
- Small, swappable boundary around the hardware so that more models or press types can be added later without touching actions or config.
- Stable code signature across rebuilds so Accessibility permission survives development.

**Non-Goals:**
- Supporting other Stream Deck models. The model table holds one entry, but no abstraction is built for models that don't exist yet.
- Sandboxing or Mac App Store distribution. Synthesized events and arbitrary shell commands are incompatible with the sandbox.
- A plugin system. Integrations go through shell commands.

## Decisions

### D1. Swift package with library modules, bundled into a signed `.app` by script
Layout:
```
Package.swift
Sources/
  DeckHID/       transport protocol, IOKit implementation, report codec
  DeckConfig/    Codable model, Yams decoding, validation, file watcher
  DeckRender/    CoreGraphics/CoreText key drawing, JPEG encoding
  DeckEngine/    navigation state, dynamic-key scheduler, action dispatch
  StreamDeckApp/ AppKit menu bar, app lifecycle (executable)
Tests/           one test target per library module
scripts/bundle.sh   builds release, assembles .app with Info.plist, signs
```
`scripts/bundle.sh` writes `Info.plist` (`LSUIElement = YES`, bundle ID `de.wehrens.streamdeck`), copies the binary, and signs with the Apple Development identity.
- Why: `swift build` / `swift test` work from the terminal and from agents. The library split keeps device-free logic testable.
- Alternative: an Xcode project. Rejected because the `.pbxproj` is hard to edit and review by hand, and it adds nothing a menu-bar app without storyboards needs.
- Alternative: an unsigned or ad-hoc signed binary. Rejected because TCC ties Accessibility to the code signature, so the grant would be lost on every rebuild.

### D2. IOKit `IOHIDManager` directly, no hidapi
Match on VID/PID and register matching/removal callbacks for hot-plug. The manager runs on the HID dispatch queue. For each match, the transport creates its own `IOHIDDevice` from the same IOService (`IOHIDDeviceCreate(IOHIDDeviceGetService(matched))`). It opens that object non-seizing (`kIOHIDOptionsTypeNone`), sets the queue, registers the input-report callback, then activates it. `IOHIDDeviceSetReport` / `GetReport` handle output and feature reports.
- Why a separate device object: found on hardware. The manager's device objects are already activated, and IOKit traps when a callback is registered on one. Manager-level input callbacks only fire for devices the manager opened itself, which would lose the per-device open error needed for the Elgato-conflict message. Details in `docs/protocol.md`.
- Why: no C dependency, and hot-plug callbacks come with it.
- Alternative: hidapi via a C target. Rejected: extra dependency for no gain on a macOS-only app.
- `DeckHID` exposes a `DeckTransport` protocol (`events: AsyncStream<DeviceEvent>` carrying connect, disconnect, open-failure and key events; `setImage(key:jpeg:)`, `setBrightness(_:)`, `reset()`, `start()`, `stop()`). The engine depends only on this protocol, and tests use a fake.

### D3. Raw key-down/up at the boundary, press interpretation in the engine
`DeckHID` diffs consecutive input reports and emits `KeyEvent(key, .down | .up)`. A `PressInterpreter` in `DeckEngine` maps `.down` to "press" and drives press feedback on both edges.
- Why: long-press, double-press and repeat later need only a new interpreter and config fields. See the explore discussion.

### D4. Concurrency: engine on the main actor, I/O on dedicated queues
- `DeckEngine` and the UI are `@MainActor`. State is small, and AppKit and `NSWorkspace` notifications live there.
- HID writes go through one serial `DispatchQueue`, because `SetReport` is synchronous and a full page is about 75 reports.
- Rendering runs on the main actor, synchronously. A 72x72 key renders in about a millisecond, so a full page takes well under a frame. Keeping it on the main actor avoids ordering bugs between renders and cache updates. The renderer is a pure function, so it can move off the main actor later if profiling shows a need.
- The engine keeps the last JPEG sent per key and writes only keys whose bytes changed. Page switches between similar pages and dynamic-key ticks then cost one or two keys, not fifteen.

### D5. Config: Yams node tree, single parse-and-validate pass
`Yams.compose` produces a node tree, and the parser walks it into the model structs. Every node carries its YAML line, so every error, not just syntax errors, reports a line. Unknown fields are found by comparing each mapping's keys against the allowed set. Value checks (key range, intervals, action exclusivity, hex colors, key-combo and media names) happen while walking. Page references (`default_page`, `page` actions, `app_pages`) are collected and checked at the end. All errors are collected, not just the first. Each carries `line`, `page` and `key` where they apply.
- Alternative: `Codable` decoding plus a separate validation pass. Rejected during implementation: `Codable` loses node positions, so validation errors could not name a line.
- Alternative: hand-written YAML subset parser. Rejected: Yams is the standard and gives line numbers.

### D6. File watching with FSEvents on the config directory
An FSEvents stream on `~/.config/streamdeck/` with a 200 ms latency coalesces events. Any event for `config.yaml` or files under the directory triggers a reload. This covers atomic rename-saves from editors, and changed icon files.
- Alternative: `DispatchSource` vnode on the file. Rejected: it loses the file descriptor on rename-replace and needs re-arming.

### D7. Shell execution via the user's login shell
`run` and `dynamic.run` execute as `$SHELL -l -c "<command>"` (shell from `getpwuid`, fallback `/bin/zsh`) through `Process`, with a 10-second timeout for dynamic keys (terminate, then kill). Each dynamic key has its own `Task` loop that sleeps `every` after each completed run, so runs never overlap. Loops for keys not on the current page are cancelled.
- Why login shell: apps started from launchd get a minimal `PATH`. A login shell gives the user's Homebrew and other tools.
- Trade-off: login-shell startup adds latency per run (often 50-300 ms with heavy dotfiles). Acceptable at a 1 s minimum interval. If it hurts, resolve `PATH` once at startup instead.

### D8. Synthesized input
- Keystrokes: `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with modifier flags, posted to `.cghidEventTap`. Key names map to virtual key codes through a static table (US layout ANSI codes; letters are positional).
- Media keys: `NSEvent.otherEvent(with: .systemDefined, subtype: 8, data1: (code << 16) | (state << 8))` for down (`0xA`) and up (`0xB`), posted via its `cgEvent`. Codes come from `NX_KEYTYPE_PLAY`, `NX_KEYTYPE_NEXT`, etc.
- Permission check: `AXIsProcessTrustedWithOptions` before posting. If not trusted, report and offer to open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.

### D9. Rendering with CoreGraphics + CoreText
Offscreen 72x72 sRGB bitmap. Layers: background fill, then icon (SF Symbol via `NSImage(systemSymbolName:)` with a white palette config, or an image file via ImageIO, aspect-fit), then label in the system font, wrapping with `CTFramesetter` and shrinking from 14 pt to 9 pt, then ellipsis truncation. Press feedback draws the same image with a 40% black overlay. Error indicator: small red dot top-right. The final step flips both axes and encodes JPEG (quality 0.9) with `CGImageDestination`.
- The renderer is a pure function `(KeyAppearance) -> Data` and is tested with snapshot assertions on decoded pixels (for example, after the flip a known top-left pixel lands bottom-right).

### D10. Navigation as a pure state machine
```
state: current page, history [page], autoSwitch on/off
events: pageAction(name) | back | appActivated(bundleID) | configReloaded
```
`appActivated` with the app's own bundle ID is ignored. `appActivated` sets the page to `app_pages[id] ?? default_page` and clears history. A pure `reduce(state, event) -> state` makes every page-navigation scenario a unit test.

### D11. Menu bar with AppKit `NSStatusItem`
`NSStatusItem` + `NSMenu`, rebuilt on `menuNeedsUpdate`. The brightness slider is an `NSSlider` in a custom `NSMenuItem.view`. Launch at login uses `SMAppService.mainApp`.
- Alternative: SwiftUI `MenuBarExtra`. Rejected: an inline slider and a dynamic error list are awkward in `.menu` style, and `.window` style doesn't feel like a menu.

### D12. Sleep/wake
Observe `NSWorkspace.didWakeNotification`. After wake, wait 1 s, invalidate the per-key JPEG cache, then re-send brightness and the full page. If the device was re-enumerated, hot-plug handling covers it anyway.

## Risks / Trade-offs

- [Input report buffer layout from IOKit may include or omit the report ID byte] → Verify against the device in task 2.2 and cover the decoder with a test using captured bytes.
- [Elgato app holding the device makes opens fail or events go missing] → Detect a running Elgato app by bundle ID `com.elgato.StreamDeck` and show a specific error.
- [Input Monitoring prompt appears for HID input on current macOS] → Checked in the first spike task. If it appears, document the one-time grant. The design does not change.
- [Accessibility grant lost after re-signing with a different identity] → `bundle.sh` always uses the same identity and bundle ID. Install to `/Applications` so the login item and TCC path stay stable.
- [Keystroke mapping assumes US key positions] → Acceptable for v1. Letters are positional, which matches how most shortcuts are defined.
- [Login-shell cost for frequent dynamic keys] → Minimum interval of 1 s. Fallback described in D7.
- [JPEG artifacts on fine text] → Quality 0.9. Raise it if text looks soft on the device.

## Migration Plan

None. New app. The user quits the Elgato app (and removes it from login items) before running this one.

## Open Questions

- Exact label font sizes and icon/label split ratio. To tune visually on the device; this doesn't affect the specs or tasks.
