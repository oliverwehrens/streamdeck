# Configuration

The app reads `~/.config/streamdeck/config.yaml`. If the file does not exist, the app creates a starter config on launch. Saved changes apply within a second. If a save has errors, the deck keeps the last valid config, and the menu-bar menu lists the errors with line numbers.

You can edit the file by hand, as described below, or with the config editor.

## Config editor

**Edit Config…** in the menu-bar menu opens the editor. It edits everything in this file: keys, pages (add, rename, delete) and settings (brightness, default page, app pages).

- **Live preview.** The deck shows your changes as you make them. `config.yaml` changes only when you click **Save** (Cmd-S). **Revert** returns to the saved file. Closing the window with unsaved changes asks whether to save or discard them.
- **Icons.** For an SF Symbol, click **Choose…** to browse every symbol by category or search by name or keyword. Click one to use it.
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
      3: { icon: sf:mic.slash.fill, action: { keys: cmd+shift+m } }
      4: { icon: sf:music.note, label: Media, action: { page: media } }
      14:
        label: "--:--"
        dynamic: { run: "date +%H:%M", every: 30s }

  media:
    keys:
      0: { icon: sf:playpause.fill, action: { media: playpause } }
      1: { icon: sf:forward.fill, action: { media: next } }
      14: { icon: sf:arrow.uturn.left, label: Back, action: { page: back } }

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
| `icon` | `sf:<name>` for an SF Symbol (browse with Apple's SF Symbols app), or a PNG/JPEG path. Relative paths resolve against `~/.config/streamdeck/`, `~` expands. |
| `label` | Text below the icon, or centered without an icon. Shrinks, wraps to two lines, then truncates. |
| `background` | Hex color `#RRGGBB`. Default black. |
| `action` | What a press does. Exactly one of the types below. |
| `dynamic` | `run` (shell command) and `every` (duration). The command's output replaces `label`, or sets `label`, `icon` and `background` when it prints JSON. See [Dynamic keys](#dynamic-keys). |

## Actions

Actions fire when the key goes down. Holding a key does not repeat the action.

| Action | Example | Effect |
|---|---|---|
| `run` | `{ run: "say hello" }` | Runs the command in your login shell, in the background. A non-zero exit shows up in the menu. |
| `open` | `{ open: "https://example.com" }` | Opens a URL, file, folder or app, like `open` in Terminal. |
| `keys` | `{ keys: cmd+shift+m }` | Sends a key combination to the frontmost app. Needs Accessibility permission. |
| `media` | `{ media: playpause }` | Sends a media key. Needs Accessibility permission. |
| `page` | `{ page: media }`, `{ page: back }` | Switches page, or returns to the previous one. |

**Key combinations**: modifiers `cmd`, `shift`, `alt` (or `option`), `ctrl`, `fn`, plus exactly one key, joined by `+`. Key names:
- letters `a`-`z` and digits `0`-`9`
- `f1`-`f20`
- `space`, `return`, `tab`, `esc`, `delete`, `forwarddelete`
- `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`
- punctuation such as `-`, `=`, `[`, `]`, `;`, `'`, `,`, `.`, `/`, `` ` ``

Letters map to US key positions.

**Media keys**: `playpause`, `next`, `previous`, `volumeup`, `volumedown`, `mute`, `brightnessup`, `brightnessdown`.

## Dynamic keys

```yaml
14: { dynamic: { run: "date +%H:%M", every: 30s } }
```

- The command runs only while its page is shown. A new run starts only after the previous one has finished.
- `every` accepts `ms`, `s`, `m` and `h` units. The minimum is `1s`.
- If the command fails or runs longer than 10 seconds, the key keeps its last label, icon and background and shows a red dot until a later run succeeds. The menu shows the reason.

### Output

Plain text: the first line, trimmed, replaces `label`.

JSON: output whose first non-blank character is `{` is read as a JSON object. It can set three fields:

| Field | Value |
|---|---|
| `label` | Text. `""` hides the label. |
| `icon` | Same as the `icon` key field: `sf:<name>` or an image path. Relative paths resolve against `~/.config/streamdeck/`. |
| `background` | Hex color `#RRGGBB`. |

- A field you leave out keeps the key's configured value.
- Other fields are ignored.
- Output that is not valid JSON, a field that is not a string, or a color that is not `#RRGGBB` counts as a failed run.

Example: a Home Assistant light. `HA_TOKEN` must be exported in `~/.zprofile` or `~/.zshenv`, because commands run in a login shell that does not read `~/.zshrc`.

```yaml
4: { icon: sf:lightbulb, dynamic: { run: "~/.config/streamdeck/ha-light.sh kitchen", every: 10s } }
```

```sh
#!/bin/sh
# ~/.config/streamdeck/ha-light.sh <light name>
state=$(curl -sf -H "Authorization: Bearer $HA_TOKEN" \
  "http://homeassistant.local:8123/api/states/light.$1" | jq -r .state) || exit 1
case $state in
  on) echo '{"icon":"sf:lightbulb.fill","background":"#c08000","label":"on"}' ;;
  *)  echo '{"icon":"sf:lightbulb","background":"#202020","label":"off"}' ;;
esac
```

## Pages

- `page: <name>` remembers the current page, and `page: back` returns to it. Back steps only through pages you navigated to by key.
- When the frontmost app changes, the deck shows that app's page from `app_pages`, or `default_page` if the app has none. That clears the back history. Find an app's bundle ID with `osascript -e 'id of app "Safari"'`.
- The menu-bar menu can pause automatic switching.
