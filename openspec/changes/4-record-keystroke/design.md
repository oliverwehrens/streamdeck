# Design

## Context

`ActionEditor`'s `.keys` case in `KeyInspector.swift` is a `TextField` bound to `action.value`. `KeyCombo.parse` turns text into modifiers plus an ANSI virtual key code. `KeyCombo.keyCodes` maps names to codes, with several names for some codes (`return`/`enter`, `delete`/`backspace`, `esc`/`escape`). There is no inverse. `SystemActionPerformer.post` sends the code and maps `fn` to `.maskSecondaryFn`. Sending is position-based, and `docs/config.md` says so: "Letters map to US key positions." Save is bound to Cmd-S with `.keyboardShortcut("s")` in `EditorView.swift`. An empty `keys` value already fails validation with "keys must not be empty".

## Goals / Non-Goals

**Goals:**
- Letters, digits and punctuation mean the character on the active layout, both when sending and when recording.
- Turn a key event into config text that sends the same key on the same layout.
- Keep the layout lookup, the send-side resolution and the event mapping pure behind a layout protocol, so tests cover them with a fake layout.

**Non-Goals:**
- Global capture. Combinations macOS handles before the app (Cmd-Space, Cmd-Tab, Mission Control keys, media keys on F-row) are not recordable. The text mode covers them.
- Characters the config cannot name today, such as `ö` or `ß`. The set of accepted names stays as it is.
- Combos whose character needs Shift or Option on the active layout. They fail with an error instead of guessing a modifier.

## Decisions

### A combo stores a key, not a key code

```swift
public enum Key: Equatable, Sendable {
    case character(Character)   // letters, digits, punctuation
    case named(UInt16)          // return, esc, space, tab, delete, F-keys, arrows, navigation keys
}
public var key: Key
```

`parse` accepts exactly the names it accepts today, so loading and validation stay layout-independent. Single-character names become `.character`, the rest `.named` with today's code. `KeyCombo.text` writes the character as is, and named keys by one canonical name (`return`, `delete`, `esc`, `fN`, `left`, ...). Modifier order is `cmd`, `ctrl`, `alt`, `shift`, `fn`, matching the issue's examples `cmd+shift+m` and `ctrl+alt+left`. `DeckConfigTests` checks `parse(combo.text) == combo` over every name and modifier subset.

Alternative: keep `keyCode` and remap it at send time from US position to the layout. Rejected: the stored code would mean "US position" while nothing else is US-based, and the editor would need the same remap in reverse.

### `KeyboardLayout` resolves characters

In DeckEngine, which already links AppKit:

```swift
public protocol KeyboardLayout: Sendable {
    var name: String { get }
    func keyCode(typing character: Character) -> UInt16?
    func character(forKeyCode code: UInt16) -> Character?
}
```

- `SystemKeyboardLayout` reads `TISCopyCurrentASCIICapableKeyboardLayoutInputSource()` and its `kTISPropertyUnicodeKeyLayoutData`, then runs `UCKeyTranslate` with no modifiers and `kUCKeyTranslateNoDeadKeysBit` over codes 0–127. It does this on every call. That is about 128 lookups per press: cheap, always current, and no layout-change notification to handle. The ASCII-capable source is what macOS uses for shortcuts, so a Russian layout falls back to the last Latin one. `name` comes from `kTISPropertyLocalizedName`.
- `USKeyboardLayout` is a fixed table equal to today's character entries in `keyCodes`. It is the fallback when layout data is missing, and a test fixture.
- Character matching is case-insensitive for letters: the layout's unmodified output is lowercase.

### Sending resolves at press time

`static func resolve(_ combo: KeyCombo, layout: KeyboardLayout) -> Result<(UInt16, CGEventFlags), KeyResolutionError>`: `.named(code)` passes through, `.character(c)` goes through `layout.keyCode(typing:)`. A miss returns an error that `perform` turns into `.failed("keys '<text>': keyboard layout '<name>' has no key for '<c>'")`, which the menu already shows. `post` takes the resolved code. `SystemActionPerformer` takes a `layout` in its initializer, defaulting to `SystemKeyboardLayout()`. `ActionTests` use a fake German layout.

