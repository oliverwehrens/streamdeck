# Tasks

Issue #5 has no checklist items, so nothing here duplicates it.

## 1. Linux test runner

- [x] 1.1 Add `scripts/test-linux.sh`: runs `swift` in the official `swift` Docker image pinned to the Swift version the macOS toolchain reports, with the repo mounted and a container-local build directory (not `.build`), passing its arguments through (default `test`); verify `./scripts/test-linux.sh --version` prints the pinned Swift version and leaves `.build/` untouched
- [x] 1.2 Add a "Linux" paragraph to the README's Build section: the portable targets build and test on Linux, run `./scripts/test-linux.sh` or `swift test` with a native toolchain, the app itself is macOS-only; verify the documented command runs as written

## 2. Mac platform target

- [x] 2.1 Create `Sources/DeckPlatformMac` and move `IOKitTransport.swift` and `OpenFailure.swift` from `DeckHID`, and `SystemActionPerformer.swift` and `SystemKeyboardLayout` (split out of `KeyboardLayout.swift`) from `DeckEngine`; `KeyboardLayout` and `TableKeyboardLayout` stay in `DeckEngine`; verify `grep -rE "import (AppKit|Carbon|IOKit|ApplicationServices|CoreGraphics)" Sources/DeckHID Sources/DeckEngine` finds nothing
- [x] 2.2 Move `describe(_:command:)` into `DeckEngine` as an `ActionResult` initializer from a `CommandResult` and command, and call it from `SystemActionPerformer`; verify with a test in `DeckEngineTests` for the success, exit-status and last-three-stderr-lines messages
- [x] 2.3 Change `DeviceEvent.openFailed(Int32)` to `openFailed(String)`; `IOKitTransport` yields `OpenFailure.message(code:elgatoRunning:elgatoAppIsRunning())`, and `DeckEngine` stores the string as the `.device` problem; verify with a `DeckEngineTests` test that a fake transport's `.openFailed("message")` shows up unchanged in `status.problems`
- [x] 2.4 Restructure `Package.swift`: always declare `DeckConfig`, `DeckHID`, `DeckEngine` and their test targets; inside `#if os(macOS)` add `DeckRender` (now depending on `DeckEngine`), `DeckPlatformMac`, `StreamDeckApp`, `DeckRenderTests`, a new `DeckPlatformMacTests` and `StreamDeckAppTests`, plus the app product; `StreamDeckApp` imports `DeckPlatformMac` where it uses the moved types (`AppDelegate`, `KeyRecorder`); verify `./scripts/test-linux.sh build --target DeckHID` and `--target DeckConfig` succeed
- [x] 2.5 Move the CGEvent parts of `Tests/DeckEngineTests/ActionTests.swift` (`flags`, `resolve`, the performer tests) and `Tests/DeckHIDTests/OpenFailureTests.swift` into `Tests/DeckPlatformMacTests`; the `TableKeyboardLayout.us` round-trip test stays in `DeckEngineTests` without importing CoreGraphics; verify no file under `Tests/DeckEngineTests` or `Tests/DeckHIDTests` imports a Mac-only module, and `./scripts/test-linux.sh test --filter DeckHIDTests` passes
- [x] 2.6 Update the README's project layout table with `Sources/DeckPlatformMac` (IOKit transport, CGEvent actions, keyboard layout) and `Sources/DeckSupport`, and mark `DeckRender` and `StreamDeckApp` as macOS-only; verify every directory under `Sources/` has a row

## 3. Rendering port

