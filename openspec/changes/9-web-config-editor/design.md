# Design

## Context

See proposal.md for the motivation. Here is what exists after #7.

- **`streamdeckd`** wires `DeckEngine` with the Linux transport, actions and renderer, runs `ConfigWatcher`, and calls `dispatchMain()`. The engine is `@MainActor`. It already has `editorPage` and `onEditorKeyPress` for an editor, and a status key (key 14) for problems that belong to no key.
- **Editing logic** is in `EditorModel`, inside the macOS-only `StreamDeckApp` target. The model holds the draft, the saved document, errors, the last valid config, unreadable and disk errors, a pending disk document, save with backup, and the page operations. `ConfigDocument` (portable, in `DeckConfig`) does the page operations themselves (`addPage`, `renamePage`, `deletePage`, `references`), YAML read and write, and `isEditorWritten`.
- **The Mac app** sends file changes to the editor instead of the engine while the editor is open (`AppDelegate`). When the editor closes, it reapplies `watcher.config`.
- **Rendering**: `KeyRenderer.render` returns the device JPEG, rotated 180°. The engine sends a key to the transport only while connected.
- **Embedding**: `CStb/fonts.c` embeds the fonts and the Material Symbols codepoints file with C23 `#embed`.

Constraints:

- **The binary is a static musl binary** (#7). Every new dependency has to build with the Swift Static Linux SDK. Yams 5.x didn't, which is a warning.
- **The binary is a single file**, so SwiftPM resource bundles are out. They'd be a directory next to the binary.
- **The development machine has no Swift and no Mac.** Builds and tests run in the `swift:6.4.2` Docker image. Node also runs in Docker.
- **It's plain HTTP on a LAN.** The page isn't a secure context, so `navigator.clipboard`, `navigator.keyboard.getLayoutMap()` and similar APIs are unavailable.

## Goals / Non-Goals

**Goals:**
- `streamdeckd` meets the web-editor, web-pairing and linux-daemon deltas.
- The editing logic is portable, in one place that #10 can reuse.
- The API, pairing, token storage and the browser's keystroke mapping are covered by tests in Docker. Phone and Steam Machine behavior is a manual checklist.
- The macOS app behaves exactly as before.

**Non-Goals:**
- HTTPS (see Risks), image upload, the SF Symbols catalog in the browser, editing YAML as text in the browser.
- Moving the Mac `EditorModel` onto `DeckEditor`. That's #10, which also decides whether the SwiftUI editor stays. Until then the logic exists twice, and the Mac copy doesn't change.
- Several independent drafts, or merging concurrent edits field by field. The last write to a key or setting wins.

## Decisions

### Targets

```
DeckEditor     portable  ConfigEditor (draft, validation, pages, save, external changes),
                         JSON coding of ConfigDocument and ConfigError
CWebAssets     portable  C target: #embed of Sources/CWebAssets/web/* (html, css, js)
DeckWeb        portable  HTTP server, routes, SSE hub, presence, pairing, token store, SHA-256
streamdeckd    Linux     adds flags, starts DeckWeb, routes watcher updates
DeckEditorTests, DeckWebTests  portable
```

`DeckEditor` depends on `DeckConfig`. `DeckWeb` depends on `DeckEditor`, `DeckEngine`, `DeckRender` (for symbol names and fonts), `CWebAssets`, `DeckSupport` and Hummingbird. Both are in the portable part of `Package.swift`, so #10 only has to wire them up. The Mac app doesn't link them yet.

*Alternative:* put everything in `streamdeckd`. That's simpler today, but #10 would have to move it out again, and an executable target can't be tested directly.

### HTTP server: Hummingbird 2

The issue left this for the design to confirm. Hummingbird 2 (on SwiftNIO) is confirmed, on one condition (task 1.1): it has to build with the musl Static Linux SDK and produce a static binary before anything else is built on it.

- The HTTP parser is SwiftNIO's (llhttp). This server sits on a network and controls a machine that runs shell commands, so a hand-written parser is the wrong place to save code.
- `HummingbirdTesting` runs the router in-process, so the API and pairing tests need no sockets.
- Streaming response bodies cover server-sent events, so there's no WebSocket package.
- It's async/await native and has a small surface compared with Vapor.

*Fallback, if 1.1 fails:* SwiftNIO's `NIOHTTP1` directly, with a small router. The parser and NIO stay; only the routing and test helpers get written by hand. The API and the rest of this design don't change.

*Alternatives:* a hand-written HTTP/1.1 server over sockets (no dependency, but a security-sensitive parser to own), and Vapor (larger, more dependencies, the same NIO underneath).

The server runs on NIO's threads. Each handler that touches the editor, engine or pairing calls `await MainActor.run { … }`, since `dispatchMain()` serves the main actor. All shared state lives on the main actor, so there are no locks besides the existing ones.

### ConfigEditor (DeckEditor)

`@MainActor final class ConfigEditor` is ported from `EditorModel` without the UI state (selected page and key, settings sidebar) and without Observation:

- State: `saved`, `draft`, `errors`, `lastValid`, `unreadable`, `diskErrors`, `pendingDiskDocument`, `revision` (incremented on every change), `isDirty`, `canSave`, `needsOverwriteWarning`.
- Operations: `setKey(page:index:_:)`, `setSettings(brightness:defaultPage:appPages:)`, `addPage`, `renamePage`, `deletePage`, `save(confirmOverwrite:)`, `revert()`, `fileChanged()`, `resolveDiskChange(reload:)`.
- Validation is synchronous after every operation (`ConfigLoader.load(yaml: draft.yaml(), …)`), which is a few milliseconds. The browser debounces typing, so the server doesn't. When `lastValid` changes, `onPreview(config)` fires. `onChange` fires on every revision.
- `save(confirmOverwrite: false)` on a hand-written file throws `.needsOverwriteConfirmation` and doesn't write. With `true`, it copies to `config.yaml.bak` and writes. The write is atomic, as on the Mac. `saveNeedsOverwriteWarning` reads the file at save time, so a file edited over ssh after the last save is caught.

The tests are ported from `EditorModelTests` (draft, validation, save, backup, external changes, rename, delete), plus `revision` and `onPreview` counting.

**JSON wire format.** `Codable` extensions in `DeckEditor` (not in `DeckConfig`, which stays format-agnostic):

```json
{ "brightness": "80", "defaultPage": "home",
  "pages": [ { "name": "home", "keys": { "0": { "icon": "ms:terminal", "label": "Term",
      "action": { "kind": "run", "value": "open -a Terminal" },
      "dynamic": { "run": "date +%H:%M", "every": "30s" } } } } ],
  "appPages": [ { "app": "com.apple.Safari", "page": "browser" } ] }
```

All values are strings, as in `ConfigDocument`, so invalid input comes back unchanged. Absent fields are `null` or omitted. `ConfigError` is encoded as `{message, line, page, key}`.

### API

Everything is under `/api`, JSON in and out. Every route needs a valid token (web-pairing) except those marked *open*.

| Method and path | Purpose |
| --- | --- |
| `GET /api/state` | `{revision, draft, isDirty, canSave, errors, unreadable, diskErrors, pendingDisk, needsOverwriteWarning, status, holder}` |
| `GET /api/events` | Server-sent events, see below |
| `PUT /api/draft/pages/{page}/keys/{index}` | Body: a key or `null`. Sets or clears a key |
| `PUT /api/draft/settings` | `{brightness, defaultPage, appPages}` |
| `POST /api/draft/pages` | `{name}`. `400 {error: empty\|reserved\|taken}` |
| `POST /api/draft/pages/{page}/rename` | `{name}`, with the same errors |
| `DELETE /api/draft/pages/{page}` | `409 {references: [...]}` when referenced |
| `POST /api/save` | `{confirmOverwrite}`. `409 {needsOverwriteConfirmation: true}`, or `422` with errors |
| `POST /api/revert` | |
| `POST /api/disk-change` | `{reload}` |
| `POST /api/presence` | `{tab, visible, page}`, see "Holding the deck" |
| `GET /api/symbols` | `[[name, codepoint], …]`, from the embedded codepoints file |
| `GET /api/clients`, `DELETE /api/clients/{id}` | Paired browsers |
| `POST /api/pair/start` *open* | Starts pairing. `409` without a deck, `429` while locked out |
| `POST /api/pair` *open* | `{code, name}`. Sets the token cookie |
| `POST /api/logout` | Revokes the caller's own token |

Every mutating response returns the new full state, so the browser applies one shape everywhere. The state is a few kilobytes. Page names in paths are percent-encoded.

### Events

`GET /api/events` is an SSE stream (`text/event-stream`). On connect it sends `state`, then:

- `state`: the full state, sent whenever the editor's `revision`, the engine status or the holder changes.
- `key`: `{index, jpeg}` (base64), sent whenever the engine renders a different image for a key. All 15 are sent on connect.
- `deckKey`: `{index}`, sent only to the tab that holds the deck selection, when a deck key is pressed.
- A comment line every 15 s, so phones and proxies keep the connection open and dead connections show up.

`EventSource` reconnects by itself. Each connect starts with full state, so there's no replay. The browser opens one stream per tab and gives it a random tab ID (`?tab=`) that it also uses for presence.

### Key images: the device's own JPEG, rotated in CSS

`DeckEngine` gets `public private(set) var keyImages: [Int: Data]` and `onKeyImage: ((Int, Data) -> Void)?`. `send(_:to:)` records the image and calls the hook whether or not a device is connected. Writing to the transport still needs a connection. The browser shows each image in an `<img>` with `transform: rotate(180deg)`. That makes the grid byte-identical to the deck, with no second render and no re-encoding. A key image is about 2-4 KB, and base64 over SSE is fine at that size.

*Alternative:* render upright PNGs for the browser with `KeyRenderer.preview`. That's a second render of every key, a PNG encoder, and a chance for the two to drift.

### Holding the deck

`EditorPresence` (main actor) tracks the open SSE streams by tab, which tabs are visible, and the most recent visible tab.

- **Hold:** the web editor holds the deck from the first stream opening until 60 s after the last one closes. Gaining the hold calls `engine.configLoaded(editor.lastValid)` when there is one, and `editor.onPreview` goes to the engine. Losing it sets `editorPage = nil`, clears `onEditorKeyPress`, and applies the watcher's latest result (`configLoaded` or `configFailed`). The 60 s grace covers reloads and short phone locks.
- **Selection:** `POST /api/presence` reports `{tab, visible, page}` on `visibilitychange`, on `focus`, and on page selection. The most recent visible tab owns `engine.editorPage` and gets `deckKey` events through `onEditorKeyPress`. When no tab is visible, both are cleared, so the deck navigates and runs actions normally, on the draft. A tab whose stream closes counts as hidden.
- **File changes:** `streamdeckd` sends every `ConfigWatcher` update to `presence.holdsDeck ? editor.fileChanged() : engine`. It keeps the latest update for the moment the hold ends. That mirrors `AppDelegate`.

The state includes `holder: {tab, page}`, so a tab that isn't the holder can say "The deck is showing page X for another editor." Selecting a page or focusing the tab takes the deck over.

### Pairing

**The deck overlay.** `DeckEngine` gets `public var overlay: [Int: KeyAppearance]?` and `onOverlayKeyPress: ((Int) -> Void)?`. While the overlay is set, `render(key:)` draws the overlay entry (or a blank key) for every key, ahead of the status key and the editor. `handleKey` sends key-downs to `onOverlayKeyPress` and runs no actions. Clearing the overlay re-renders everything. It's generic, so other prompts can use it later.

**Pairing layout:**

```
[        ] [        ] [ms:link   ] [        ] [        ]
[        ] [  48    ] [  21      ] [  93    ] [        ]
[        ] [        ] [ Pair this] [        ] [ms:close ]
                        browser?               Cancel
```

There are two digits per key, as a large label on a dark blue background. The code is read left to right as `482193`.

**Rules** (`PairingController`, on the main actor):

- `start` needs `engine.status.connected`. It draws 6 digits from `SystemRandomNumberGenerator` (getrandom on Linux), replaces any pending code, sets the overlay, and starts a 2 min timer. It logs `pairing requested from <ip>`.
- `complete(code)` compares in constant time. On success it clears the overlay and creates a token. On failure it counts: 5 failures kill the code, and 10 within a sliding 10 min window lock out `start` and `complete` for 10 min. Every failure and every lockout is logged.
- Cancel (key 14), a timeout, or a deck disconnect clears the code and the overlay.

**Tokens.** A token is 32 random bytes, base64url-encoded. The browser gets it once, as the cookie `streamdeck_token` (`HttpOnly; SameSite=Strict; Path=/; Max-Age=315360000`). A cookie and not a header, because `EventSource` and `<img>` can't set headers, and `HttpOnly` keeps it away from scripts. The store, `$XDG_STATE_HOME/streamdeck/web-clients.json` (default `~/.local/state/…`), holds `{id, name, sha256, created, lastUsed}` per client. It's written atomically with mode 0600 in a 0700 directory. `lastUsed` is written at most once per hour. The store lives outside `~/.config/streamdeck`, so copying or syncing a config never copies access, and the config directory watcher never sees writes to it. A token is checked by hashing it and comparing hashes in constant time. Deleting the file and restarting revokes everyone.

**SHA-256** is a small Swift implementation in `DeckWeb`, about 80 lines, tested against the NIST vectors. *Alternative:* swift-crypto, which brings BoringSSL into the static binary for one hash.

**Name:** the pairing screen fills a name field from the user agent ("Firefox on Android") and the user can change it.

### Request hardening

- **State-changing requests** (`POST`/`PUT`/`DELETE`) must have `Content-Type: application/json` and an `Origin` header equal to `http://<Host header>`. Otherwise they get `403`. That blocks cross-site form posts and `fetch`es even if `SameSite` fails. No CORS headers are ever sent.
- **DNS rebinding:** a rebinding page has its own origin, so the browser doesn't send it the cookie. It can call `pair/start` and make the deck show a code, which is a nuisance and is logged, but it can't finish without the code.
- **Bodies** are limited to 256 KB. A config document is far smaller.
- **Every response** gets `Content-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; frame-ancestors 'none'`, `X-Content-Type-Options: nosniff` and `Referrer-Policy: no-referrer`.
- **The browser** writes config strings into the DOM with `textContent` and attributes only, never `innerHTML`. Labels and commands come from a file that scripts may write.

### Static assets

The web files live in `Sources/CWebAssets/web/`: `index.html`, `app.css`, `app.js` (state, rendering, API), `keys.js` (keystroke mapping, pure), `picker.js`, `pairing.js`. `assets.c` embeds each one with `#embed` and exports a table of `{path, bytes, size}`. `DeckWeb` serves the table at `/` and `/assets/*`, with content types by extension, an `ETag` computed from a hash of the bytes at startup, and `Cache-Control: no-cache`. The Material Symbols fonts are served at `/assets/material-outlined.ttf` and `/assets/material-filled.ttf`, straight from the existing `CStb` accessors, so the fonts in the binary aren't duplicated.

The frontend is plain ES modules with no build step and no third-party code. It's one page of a few hundred lines per module. A framework would need a bundler and a vendored copy, and the UI doesn't need one.

**Layout:** on a wide screen the page list, grid and inspector sit side by side. Below 700 px, the pages become a select menu, the grid takes the full width, and the inspector sits below the grid. Save and Revert stay in a sticky top bar.

**The Material Symbols picker** loads `/api/symbols` once, draws each symbol as its codepoint in the served font (no ligature support needed), filters by substring as the user types, and shows the first 400 matches with a count. It has a Filled toggle. There are no categories, because the font's codepoints file has none.

### Keystroke recording in the browser

`keys.js` exports `record(event) → {combo} | {unsupported} | {ignore} | {cancel}`, a pure function over the event's `code`, `key` and modifier flags. It is tested with Node.

1. **Modifiers:** `metaKey` → `cmd`, `ctrlKey` → `ctrl`, `altKey` → `alt`, `shiftKey` → `shift`, in that order. A `keydown` for a modifier alone (`code` `Meta*`/`Control*`/`Alt*`/`Shift*`) returns `ignore`, and the field shows the modifiers that are held.
2. **Esc** with no modifiers returns `cancel`.
3. **Named keys** come from a table over `event.code`: `Enter`→`return`, `Tab`, `Space`, `Backspace`→`delete`, `Delete`→`forwarddelete`, `Escape`→`escape` (with modifiers), arrows, `Home`, `End`, `PageUp`, `PageDown`, `F1`…`F20`. The names match `KeyCombo.canonicalNames`, and a test reads that list from a fixture generated by a Swift test so the two can't drift.
4. **Characters:** if `event.key` is one character that the config allows as a character (`a`…`z`, digits, `` -=[]\;',./` ``), take it, lowercased. That's the character on the user's own layout, so German Ctrl-Z gives `z`. If Shift or Alt changed it into something outside that set (`!`, `ø`), use the US character for `event.code` (`Digit1`→`1`, `KeyQ`→`q`, `Slash`→`/`). Without `getLayoutMap()` that's the best available, and it's right for every layout on digits and for Latin layouts on most keys.
5. **Everything else** (numpad keys, `IntlBackslash`, dead keys, IME composition) returns `unsupported`.

The handler calls `preventDefault()` on every key-down while recording, so browser shortcuts that pages may override (Ctrl-S, Ctrl-F) are recorded. Shortcuts the browser never gives to pages (Ctrl-W, Ctrl-T, Ctrl-N, and Super combinations the desktop grabs) can't be recorded. The field's hint says so, and Edit as Text is the way around it, as it is for `fn`.

### Daemon changes

- **Flags:** `--web-listen <host:port>` (default `0.0.0.0:3325`) and `--no-web`, parsed by hand, with no ArgumentParser dependency. Any other argument prints usage and exits 2.
- **Startup:** build `ConfigEditor(configURL:)` and `loadFromDisk()`, then `PairingController`, `EditorPresence` and `WebServer`, and start the server in a `Task`. If binding fails, set `engine.setWebProblem("web editor: cannot listen on 0.0.0.0:3325: address in use")`. That's a new problem source, `.web`, which counts for the status key with the label `Web`. Then log the URLs: `gethostname` + `.local`, and each non-loopback IPv4 address from `getifaddrs`.
- **SIGTERM:** stop the server (close streams), then shut down as before.
- **Port 3325** spells DECK on a phone keypad, and nothing common uses it.

## Risks / Trade-offs

- [Hummingbird or one of its dependencies doesn't build with the musl Static SDK] → Task 1.1 is a spike before anything else. The fallback is the `NIOHTTP1` design above. If NIO itself fails, the change stops and the design comes back for review.
- [Plain HTTP: someone on the same network can read the token and the config] → This is accepted for a home LAN and stated in the README. Pairing still keeps out anyone who can't see the deck, which is the threat the issue names. Revoking is one click. HTTPS with a self-signed certificate means warnings on every phone, so a real solution is a follow-up.
- [Binary size grows by NIO and Hummingbird] → Measured and recorded in task 8.1. The current size is 57 MB, and a size in that range is irrelevant on a Steam Machine.
- [Two browsers editing at once overwrite each other's change to the same key] → Last write wins per key or setting. Every tab sees the result within a second, so overwrites are visible. One person editing is the expected case.
- [The draft lives only in memory] → A daemon restart loses unsaved edits. The editor shows an unsaved marker, and `beforeunload` warns when a tab closes with unsaved edits. That matches the Mac app, where quitting loses the draft too.
- [The character fallback in recording uses US positions for shifted or Alt-modified keys on non-US layouts] → It affects only combinations like Shift-Alt-punctuation on non-US layouts. The value is shown before it's used, and Edit as Text corrects it.
- [Editing logic exists twice (Mac `EditorModel` and `ConfigEditor`) until #10] → `ConfigEditor`'s tests are ported from `EditorModelTests`, so the behavior matches. #10 removes one of them.
- [SSE connections from sleeping phones linger] → The 15 s heartbeat surfaces dead TCP connections, and the hold uses stream presence, so a lingering stream delays release by at most the TCP timeout. The deck still previews the draft in that case, which is harmless.

## Migration Plan

New feature, on by default after upgrading `streamdeckd`. Nothing changes in the config format or on macOS. To turn it off, edit the unit's `ExecStart` to add `--no-web` (the README shows a `systemctl --user edit` drop-in). Rollback: install the previous binary.

## Open Questions

- Whether SteamOS answers `.local` names (avahi) out of the box. The IPv4 URLs are logged anyway, and hardware testing records the answer.
- Whether Steam's in-game overlay browser can use the editor while a game runs. That would be nice to have, it's not required, and it's recorded during hardware testing.
