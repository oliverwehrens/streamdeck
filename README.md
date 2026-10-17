# StreamDeck

A macOS menu-bar app that drives an Elgato Stream Deck over USB, without Elgato's software. Keys, pages and actions come from a YAML file that reloads when you save it.

Supported hardware: **Stream Deck Original V2** (15 keys, USB product ID `0x006d`). Other models are ignored.

## Requirements

- macOS 14 or later
- Xcode command line tools with Swift 6 (`swift --version`)
- An Apple Development signing identity in your keychain. Check with `security find-identity -v -p codesigning`. The app needs a stable signature, otherwise macOS forgets its Accessibility permission after every rebuild.

## Build

```sh
./scripts/bundle.sh
```

This builds a release binary and writes a signed `build/StreamDeck.app`. To pick a different identity:

```sh
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/bundle.sh
```

Run the tests with:

```sh
swift test
```

## Install

1. **Quit the Elgato Stream Deck app** and remove it from login items. Only one app can drive the deck at a time. If Elgato's app is running, the menu says so.
2. Copy the app to `/Applications`:
   ```sh
   cp -R build/StreamDeck.app /Applications/
   open /Applications/StreamDeck.app
   ```
   A grid icon appears in the menu bar. There is no Dock icon.
3. Optional: choose **Launch at Login** in the menu.

Always run the copy in `/Applications`. macOS ties permissions and the login item to the app's path and signature.

## Accessibility permission

Keys that send keystrokes (`keys:`) or media keys (`media:`) need Accessibility permission. The first time you press one, the menu shows the problem and offers **Open Accessibility Settings…**. Enable **StreamDeck** there and press the key again.

Shell commands, opening apps or URLs, and page switching work without it. Input Monitoring permission is not needed.

## Configure

The config lives at `~/.config/streamdeck/config.yaml`. The first launch creates a starter config. **Open Config** in the menu opens it for editing.

```yaml
default_page: home
pages:
  home:
    keys:
      0: { icon: sf:terminal, label: Terminal, action: { open: /System/Applications/Utilities/Terminal.app } }
      1: { icon: sf:mic.slash.fill, action: { keys: cmd+shift+m } }
      14: { dynamic: { run: "date +%H:%M", every: 30s } }
```

See [docs/config.md](docs/config.md) for every field, action and option.

## Troubleshooting

| Symptom | Check |
|---|---|
| Menu says "Not connected" | Is the deck plugged in directly? Is the Elgato app quit? |
| Keys stay dark after a config edit | The menu lists config errors with line numbers. The deck keeps the last valid config. |
| Keystroke keys do nothing | Accessibility permission (see above). After a rebuild signed with a different identity, remove and re-add StreamDeck in Accessibility settings. |
| A shell command works in Terminal but not on the deck | Commands run in your login shell (`$SHELL -l -c`), so PATH comes from your shell profile, not from interactive-only files such as `.zshrc`. |

## Project layout

| Path | Contents |
|---|---|
| `Sources/DeckHID` | USB HID transport and report codec ([docs/protocol.md](docs/protocol.md)) |
| `Sources/DeckConfig` | YAML parsing, validation, file watching |
| `Sources/DeckRender` | Key image rendering |
| `Sources/DeckEngine` | Pages, actions, dynamic keys |
| `Sources/StreamDeckApp` | Menu-bar app |
| `openspec/` | Specs and change history |

## License

MIT. See [LICENSE](LICENSE).
