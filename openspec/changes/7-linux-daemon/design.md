# Design

## Context

See proposal.md for the motivation. After #5 and #6, these pieces build and test on Linux: `DeckConfig` (with an inotify watcher), `DeckHID` (`ReportCodec` and the `DeckTransport` port), `DeckEngine` (navigation, dynamic keys, `ShellRunner` with `/bin/sh` fallback, and the `ActionPerformer`, `CommandRunner`, `KeyRendering` and `KeyboardLayout` ports), and `DeckRender` (pure Swift plus stb, with fonts built in). The Mac-only parts all live in `DeckPlatformMac` and `StreamDeckApp`. The Linux daemon is the same composition with Linux parts.

Constraints:

- **Static musl binary.** The binary can't link libudev, libxkbcommon, libsystemd or D-Bus. Everything comes from syscalls, `/sys`, `/proc`, and files under `/usr/share`.
- **Swift can't import function-like C macros.** That rules out `HIDIOCSFEATURE(len)`, `UI_SET_KEYBIT` and the other ioctl request codes, which need a C shim.
- **Key codes are macOS codes.** `KeyCombo.Key.named` and `KeyboardLayout` use macOS virtual key codes.
- **The engine is `@MainActor`** and communicates by callbacks (`onStatusChange`). The Mac app runs it on the AppKit main loop.
- **The development machine has no Swift.** Builds and tests run in the `swift:6.4.2` Docker image (`scripts/test-linux.sh`). The Steam Machine is the hardware target.

## Goals / Non-Goals

**Goals:**
- `streamdeckd` meets the linux-daemon, deck-device, key-actions and deck-config deltas on a Steam Machine.
- Everything except the actual hardware and Steam behavior is covered by tests that run in Docker.
- The macOS app behaves exactly as before.

