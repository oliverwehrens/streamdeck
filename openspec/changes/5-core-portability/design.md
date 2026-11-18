# Design

## Context

See proposal.md for motivation. Platform dependencies in the targets the Linux daemon needs:

| File | Platform dependency | Used by |
|---|---|---|
| `DeckEngine/SystemActionPerformer.swift` | AppKit, ApplicationServices (CGEvent, NSWorkspace, AX) | `AppDelegate` |
| `DeckEngine/KeyboardLayout.swift` | Carbon (`SystemKeyboardLayout` only; the protocol and `TableKeyboardLayout` are pure) | performer, `KeyRecorder` |
| `DeckEngine/ShellRunner.swift` | `os` (`OSAllocatedUnfairLock`), `/bin/zsh` fallback | `AppDelegate`, engine |
| `DeckEngine/DeckEngine.swift` | calls `OpenFailure.message` and `OpenFailure.elgatoAppIsRunning()` on `.openFailed`; imports `DeckRender` and calls `KeyRenderer.render` (AppKit, CoreText) | - |
| `Tests/DeckEngineTests/DynamicKeyTests.swift` | compares against real `KeyRenderer` JPEGs | tests |
| `DeckHID/IOKitTransport.swift` | IOKit | `AppDelegate` |
| `DeckHID/OpenFailure.swift` | AppKit (`NSRunningApplication`), IOKit return codes | engine |
| `DeckConfig/ConfigWatcher.swift` | CoreServices (FSEvents, recursive, 0.2 s latency) | `AppDelegate` |
| `Tests/DeckEngineTests/Fakes.swift`, `Tests/DeckConfigTests/ConfigWatcherTests.swift` | `os` (`OSAllocatedUnfairLock`) | tests |

`ReportCodec`, `DeckTransport`, `ConfigLoader`, `ConfigDocument`, `KeyCombo`, `Navigation` and `DynamicOutput` use only Foundation and Yams. The package targets macOS 14. Swift is not installed on the Linux development machine, but Docker is.

## Goals / Non-Goals