### Pure mapping from event data to a recording result

In `KeyRecorder.swift`:

```swift
enum Recording: Equatable {
    case combo(KeyCombo)
    case unsupported(keyCode: UInt16)
}
static func recording(keyCode: UInt16, flags: NSEvent.ModifierFlags, layout: KeyboardLayout) -> Recording
```

It checks the named-key codes first. Otherwise it asks `layout.character(forKeyCode:)` and accepts the character only if `parse` knows it as a name; anything else is `.unsupported`. It maps `.command`, `.control`, `.option`, `.shift`, `.function` to modifiers, and drops `.function` when the key is an F-key, arrow, home, end, page up, page down or forward delete. macOS sets `.function` on those keys whether or not fn is held, so a held fn cannot be detected for them. For every other key, `.function` appears only when fn is held, so it is kept. `KeyRecorderTests` covers this with the fake German layout, without AppKit windows.

Alternative: track the physical fn key through `flagsChanged` with key code 0x3F. Rejected: on laptops fn+Delete arrives as forward delete and fn+F12 as F12, so a physically held fn still yields the key the user meant without `fn`.

### Recorder view uses a local event monitor

A SwiftUI view with three states: idle (shows the value, or "Click to record" in secondary style), recording (shows "Type shortcut…" or the held modifiers, accent border), and text (the existing `TextField` with a Done button). Clicking the idle field starts recording.

While recording, `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown])` handles events:
- `keyDown`: Esc (0x35) with no modifiers cancels. Otherwise call `recording(keyCode:flags:layout:)`; on `.combo` write `combo.text` to the value and stop; on `.unsupported` show the message and stay in recording. Return `nil` so the event never reaches menus or `keyboardShortcut` handlers. Local monitors run before key-equivalent dispatch, so Cmd-S and Cmd-W are swallowed.
- `flagsChanged`: update the held-modifier display. Return `nil`.
- Mouse down: stop recording and return the event, so the click lands where the user clicked. Clicks on the recorder itself are filtered by checking the hit view or by toggling via the button's own action.

Recording also stops on `NSWindow.didResignKeyNotification` and when the view disappears or the inspected key index changes (`.onChange(of: index)` / `.onDisappear`). Remove the monitor in every stop path.

Alternative: an `NSViewRepresentable` that becomes first responder and overrides `keyDown` and `performKeyEquivalent`. Rejected: Cmd-W and menu items would still need special cases, and focus handling in a SwiftUI `Form` is fiddly. The monitor is the approach the issue names and needs no permission.

### Clear and text mode

Next to the field: a clear button (`xmark.circle.fill`, shown only when the value is non-empty) that sets the value to `""`, and an "Edit as Text" button that switches to the `TextField`. The text field keeps the hint line about modifiers. The value stays a plain string, so validation and live preview work unchanged.

## Risks / Trade-offs

- [Some combos never reach the app: Cmd-Space, Cmd-Tab, Cmd-Shift-3, and F-keys sent as media keys] → The hint text says so and points to Edit as Text.
- [Existing configs change meaning on non-US layouts] → This is the fix: they now send the character written. US-layout users see no change. `docs/config.md` states the rule.
- [Some characters need a modifier on some layouts: `[` and `/` on German] → The press fails with a menu error naming the character and layout, instead of sending a different key.
- [On French AZERTY the top-row digits need Shift, so `cmd+1` would fail] → Unverified how macOS itself matches Cmd-digit shortcuts on AZERTY. A Shift-layer fallback can be added later without changing the config format.
- [A stale monitor would swallow all typing in the app] → Every stop path removes the monitor. The manual check covers switching keys and closing the window mid-recording.
- [`.function` is also set for keys like Help and keypad Clear] → Those have no config name, so they are `.unsupported` anyway.