**Non-Goals:**
- Following the focused game, and `steam:` keys in `app_pages`. That's #8. The daemon passes `frontmostApp: nil` and never calls `appActivated`.
- Any network listener (#9), command-line config checking, or a tray icon.
- aarch64 builds and non-systemd init systems.
- `sf:` icons on Linux. They already draw a placeholder and report a problem, from #6.

## Decisions

### Targets

```
CLinux             C shim: hidraw/uinput ioctls, uinput setup         (Linux only)
DeckPlatformLinux  HidrawTransport, UinputKeyboard, XKBLayout,
                   LinuxActionPerformer, ResumeDetector, EvdevKeys       (Linux only)
streamdeckd        executable: wiring, main loop, signals, logging      (Linux only)
DeckPlatformLinuxTests                                                    (Linux only)
```

They go in an `#if os(Linux)` block in `Package.swift`, the mirror of the `#if os(macOS)` block. The pure parts of `DeckPlatformLinux` (the XKB parser, key-code tables, `/sys` uevent parsing, and the action routing) are written as functions over strings and file paths. That way the tests feed them fixture files and don't need devices.

*Alternative:* put Linux code in `DeckHID` and `DeckEngine` behind `#if`. That reverses #5's split, which keeps platform code in one target per platform.

### hidraw transport

- **Discovery.** It scans `/sys/class/hidraw/hidraw*/device/uevent` for `HID_ID=0003:00000FD9:0000006D`. The serial comes from `HID_UNIQ` when it's present, otherwise from feature report 0x06 as on macOS. Firmware comes from report 0x05.
- **Opening.** It opens `/dev/hidrawN` with `O_RDWR | O_CLOEXEC`. If that fails with `EACCES`, it yields `.openFailed` with a message naming the node and the udev rules. udev applies permissions shortly after it creates the node, so on hotplug, `EACCES` is retried for up to 2 s before it's reported.
- **Reading.** One dedicated thread blocks in `read()` on 512-byte reports and feeds `ReportCodec.keyStates`. `ENODEV`/`EIO` or a 0-byte read means the device was unplugged, which yields `.disconnected`. A thread, not a `DispatchSource`, because of what #5 found: blocking work on the global pool starves Swift tasks on Linux.
- **Writing.** A serial queue handles `write()` for image reports (report ID in byte 0, which is what hidraw expects for numbered reports) and `HIDIOCSFEATURE`/`HIDIOCGFEATURE` through `CLinux` for brightness, reset, serial and firmware. `stop()` runs `queue.sync` before closing, so the blank images from `DeckEngine.shutdown()` reach the device before exit.
- **Hotplug.** inotify on `/dev` for `IN_CREATE | IN_ATTRIB | IN_DELETE`, filtered to `hidraw*`. `IN_ATTRIB` catches udev changing permissions after creation. Any event triggers a rescan when no device is open. This doesn't need libudev or a netlink socket: devtmpfs nodes show up in `/dev`, and the scan reads `/sys`.

*Alternatives:* a libudev monitor (can't be linked statically). Raw netlink `NETLINK_KOBJECT_UEVENT` works too, but it reports events before udev has applied permissions, so it would need the same retry, with more code. Polling every second is simple, but it wakes a machine that's running games.

### Resume detection

The engine already has `redrawAll()`. A `ResumeDetector` thread wakes every 2 s and compares `CLOCK_BOOTTIME - CLOCK_MONOTONIC`. That gap grows only while the system is suspended. When it grows by more than 1 s, the daemon calls `redrawAll()` on the main actor after a 1 s delay, the same delay the Mac uses after wake. If the deck lost power during suspend and re-enumerated, hotplug covers it too. Both paths are idempotent.

*Alternative:* logind's `PrepareForSleep` signal over D-Bus. That needs a D-Bus client in a static binary, which is a lot of code for one signal.

### uinput keyboard

`UinputKeyboard` opens `/dev/uinput` once at startup. It enables `EV_KEY` for every evdev code it may send: the modifiers, every code the evdev tables produce, and the media keys. Then it creates a device named `streamdeckd keyboard` with `UI_DEV_SETUP`/`UI_DEV_CREATE` and keeps it for the life of the process. A combo is sent as modifiers down, key down, `SYN`, key up, modifiers up, `SYN`. Brief pauses between the events let gamescope and games that poll see the press.

If opening or creating the device fails, the daemon calls `engine.setPermissionProblem(...)` with the udev message, and the performer returns `.failed` with the same text for `keys`/`media`. That's one problem, shown on the status key. On Linux, `.needsAccessibility` is never returned.

Mapping:

- **Named keys:** a fixed table from the macOS codes in `KeyCombo.canonicalNames` to evdev codes (`return` → `KEY_ENTER`, `f13`…`f20` → `KEY_F13`…`KEY_F20`, and so on). A test checks that every named key has an entry.
- **Modifiers:** `cmd` → `KEY_LEFTMETA`, `ctrl` → `KEY_LEFTCTRL`, `alt` → `KEY_LEFTALT`, `shift` → `KEY_LEFTSHIFT`. `fn` → `.failed("keys '<combo>': fn has no Linux equivalent")`, checked before anything is sent.
- **Media:** `playpause` → `KEY_PLAYPAUSE`, `next` → `KEY_NEXTSONG`, `previous` → `KEY_PREVIOUSSONG`, `volumeup`/`volumedown`/`mute` → `KEY_VOLUMEUP`/`KEY_VOLUMEDOWN`/`KEY_MUTE`, `brightnessup`/`brightnessdown` → `KEY_BRIGHTNESSUP`/`KEY_BRIGHTNESSDOWN`.
- **Characters:** through `XKBLayout`, described next.

`KeyCombo.modifierAliases` gains `super` and `meta` → `.cmd`. That's the only `DeckConfig` change, and it's portable: the Mac app accepts the aliases too.

*Alternative:* `ydotool` or `wtype`. They're external dependencies that SteamOS doesn't ship, and `wtype` needs a Wayland virtual-keyboard protocol that gamescope doesn't offer.

### XKB layout without libxkbcommon

`XKBLayout: KeyboardLayout` returns evdev codes. The protocol's `UInt16` code is documented as platform-specific: macOS virtual codes on the Mac, evdev codes on Linux. It's read on every press:

1. **Which layout.** The first source that gives one wins:
   1. `XKB_DEFAULT_LAYOUT`/`XKB_DEFAULT_VARIANT` in the environment of the running `gamescope` process (`/proc/*/environ`, own uid only), because gamescope applies that keymap in Game Mode.
   2. The daemon's own environment.
   3. `/etc/X11/xorg.conf.d/00-keyboard.conf` (written by `localectl`).
   4. `XKBLAYOUT`/`XKBVARIANT` in `/etc/vconsole.conf`.
   5. `us`.

   Only the first entry of a comma-separated list is used.
2. **Parsing.** A small parser for the subset of `/usr/share/X11/xkb/symbols/<layout>` that keymaps use: `xkb_symbols "<variant>" { ... }` blocks, `include "file(variant)"` (recursive, with a depth limit), `key <AD01> { [ q, Q ] };`, and the `symbols[Group1]=` form. It takes the level-1 keysym of each key, maps keysym names to characters for the printable ASCII set the config allows (`a`…`z`, digits, ``-=[]\;',./` ``), and maps `<XXXX>` key names to evdev codes with a built-in table copied from xkeyboard-config's `keycodes/evdev` (evdev = XKB code − 8). Parsed layouts are cached by `layout(variant)`.
3. **Fallback.** If the layout types none of `a`…`z`, or its files are missing or unparseable, `us` is used. `us` is built in, so it works even without `/usr/share/X11/xkb`. A layout that types Latin letters but lacks a character gives the `noKey` problem from the key-actions spec.

The parser is tested against fixture copies of the `us`, `de`, `de(nodeadkeys)`, `fr`, `ru` and `latin` symbol files, checked into `Tests/DeckPlatformLinuxTests/Fixtures/xkb`.

*Alternatives:* libxkbcommon (can't be linked statically without vendoring a large C library and its own keymap compiler). Always `us` (breaks `ctrl+z` on German keyboards, which the Mac fixed in #4). A config field for the layout (adds a setting the user has to keep in sync, when the system already knows the layout).

### Open action

`LinuxActionPerformer.open` uses the same target parsing as the Mac (URL with a scheme, otherwise a path with `~` expanded that must exist). Then:

- `steam://…` runs `steam <url>`. That hands the URL to the running client over its pipe, and starts Steam if it isn't running.
- Anything else runs `xdg-open <target>`.

Both run through `Process` (not the shell), on a dedicated thread, with a 10 s timeout. A non-zero exit becomes `.failed("cannot open '<target>': <stderr>")`. `run` actions use `ShellRunner` unchanged.

### Problems on the deck

`DeckEngine.init` gets `showsProblemsOnDeck: Bool = false`. The Mac app keeps the default. When it's true:

- **Key error dot.** `render(key:)` sets `appearance.error` when the key has a dynamic failure (as today), an action problem for the displayed page, or rendering problems. For rendering problems it renders once, and if `rendered.problems` isn't empty, it renders again with `error: true`. `actionFinished` re-renders the key, because the dot depends on the result.
- **Status key.** Global problems are `.config`, `.permission`, and any future source that isn't key-bound. `.device` is excluded, because it can't be shown without the device. While global problems exist, key 14 renders `KeyAppearance(background: #B00020, icon: ms:error, label: …)` instead of its definition. The label is `Config` or `Keys`, or `<n> problems` when there are several. `handleKey` treats key 14 as the status key while it's shown: no action, no press darkening, and it calls `onStatusKeyPress`. The daemon logs every problem from that callback. `notify()` re-renders key 14 whenever the status key's content changes, so `configFailed` and `setPermissionProblem` reach the deck without new call sites.

The engine owns this, not the daemon, because the daemon can't change what the engine sends to key 14 without a second writer to the transport.

*Alternative:* flash all keys red, or show the message as scrolling text across the keys. It's noisy, and it hides the working keys that a broken edit keeps.

### Daemon main loop and logging

`main.swift` builds the engine like `AppDelegate` does: `HidrawTransport`, `KeyRenderer()` (no SF source), `LinuxActionPerformer`, `ShellRunner`, `ConfigWatcher` with `DispatchQueue.main.async` hops. `ownBundleID` is `streamdeckd` and `frontmostApp` is nil. Then it calls `dispatchMain()`. SIGTERM and SIGINT are ignored with `signal(SIG_IGN)` and handled by `DispatchSource.makeSignalSource` on the main queue: `watcher.stop()`, `engine.shutdown()`, `exit(0)`.

Logging: `onStatusChange` diffs the problem list against the previous one and writes `problem: <message>` and `resolved: <message>` lines, plus `connected <serial> (firmware <v>)` / `disconnected`, to stderr with line buffering. systemd adds timestamps and the unit name. There's no log library, and no syslog priority prefixes for now.

### Static build

`scripts/build-linux.sh` runs in the same pinned `swift:6.4.2` image as `test-linux.sh`. It installs the matching Static Linux SDK into the build cache volume once (`swift sdk install <url> --checksum <sha>`, with the URL and checksum pinned in the script), then runs `swift build -c release --swift-sdk x86_64-swift-linux-musl --product streamdeckd`. The output is copied to `build/linux/streamdeckd`. A check in the script runs `file` on the binary and fails unless it says "statically linked".

Found while implementing:

- **No kernel headers in the musl sysroot.** The Static SDK ships musl's headers but not the kernel's uapi headers (`linux/input.h`, `linux/uinput.h`, `linux/hidraw.h`). `CLinux` therefore defines the input event codes, `struct uinput_setup`, `struct input_event` and the ioctl numbers itself, from the stable kernel ABI, using `_IOC`/`_IOW` from `<sys/ioctl.h>`. Both builds use these definitions. `_Static_assert`s check the struct sizes. A test compares the key codes with `/usr/include/linux/input-event-codes.h` where that header exists (the glibc test image), and the uinput test checks the ioctls against a real `/dev/uinput`.
- **Yams 5.x doesn't compile against the musl SDK** (`ambiguous use of 'DBL_DECIMAL_DIG'`). Yams 6.2.2 fixes it (#477). Its only breaking change since 5.4.0 is in `YamlError.duplicatedKeysInMapping`, which `ConfigLoader` doesn't match on. `Package.swift` now requires `from: "6.2.2"`. That also changes the Mac build, so group 9 includes a Mac check.
- The new build backend puts products under `out/Products/…`. The script asks `swift build --show-bin-path` instead of hard-coding the path. `-Xlinker --strip-all` takes the binary from 138 MB to 57 MB. Most of what's left is Foundation's ICU data and the embedded fonts.

`DeckConfig` and `DeckEngine` already import `Musl` where they import `Glibc`. `DeckPlatformLinux` and `streamdeckd` follow the same pattern. Tests run against glibc (`test-linux.sh`), and the release build is musl. The static build is a separate CI-less step that the task list runs.

*Alternative:* a dynamic glibc build. SteamOS ships glibc, but not the Swift runtime, and its glibc version moves with OS updates.

### Installation

```
dist/linux/streamdeckd.service       systemd user unit
dist/linux/70-streamdeck.rules       udev rules
dist/linux/uinput.conf               modules-load.d entry
scripts/install-linux.sh             runs on the target machine
```

- **Unit:** `ExecStart=%h/.local/bin/streamdeckd`, `Restart=on-failure`, `RestartSec=2`, `WantedBy=default.target`. With `default.target`, it starts when the user's systemd manager starts. On SteamOS that's at autologin, so it also runs before Game Mode is up. `steam` and `xdg-open` get `DISPLAY`/`WAYLAND_DISPLAY` from the user manager environment, which the session imports. Hardware verification confirms that.
- **udev:** `SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="006d", TAG+="uaccess"` and `KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"`. `uaccess` gives access to whoever is logged in on the seat, the `deck` user on SteamOS, without group changes. The rules go to `/etc/udev/rules.d`, which SteamOS keeps across updates (its `/etc` is an overlay on writable storage). `/usr` is read-only and replaced on update, so nothing goes there.
- **Script:** copies the binary to `~/.local/bin`, the unit to `~/.config/systemd/user`, then runs `systemctl --user daemon-reload` and `enable --now`. Then, with sudo, it installs the rules and `uinput.conf`, runs `modprobe uinput`, `udevadm control --reload` and `udevadm trigger` for both devices. Re-running it upgrades in place. `--uninstall` removes everything. On SteamOS, the `deck` user needs a password set (`passwd`) for sudo, and the README says so.
- **Getting it onto the machine:** `scp build/linux/streamdeckd dist/linux/* scripts/install-linux.sh deck@steammachine:` then `ssh` and run it. The README documents this.

### Linux starter config

`ConfigFile.starter` becomes a platform-selected constant (`#if os(macOS)`). The Linux one has a `home` page with `ms:` icons: Steam store (`open: steam://store`), a browser (`open: https://…`), Media page, screenshot (`keys: f12`, the Steam screenshot key), a clock dynamic key, and a `media` page with the media keys and Back. A test loads it, renders every key with `KeyRenderer`, and checks that there are no problems and no `sf:` or `fn`.

## Risks / Trade-offs

- [Steam might open the deck's hidraw node as a generic controller] → It's a hardware verification task. If Steam does, the fallback is a `STEAM_INPUT` ignore via Steam's controller blacklist in `~/.steam/steam/config/config.vdf` (`controller_blacklist` with `0x0fd9/0x006d`), added to the install script.
- [gamescope might apply a different keymap than the one detected, for example one Steam sets at runtime] → It's a verification task with a German layout. The detection order is isolated in one function, so changing sources doesn't change the design.
- [The XKB parser covers a subset of the format] → Unknown constructs are skipped. If a layout yields no Latin letters, it falls back to `us`. Fixture tests cover the layouts most likely in use.
- [A uinput device created at startup appears to Steam as a new keyboard] → Expected and harmless. It's one device for the process's lifetime, not one per press.
- [Status key hides key 14's own function while a problem exists] → It's the only way to show a problem on a headless device without hiding more. It goes away as soon as the problem is fixed, and the journal has the details.
- [Static SDK version must match the toolchain exactly] → Both are pinned in the scripts next to each other. `SWIFT_VERSION` changes both.
- [Steam Machine hardware isn't available in CI] → The last task group is a manual checklist on the device, recorded in tasks.md as #5 did for the Mac run.

## Migration Plan

New install only. Nothing changes for Mac users, except that the `super`/`meta` aliases are accepted. Rollback: `scripts/install-linux.sh --uninstall`.

## Open Questions

- Whether `steam <url>` or `xdg-open steam://…` is more reliable in Game Mode. Both are one-line changes inside `open`. Hardware testing decides.
- Whether gamescope needs a longer pause between key-down and key-up for some games. It's a constant in `UinputKeyboard`.
