# Configuration

The app reads `~/.config/streamdeck/config.yaml`. If the file does not exist, the app creates a starter config on launch. Saved changes apply within a second. If a save has errors, the deck keeps the last valid config, and the menu-bar menu lists the errors with line numbers.

You can edit the file by hand, as described below, or with the config editor.

## Config editor

**Edit Config…** in the menu-bar menu opens the editor. It edits everything in this file: keys, pages (add, rename, delete) and settings (brightness, default page, app pages).

On Linux, `streamdeckd` serves the same editor to a web browser. It has the same rules for drafts, errors, saving and external changes, and it needs a one-time pairing at the deck. See [Web editor](../README.md#web-editor). The points below describe the Mac editor; the web editor differs where a browser can't do the same: icons and images are typed as paths, the Material Symbols picker replaces the SF Symbols catalog, and `fn` and browser-reserved shortcuts are typed instead of recorded.

- **Live preview.** The deck shows your changes as you make them. `config.yaml` changes only when you click **Save** (Cmd-S). **Revert** returns to the saved file. Closing the window with unsaved changes asks whether to save or discard them.
- **Icons.** For a Material Symbol, type its name, such as `play_arrow`, and turn on **Filled** for the filled style. **Browse** opens Google's catalog. A name the app doesn't know is marked in red. For an SF Symbol, click **Choose…** to browse every symbol by category or search by name or keyword. Click one to use it.
- **Keystrokes.** Click the Keys field and press the combination. The field fills in the config text, for example `cmd+shift+m`, `f12` or `ctrl+alt+left`. Esc cancels; clicking elsewhere or switching keys stops recording. While recording, editor shortcuts such as Cmd-S are recorded instead of run. Letters follow your active keyboard layout. F-keys and arrows never record `fn`, because macOS adds it on its own; other keys record `fn` only when you hold it. A key without a config name, such as a keypad key or `ö`, shows a message instead. Shortcuts macOS keeps for itself, such as Cmd-Space or Cmd-Tab, never reach the editor: use **Edit as Text** and type them. The clear button empties the field.
- **Errors** appear next to the key, page or setting they belong to. Save stays disabled until they are fixed, and the deck keeps showing the last valid state.
- **Selecting keys from the deck.** While the editor window is in front, the deck shows the page you are editing. Pressing a key selects it in the editor instead of running its action. Switch to another app and the deck works normally again.
- **Renaming a page** updates every key, app page and default page that points at it. A page that is still in use cannot be deleted. The editor lists where it is used.
- **Comments are not kept.** The editor writes the file in a fixed format: one line per key, keys in order, no comments. The first save over a file you edited by hand asks first and copies the old file to `config.yaml.bak`.
- **Editing the file while the editor is open.** Without unsaved changes, the editor reloads the file. With unsaved changes, it asks whether to reload or keep yours. While the editor has unsaved changes, the deck keeps showing them.

## Full example

Every field appears in this example. A test loads it, so it stays valid.

```yaml
brightness: 60            # 0-100, default 70
default_page: home        # required; shown at start and for apps without a mapping

app_pages:                # optional; bundle ID -> page shown when that app is in front
  com.apple.Safari: browser
  com.apple.dt.Xcode: xcode

pages:                    # required; page name -> page
  home:
    keys:                 # key index 0-14 -> key definition; undefined keys are black
      0: { icon: sf:terminal, label: Terminal, action: { open: /System/Applications/Utilities/Terminal.app } }
      1: { icon: icons/zoom.png, label: Zoom, action: { open: /Applications/zoom.us.app } }
      2: { label: Deploy, background: "#B00020", action: { run: "~/bin/deploy.sh" } }
      3: { icon: ms:mic_off, action: { keys: cmd+shift+m } }
      4: { icon: ms:music_note, label: Media, action: { page: media } }
      5: { image: art/cover.jpg, icon: ms:play_arrow.fill, label: Album, action: { media: playpause } }
      14:
        label: "--:--"
        dynamic: { run: "date +%H:%M", every: 30s }

  media:
    keys:
      0: { icon: ms:play_pause, action: { media: playpause } }
      1: { icon: ms:skip_next.fill, action: { media: next } }
      14: { icon: ms:arrow_back, label: Back, action: { page: back } }

  browser:
    keys:
      0: { icon: sf:arrow.clockwise, label: Reload, action: { keys: cmd+r } }

  xcode:
    keys:
      0: { icon: sf:play.fill, label: Run, action: { keys: cmd+r } }
      1: { icon: sf:hammer.fill, label: Build, action: { keys: cmd+b } }
```

## Key layout

```
 0  1  2  3  4
 5  6  7  8  9
10 11 12 13 14
```

## Key fields

All fields are optional.

| Field | Value |
|---|---|
| `icon` | `ms:<name>` for a Material Symbol, `ms:<name>.fill` for its filled style, `sf:<name>` for an SF Symbol (macOS only), or a PNG/JPEG path. Relative paths resolve against `~/.config/streamdeck/`, `~` expands. See [Symbols](#symbols). |
| `image` | PNG/JPEG path, drawn across the whole key under `icon` and `label`. Same path rules as `icon`; symbols are not allowed. See [Images](#images). |
| `label` | Text below the icon, or centered without an icon. Shrinks, wraps to two lines, then truncates. Characters the bundled font lacks, such as emoji, show as a box. |
| `background` | Hex color `#RRGGBB`. Default black. |
| `action` | What a press does. Exactly one of the types below. |
| `dynamic` | `run` (shell command) and `every` (duration). The command's output replaces `label`, or sets `label`, `icon`, `image` and `background` when it prints JSON. See [Dynamic keys](#dynamic-keys). |

## Symbols

Symbol icons are drawn in white.

- **Material Symbols** (`ms:`) are built into the app and look the same on macOS and Linux. Find names in the [Material Symbols catalog](https://fonts.google.com/icons?icon.set=Material+Symbols). Names use underscores, for example `ms:play_arrow`, `ms:skip_next` or `ms:lightbulb`. Add `.fill` for the filled style, `ms:lightbulb.fill`. The style is Outlined, weight 400. Use `ms:` for configs you share between machines.
- **SF Symbols** (`sf:`) are Apple's, and only macOS can draw them. Browse them with Apple's SF Symbols app or the config editor. On Linux, an `sf:` icon shows a dashed placeholder and the problem is reported. The rest of the config still works.

An unknown symbol name shows the same placeholder, and the problem is listed in the menu.

## Images

`icon` is drawn inside a fixed box: 48x48 px, or 44x40 px above a label. To fill the whole 72x72 px key, use `image`.

- The image covers the key and keeps its aspect ratio. An image that is not square is cropped at the center.
- Use a square image of at least 72x72 px. Larger images work but take longer to load.
- `icon` and `label` are drawn on top. With an image, the label gets a drop shadow.
- A missing or unreadable image file is left out, and the menu lists it.

## Actions

Actions fire when the key goes down. Holding a key does not repeat the action.

| Action | Example | Effect |
|---|---|---|
| `run` | `{ run: "say hello" }` | Runs the command in your login shell, in the background. A non-zero exit shows up in the menu. |
| `open` | `{ open: "https://example.com" }` | Opens a URL, file, folder or app, like `open` in Terminal. On Linux, see [Linux](#linux). |
| `keys` | `{ keys: cmd+shift+m }` | Sends a key combination to the frontmost app. Needs Accessibility permission on macOS. |
| `media` | `{ media: playpause }` | Sends a media key. Needs Accessibility permission on macOS. |
| `page` | `{ page: media }`, `{ page: back }` | Switches page, or returns to the previous one. |

**Key combinations**: modifiers `cmd` (or `command`, `super`, `meta`), `shift`, `alt` (or `option`), `ctrl`, `fn`, plus exactly one key, joined by `+`. Key names:
- letters `a`-`z` and digits `0`-`9`
- `f1`-`f20`
- `space`, `return`, `tab`, `esc`, `delete`, `forwarddelete`
- `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`
- punctuation such as `-`, `=`, `[`, `]`, `;`, `'`, `,`, `.`, `/`, `` ` ``

Letters, digits and punctuation mean the character on your active keyboard layout, so `cmd+z` is undo on QWERTZ as on QWERTY. With a non-Latin layout such as Russian active, the Latin layout macOS uses for shortcuts applies. Named keys (`return`, `esc`, `space`, `f1`-`f20`, arrows and the rest) are the same on every layout.

A character your layout can't type without a modifier, such as `[` on a German layout, can't be sent. Pressing the key sends nothing and the menu shows `keyboard layout 'German' has no key for '['`.

**Media keys**: `playpause`, `next`, `previous`, `volumeup`, `volumedown`, `mute`, `brightnessup`, `brightnessdown`.

### Linux

`streamdeckd` reads the same file, so one config can serve a Mac and a Steam Machine. Use `ms:` icons for keys both should show. A few actions work differently:

- **`keys` and `media`** go to the focused window, including a game in SteamOS Game Mode, through a virtual keyboard. They need the udev rules from the install script, not a permission prompt. `cmd` is the Super key (the Windows or Steam logo key); `super` and `meta` are the same modifier and read better in a Linux config. `alt`, `ctrl` and `shift` are the left keys.
- **`fn`** has no Linux equivalent. A config with `fn` still loads. Pressing such a key sends nothing, and the key shows the error dot.
- **Keyboard layout.** Characters follow the system's XKB layout: the one gamescope uses in Game Mode, otherwise the one set with `localectl`. With a non-Latin layout, or when no layout is set, `us` applies.
- **`open`** passes `steam://` URLs to the Steam client and everything else to `xdg-open`.

Launch a game with its Steam AppID:

```yaml
0: { icon: ms:sports_esports, label: Dota 2, action: { open: "steam://rungameid/570" } }
1: { icon: ms:storefront, label: Store, action: { open: "steam://store" } }
2: { icon: ms:lock, label: Lock, action: { keys: super+l } }
```

The AppID is the number in the game's store page URL, `store.steampowered.com/app/<AppID>/…`. [SteamDB](https://steamdb.info) lists them too. A non-Steam game added to Steam gets a generated ID instead: in desktop mode, choose **Manage → Add desktop shortcut** for it and read the `steam://rungameid/…` URL from the shortcut file.

## Dynamic keys

```yaml
14: { dynamic: { run: "date +%H:%M", every: 30s } }
```

- The command runs only while its page is shown. A new run starts only after the previous one has finished.
- `every` accepts `ms`, `s`, `m` and `h` units. The minimum is `1s`.
- If the command fails or runs longer than 10 seconds, the key keeps its last label, icon and background and shows a red dot until a later run succeeds. The menu shows the reason.

### Output

Plain text: the first line, trimmed, replaces `label`.

JSON: output whose first non-blank character is `{` is read as a JSON object. It can set four fields:

| Field | Value |
|---|---|
| `label` | Text. `""` hides the label. |
| `icon` | Same as the `icon` key field: `ms:<name>`, `ms:<name>.fill`, `sf:<name>` or an image path. Relative paths resolve against `~/.config/streamdeck/`. |
| `image` | Same as the `image` key field: an image path drawn across the whole key. `""` removes the configured image. |
| `background` | Hex color `#RRGGBB`. |

- A field you leave out keeps the key's configured value.
- Other fields are ignored.
- Output that is not valid JSON, a field that is not a string, or a color that is not `#RRGGBB` counts as a failed run.

Example: a Home Assistant light. `HA_TOKEN` must be exported in `~/.zprofile` or `~/.zshenv`, because commands run in a login shell that does not read `~/.zshrc`.

```yaml
4: { icon: ms:lightbulb, dynamic: { run: "~/.config/streamdeck/ha-light.sh kitchen", every: 10s } }
```

```sh
#!/bin/sh
# ~/.config/streamdeck/ha-light.sh <light name>
state=$(curl -sf -H "Authorization: Bearer $HA_TOKEN" \
  "http://homeassistant.local:8123/api/states/light.$1" | jq -r .state) || exit 1
case $state in
  on) echo '{"icon":"ms:lightbulb.fill","background":"#c08000","label":"on"}' ;;
  *)  echo '{"icon":"ms:lightbulb","background":"#202020","label":"off"}' ;;
esac
```

## Pages

- `page: <name>` remembers the current page, and `page: back` returns to it. Back steps only through pages you navigated to by key.
- When the frontmost app changes, the deck shows that app's page from `app_pages`, or `default_page` if the app has none. That clears the back history. Find an app's bundle ID with `osascript -e 'id of app "Safari"'`.
- The menu-bar menu can pause automatic switching.