**Goals:**
- `swift build` and `swift test` on Linux build and run every portable target and its tests, with no source changes needed on the next Linux step (#7) to keep the core compiling.
- The macOS app builds, behaves and tests exactly as before.
- One reproducible way to run the Linux tests from this machine.

**Non-Goals:**
- Any Linux implementation of transport, actions, keyboard layout or rendering (#6, #7).
- Evdev key codes. `KeyCombo.Key.named` and `TableKeyboardLayout` keep holding macOS virtual key codes; #7 maps them.
- Raising the macOS deployment target.
- CI. A Linux test script is enough for now.

## Decisions

### One Mac platform target: `DeckPlatformMac`

`IOKitTransport`, `OpenFailure`, `SystemActionPerformer` and `SystemKeyboardLayout` move into one new target that depends on `DeckHID`, `DeckEngine` and `DeckConfig`. `StreamDeckApp` depends on it. #7 adds a matching `DeckPlatformLinux`.

*Alternative:* split by layer (`DeckHIDMac`, `DeckEngineMac`). More targets and manifest lines with no consumer that wants one without the other.

### What stays portable

- `KeyboardLayout` and `TableKeyboardLayout` stay in `DeckEngine`. They are pure and #7 reuses the protocol.
- `SystemActionPerformer.describe(_:command:)` (exit status and stderr to an `ActionResult`) moves into `DeckEngine` as an `ActionResult` initializer from a `CommandResult` and command, so the Linux performer reuses the same message for `run` actions.
- `resolve`, `flags`, `ResolvedKey` and the media key mapping stay with `SystemActionPerformer`. They are typed in `CGEventFlags` and macOS key types.

### Rendering becomes an engine port

`DeckEngine` depends on `DeckRender`, which stays AppKit-based until #6. The dependency flips: the engine owns the rendering boundary, as it already owns `DeckTransport`, `ActionPerformer` and `CommandRunner`.

- `KeyAppearance` and `RenderedKey` move from `DeckRender` into `DeckEngine` unchanged. They are plain values over `DeckConfig` types.
- `DeckEngine` declares `protocol KeyRendering: Sendable { func render(_ appearance: KeyAppearance) -> RenderedKey }` in `Ports.swift`. `DeckEngine.init` takes a `renderer: any KeyRendering`, which both key rendering and the blank images in `shutdown()` use.
- `DeckRender` depends on `DeckEngine` and adds `public struct AppKitKeyRenderer: KeyRendering` that calls `KeyRenderer.render`. `KeyRenderer`'s static API, including `preview` for the editor, stays as it is. `AppDelegate` passes `AppKitKeyRenderer()`.
- Engine tests use a `FakeRenderer`. It encodes the appearance into deterministic bytes (`String(describing:)`), and reports a problem for a `.file` icon or an `image` path that doesn't exist, so `missingIconIsReported` still checks the engine's problem plumbing. `DynamicKeyTests` compare against `FakeRenderer` output instead of AppKit JPEGs, which also stops them depending on font rendering.

#6 replaces `AppKitKeyRenderer` with the shared renderer as another `KeyRendering` conformance, and the engine doesn't change.

*Alternatives:* keep `DeckEngine` Mac-only until #6 (narrows this change's goal and pushes the restructuring into #6), or pull #6 into this change (mixes a refactor with new rendering behavior).

### `DeviceEvent.openFailed` carries a message

`case openFailed(Int32)` becomes `case openFailed(String)`. `IOKitTransport` builds the message with `OpenFailure.message(code:elgatoRunning:)` when opening fails. The engine stores the string as the `.device` problem.

*Alternative:* inject a `(Int32) -> String` describer into `DeckEngine`. That keeps an IOKit-shaped code in the portable event type and adds an init parameter. The transport is already the platform-specific part and knows its own error codes.

### Mac-only targets are declared under `#if os(macOS)` in `Package.swift`

The manifest always declares `DeckSupport`, `DeckConfig`, `DeckHID` and `DeckEngine` and their test targets. Inside `#if os(macOS)` it appends `DeckRender`, `DeckPlatformMac`, `StreamDeckApp`, their test targets and the app product. On Linux, plain `swift build` and `swift test` work.

*Alternative:* declare every target everywhere and wrap each Mac source file in `#if os(macOS)`. That puts guards in roughly 25 files and leaves an empty `StreamDeckApp` executable on Linux. *Consequence:* the manifest checks the host, so a future cross-compile from macOS to Linux must build by `--product`. #7 handles that if it needs it.

### A portable lock in a small `DeckSupport` target

`OSAllocatedUnfairLock` exists only on Apple platforms. `Synchronization.Mutex` needs macOS 15. A `Locked<Value>` class (an `NSLock` around a value, with `withLock`, `@unchecked Sendable`) goes in a new `DeckSupport` target that `DeckEngine` and the test targets depend on. Its call sites look the same as `OSAllocatedUnfairLock`'s, so replacing it is mechanical.

*Alternatives:* put it in `DeckConfig` (wrong home; nothing there needs it), or copy it into each target (duplication).

### `ConfigWatcher` gets platform backends behind one public API

`ConfigWatcher` keeps its public API and reload logic (`url`, `config`, `start`, `stop`, `reload`, `Update`, serial `queue`). Change detection moves into an internal directory monitor with two implementations, chosen with `#if canImport(CoreServices)`:

- **FSEvents**: today's code, unchanged.
- **inotify** (Linux): `inotify_init1(IN_NONBLOCK | IN_CLOEXEC)`, a `DispatchSource` read source on the watcher's queue, and a watch on the config directory plus every subdirectory, matching FSEvents' recursion. That covers icon files under `icons/`. A watch is added when a directory is created or moved in. The mask is `IN_CLOSE_WRITE | IN_MOVED_TO | IN_MOVED_FROM | IN_CREATE | IN_DELETE | IN_MODIFY | IN_ATTRIB`. Events are coalesced: the first event in a burst schedules one reload 0.2 s later, the same as FSEvents' latency. `stop()` cancels the source, which closes the descriptor.

Watching the directory instead of the file handles saves that replace the file (rename over it), which change the inode.

*Alternative:* poll modification times. It's simpler, but polling slower than the FSEvents latency makes reloads lag, and polling faster wastes wakeups on a machine that is also running games.

### `ShellRunner` on Linux

`getpwuid` and `kill` come from Glibc or Musl through conditional imports. The fallback shell is `/bin/sh` on Linux and stays `/bin/zsh` on macOS. Everything else (`Process`, pipes, `DispatchQueue`) is available in swift-corelibs-foundation.

The blocking parts of a run move from `DispatchQueue.global()` to dedicated threads (`Thread.detachNewThread`): waiting for the process and draining its two pipes. Found while implementing: on Linux, Swift concurrency's global executor runs on the same dispatch pool as `DispatchQueue.global()`, which is capped at the core count. Each command blocked three of those threads for its whole runtime, so a few concurrent commands starved every task in the process. In the tests, `echo hello` took 3 s and the dynamic key tests timed out in about one run in three. In the daemon, slow dynamic commands would have frozen the engine. macOS has a separate cooperative pool and grows dispatch threads when they block, which is why the bug never showed there. The timeout timer stays on the global queue, because it doesn't block.

### Linux tests run in Docker

`scripts/test-linux.sh` runs `swift test` in the official `swift` Docker image, with the repo mounted and a container-local build directory, so Linux artifacts never mix with the macOS `.build`. The image tag is pinned to the Swift version the macOS toolchain reports. A native toolchain works the same: plain `swift test`.

## Risks / Trade-offs

- [This machine can't build the macOS side] → The task list ends with a manual step on a Mac: `./scripts/bundle.sh`, the full `swift test`, and a short smoke test (deck connects, a keystroke key works, a config edit reloads).
- [swift-corelibs-foundation differs from Apple Foundation (path APIs, `Process`, `DispatchSource`)] → The existing `DeckConfig` and `DeckEngine` tests running on Linux are the check. Fixes stay in the core and never fork behavior by platform unless a test shows the difference.
- [inotify misses changes made before a subdirectory's watch is added] → Directory creation already triggers a reload, which picks up the contents. Same outcome as today.
- [inotify watch limit (`max_user_watches`)] → The config directory has a handful of subdirectories. If adding a watch fails, the watcher reports it the way a failed FSEvents stream does today: it keeps the loaded config and doesn't watch.
- [Host-checked manifest blocks cross-compiling from macOS] → Accepted. Build Linux binaries on Linux or in Docker. #7 can revisit it.
- [Swift 6 strict concurrency on Linux flags things macOS doesn't (non-`Sendable` Foundation types)] → Fix at the call site. Don't loosen the language mode.

## Migration Plan

No migration. Nothing changes for users. Rollback is a revert.
