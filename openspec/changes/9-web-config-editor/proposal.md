Issue: #9

# Proposal

## Why

`streamdeckd` (#7) has no screen and no editor. Today you change the Steam Machine's deck by editing `config.yaml` over ssh. A browser editor served by the daemon makes that a laptop or phone task, with the same draft, preview and validation as the Mac editor. A config can run shell commands, so the editor has to be locked to browsers the user paired at the deck.

## What Changes

- `streamdeckd` serves a web editor on the LAN, on port 3325 by default. `--web-listen <address:port>` changes the address, and `--no-web` turns it off. At startup the daemon logs the URL.
- **Editing:** one draft lives in the daemon, as one editor window does on the Mac. Every connected browser sees the same draft and gets changes live. The editor covers what the Mac editor covers: pages (add, rename with references, delete guarded by references), every key field, settings (brightness, default page, `app_pages` as text), validation next to the page, key or setting it belongs to, Save in the canonical format, a warning and `config.yaml.bak` before the first overwrite of a hand-edited file, Revert, and external changes on disk (reload, or ask when the draft has unsaved edits).
- **Live preview on the deck:** while a browser has the editor open, the deck shows the last valid draft and the page selected in that browser. Pressing a deck key selects that key in the editor and doesn't run its action. The browser's key grid shows the daemon's own rendered key images, so it matches the deck pixel for pixel. When the last browser leaves for more than 60 seconds, the deck returns to the saved config. The draft stays in memory until the daemon restarts.
- **Problems:** the editor lists the daemon's current problems (config, keystroke permission, device, key errors), the same text the journal gets.
- **Keystroke recording in the browser:** clicking the Keys field and pressing a combination writes it as config text. The Mac recording rules apply where a browser can follow them. `fn` can't be recorded, and combinations the browser keeps for itself have to be typed.
- **Material Symbols picker:** a searchable grid of every symbol the daemon can draw, with an outlined or filled style, drawn from the font built into the binary.
- **Pairing:** every config read or write needs a paired browser. On a new browser, the user asks to pair, the deck shows a 6-digit code on its keys, and the user types it in the browser. The browser then gets a long-lived token. The code expires after 2 minutes or when Cancel is pressed on the deck, and wrong guesses are limited. The editor lists paired browsers and can revoke them.
- **Serving:** the HTML, CSS and JavaScript are compiled into the binary, so it stays a single static file. HTTP comes from Hummingbird 2 on SwiftNIO, confirmed in design.

## Capabilities

### New Capabilities

- `web-editor`: the browser config editor. It covers the shared draft, editing, validation, save and backup, external changes, live preview and key selection on the deck, problem display, keystroke recording and the Material Symbols picker.
- `web-pairing`: who may use the web editor. It covers pairing with a code shown on the deck, tokens, revocation, and requests that are refused.

### Modified Capabilities

- `linux-daemon`: the daemon serves the web editor, takes `--web-listen` and `--no-web`, and logs the URL. These are added requirements on the capability from #7, which isn't archived yet.

## Impact

- Code: a new portable `DeckEditor` target with the editing logic (draft, validation, page operations, save with backup, external changes) and JSON coding for `ConfigDocument`. A new portable `DeckWeb` target with the HTTP server, the API, server-sent events, pairing and token storage. A new C target `CWebAssets` embeds the web files with `#embed`, as `CStb` does for fonts. `DeckEngine` gets the last rendered image of each key and a key overlay used for the pairing code. `streamdeckd` wires it up and routes config file changes to the editor while a browser holds the deck.
- The Mac app and its SwiftUI editor don't change. Sharing `DeckEditor` and the web editor with macOS is #10.
- Dependencies: Hummingbird 2.x (with SwiftNIO, swift-log and related packages). It is the first new Swift dependency since Yams. The static binary gets bigger, and the size is recorded in tasks.
- Tests: `DeckEditorTests` and `DeckWebTests` (in-process with HummingbirdTesting) run on Linux in Docker. The browser's pure JavaScript (keystroke mapping) is tested with Node in Docker by a new `scripts/test-web.sh`.
- Docs: a README section for the web editor (URL, pairing, revoking, flags, security notes) and the `docs/config.md` notes that apply.
- Out of scope: HTTPS (plain HTTP on a trusted LAN, see design), uploading image files from the browser, wiring the Mac app (#10), and Game Mode pages (#8).
