# Stream Deck Original V2 — HID protocol notes

Verified on hardware on 2026-10-17 (firmware `1.02.007`, macOS 27.0.1), via IOKit `IOHIDManager`, Elgato app not running.

## Device

| Property | Value |
|---|---|
| Vendor ID | `0x0fd9` |
| Product ID | `0x006d` |
| Primary usage page / usage | `0x0C` (Consumer) / `0x01` |
| Max input / output / feature report size | 512 / 1024 / 32 bytes |

## Permissions

- No Input Monitoring permission is needed. `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` reported *denied* for the process, but input reports still arrived, and no prompt appeared.
- The device opens non-exclusively (`kIOHIDOptionsTypeNone`).

## Input report (key state)

The buffer passed to `IOHIDDeviceRegisterInputReportCallback` **includes the report ID** as byte 0. The callback's `reportID` argument is `1`, and the length is always 512.

```
offset: 0  1  2  3  4 .. 18
        01 00 0f 00 k0 .. k14     ki = 1 pressed, 0 released
```

Keys are numbered left to right, top to bottom (5x3). The device sends a full state report on every change, and once with all zeros right after the callback is registered.

Captured sample (key 4 and key 7 held):
```
01 00 0f 00 00 00 00 00 01 00 00 01 00 00 00 00 00 00 00
```

## Feature reports (get)

| ID | Content |
|---|---|
| `0x05` | firmware: bytes 6.. ASCII, NUL-terminated (`1.02.007`) |
| `0x06` | serial: bytes 2.. ASCII, NUL-terminated (`AL22K2C76666`) |

Captured:
```
05 0c 91 90 b1 e4 31 2e 30 32 2e 30 30 37 00 ...
06 0c 41 4c 32 32 4b 32 43 37 36 36 36 36 00 ...
```

## Feature reports (set), from reference implementations

| Purpose | Bytes (padded to 32) |
|---|---|
| Brightness | `03 08 <percent>` |
| Reset | `03 02` |

## Output report (key image), from reference implementations

Each report is 1024 bytes: an 8-byte header and up to 1016 bytes of JPEG payload, zero-padded.

```
02 07 <key> <isLast> <lenLo> <lenHi> <pageLo> <pageHi> <payload...>
```

Image: 72x72 JPEG, flipped horizontally and vertically. Verified: an unflipped image with a white top-left square shows it bottom-right.

## IOKit pitfalls (found on hardware)

- With `IOHIDManagerSetDispatchQueue`, the manager's `IOHIDDevice` objects are already activated. Calling `IOHIDDeviceRegisterInputReportCallback` on them traps (`EXC_BREAKPOINT`).
- `IOHIDManagerRegisterInputReportCallback` delivers nothing when the device is opened with `IOHIDDeviceOpen` rather than `IOHIDManagerOpen`.
- What works: for each match, `IOHIDDeviceCreate` a separate object from `IOHIDDeviceGetService(matched)`, open it, set the dispatch queue, register the input callback, then `IOHIDDeviceActivate`. Removal callbacks still report the manager's object, so keep both.
- `IOHIDManagerActivate` delivers matches for already-attached devices synchronously on the calling thread, so call it from inside the HID queue.