- [x] 3.1 Move `KeyAppearance` and `RenderedKey` from `DeckRender` into `DeckEngine`, add `KeyRendering` to `Ports.swift`, and give `DeckEngine.init` a `renderer: any KeyRendering` used for key images and the blank images in `shutdown()`; `DeckRender` imports `DeckEngine` and adds `AppKitKeyRenderer`; `AppDelegate` passes `AppKitKeyRenderer()` and `EditorView` imports `DeckEngine` for `KeyAppearance`; verify `grep -rn "DeckRender\|KeyRenderer\." Sources/DeckEngine` finds nothing and `./scripts/test-linux.sh build --target DeckEngine` gets past every rendering reference (`ShellRunner`'s `os` import is fixed in group 4)
- [x] 3.2 Add `FakeRenderer` to `Tests/DeckEngineTests/Fakes.swift` per design.md (deterministic bytes from the appearance; a problem for a missing `.file` icon or `image` path), pass it everywhere tests build a `DeckEngine`, and switch `DynamicKeyTests` from `KeyRenderer` JPEGs to `FakeRenderer` output; verify no file under `Tests/DeckEngineTests` imports `DeckRender`; the tests run on Linux in 4.3
- [x] 3.3 Move the `KeyRenderer` tests that build `KeyAppearance` values to import `DeckEngine`, and add a `DeckRenderTests` test that `AppKitKeyRenderer().render(a)` equals `KeyRenderer.render(a)`; verify on the Mac in 6.2

## 4. Portable lock and shell runner

- [x] 4.1 Add a `DeckSupport` target with `Locked<Value>` (an `NSLock` around a value, `withLock`, `@unchecked Sendable`) and a `DeckSupportTests` test that concurrent `withLock` increments from many tasks add up; verify `./scripts/test-linux.sh test --filter DeckSupportTests` passes
- [x] 4.2 Replace `OSAllocatedUnfairLock` with `Locked` in `ShellRunner.swift`, `Tests/DeckEngineTests/Fakes.swift` and `Tests/DeckConfigTests/ConfigWatcherTests.swift`, and drop `import os` there; verify `grep -rn "OSAllocatedUnfairLock\|^import os" Sources/DeckEngine Sources/DeckConfig Tests/DeckEngineTests Tests/DeckConfigTests` finds nothing
- [x] 4.3 Make `ShellRunner` build on Linux: conditional `Glibc`/`Musl` imports for `getpwuid` and `kill`, fallback shell `/bin/sh` on Linux and `/bin/zsh` on macOS, and the blocking waits on dedicated threads instead of `DispatchQueue.global()` (see design.md); verify with `DeckEngineTests` tests that run `echo hi` (stdout), `exit 3` (status) and `sleep 5` with a 0.5 s timeout (`timedOut`), and that `./scripts/test-linux.sh test --filter DeckEngineTests` passes, including `missingIconIsReported` and `DynamicKeyTests` from group 3

## 5. Config watcher on Linux

- [x] 5.1 Split `ConfigWatcher` into the shared reload logic and an internal directory monitor; move the FSEvents code unchanged into the macOS monitor behind `#if canImport(CoreServices)`; verify `ConfigWatcher`'s public API is unchanged (`AppDelegate` needs no edits)
- [x] 5.2 Add the inotify monitor per design.md: `inotify_init1(IN_NONBLOCK | IN_CLOEXEC)`, a read source on the watcher's queue, watches on the config directory and every subdirectory (added when a directory is created or moved in), the event mask from design.md, coalesced to one reload 0.2 s after the first event in a burst, and descriptor closed on `stop()`; a failed watch is reported like a failed FSEvents stream (config stays loaded, no watching); verify the existing `ConfigWatcherTests` pass on Linux, including atomic rename-saves and keeping the last valid config
- [x] 5.3 Add a `ConfigWatcherTests` test that editing an icon file in a subdirectory created after `start()` triggers a reload; verify it passes on Linux with `./scripts/test-linux.sh test --filter ConfigWatcherTests`

## 6. Integration

- [x] 6.1 Run the whole suite on Linux; verify `./scripts/test-linux.sh` (`swift test`) passes with no warnings from the portable targets in Swift 6 language mode
- [ ] 6.2 On a Mac: `./scripts/bundle.sh`, the full `swift test`, then a smoke test of the installed app (deck connects, a `keys:` key sends its combination, an `open:` key opens its target, saving `config.yaml` reloads the deck, with Elgato's app running the menu shows the "Quit the Elgato app" message); verify all pass and record the result in the PR

## Workflow follow-up

- Archive the change after review and close #5.
