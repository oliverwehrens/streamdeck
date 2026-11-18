Issue: #5

# Proposal

## Why

We want a Linux version that runs headless in SteamOS Game Mode on a Steam Machine, next to the existing macOS app and using the same config format. Today no target builds on Linux: `DeckEngine` and `DeckHID` mix the portable core with AppKit, Carbon, ApplicationServices, IOKit and CoreServices code. The core has to build and test on Linux before the renderer (#6), the daemon (#7), Game Mode (#8) or the web editor (#9) can follow.

## What Changes

- New Mac-only target for platform code. `SystemActionPerformer` and `KeyboardLayout` (including `SystemKeyboardLayout`) move out of `DeckEngine`, which then depends only on Foundation and `DeckConfig`. `TableKeyboardLayout` and other portable pieces stay in the core if nothing platform-specific holds them back.
- `IOKitTransport` and `OpenFailure` move out of `DeckHID`. The portable `ReportCodec`, `DeckTransport` and device event types stay.
- `DeviceEvent.openFailed` carries the user-facing message instead of an IOKit return code, so the engine no longer calls `OpenFailure` (and through it `NSRunningApplication`). The transport describes its own platform's errors.
- `ConfigWatcher` gets an inotify backend on Linux. It watches the config directory and its subdirectories, so saves by file replacement and edited icon files reload as they do with FSEvents today. FSEvents stays on macOS.
- `ShellRunner` and the test fakes replace Apple's `OSAllocatedUnfairLock` with a small portable lock. On Linux the shell fallback is `/bin/sh` instead of `/bin/zsh`.
- `Package.swift` gets platform conditions. On macOS the app, `DeckRender` and all current tests build as before. On Linux, `DeckConfig`, `DeckEngine` and `DeckHID` build, and their tests run.
- Tests that use Mac-only APIs (`ActionTests` uses CoreGraphics through `SystemActionPerformer`, `OpenFailureTests` uses IOKit) move with the code they test, into Mac-only test targets.
- Rendering becomes an engine port: `DeckEngine` defines `KeyRendering` and owns `KeyAppearance` and `RenderedKey`, and gets its renderer injected instead of importing `DeckRender`. `DeckRender` stays Mac-only in this change and conforms to the port. #6 replaces it with a shared renderer.
- The README describes building and testing the core on Linux.

No behavior changes for users of the macOS app.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This is a restructuring with no spec-level behavior change, so the change sets `skip_specs: true`.

## Impact

- Code: `Sources/DeckEngine/SystemActionPerformer.swift`, `Sources/DeckEngine/KeyboardLayout.swift`, `Sources/DeckHID/IOKitTransport.swift`, `Sources/DeckHID/OpenFailure.swift`, `Sources/DeckHID/DeckTransport.swift`, `Sources/DeckEngine/DeckEngine.swift`, `Sources/DeckEngine/ShellRunner.swift` and `Sources/DeckConfig/ConfigWatcher.swift` move or change. `StreamDeckApp` gets new imports.
- Build: `Package.swift` target graph; a Linux Swift 6 toolchain becomes a development requirement for Linux work.
- Tests: `Tests/DeckEngineTests/ActionTests.swift` and `Tests/DeckHIDTests/OpenFailureTests.swift` move to Mac-only test targets. `Fakes.swift` and `ConfigWatcherTests.swift` switch to the portable lock. The existing watcher tests run against inotify on Linux, plus a new test for an edited file in a subdirectory.
- Dependencies: no new packages. Yams already supports Linux.
