# Design

## Context

`KeyRenderer.renderUpright` draws in layers: it fills the background, aspect-fits the icon into a fixed `iconRect` (48x48, or 44x40 with a label), draws the label, then the error dot and the pressed overlay. `KeyAppearance` carries `background`, `icon` and `label`. `DeckEngine.render(key:)` builds it by merging `DynamicOutput` over the `KeyDefinition`, and the renderer's problems go to `problems[.icon(key:)]`.

Icon strings become `Icon` values through `Icon(configValue:relativeTo:)`, which handles `sf:`, `~` and relative paths. `ConfigLoader` and `DynamicOutput.parse` both use it. The editor works on `KeyDocument`, whose fields are plain strings, and writes YAML in a fixed field order.

## Goals / Non-Goals

**Goals:**
- One new layer, `image`, between background and icon, with no change to keys that don't use it.
- The same path rules for `image` in config and in dynamic output as for `icon`.

**Non-Goals:**
- Fit modes (stretch, fit, tile), opacity or tint. Aspect-fill is the only mode.
- SF Symbols as images.
- Animated images (GIF, APNG): only the first frame is drawn.
- Caching decoded images. Icons are not cached either (see Risks).

## Decisions

### `image` is a separate field, not an icon mode
`image` is a background layer, so an icon and label can sit on top of a photo. The alternative, `icon_fill: true`, allows only one image per key and makes `sf:` icons meaningless when filled. A separate field also makes the dynamic JSON output simpler: a script sets `image` without touching the configured `icon`.

### Path resolution shared with icons
Split the path part out of `Icon(configValue:relativeTo:)` into a function `resolvePath(_:relativeTo:)` in `DeckConfig`. Both `Icon` and `image` use it. `KeyDefinition.image` holds the resolved absolute path as a `String`. A wrapper type would add nothing, because an image is always a file. `ConfigLoader` rejects a value starting with `sf:` with a `ConfigError` that carries page and key, so the editor shows it next to the key.

### Dynamic `image` is three-state
JSON output can leave `image` out (keep the configured one), set a path, or clear it with `""`. `DynamicOutput.image` is a small enum, `ImageOverride { case path(String), case remove }`, wrapped in an optional, so nil means "not set". The alternative, a `String??`, is hard to read at the call sites. Treating `""` as a path would show a missing-file error instead of removing the image. The engine merges it as `output.image` → path or nil, falling back to `definition.image`.

### Drawing
- The image layer is drawn after the background fill and before the icon. Its rect uses aspect-fill: `scale = max(72/w, 72/h)`, centered, clipped to the key bounds. A new `aspectFill` helper sits next to `aspectFit`.
- The icon rect, label area, error dot and pressed overlay don't change. The error dot and pressed overlay still draw on top of the image.
- Label shadow: when `appearance.image` is set and loaded, wrap the `drawLabel` call in `context.saveGState()`, `setShadow(offset: (0, -1), blur: 3, color: black 80%)` and `restoreGState()`. `drawLabel` itself doesn't change.
- Loading uses the same `CGImageSource` path as file icons. On failure the renderer adds `image file not found or unreadable: <path>` to its problems and skips the layer. Unlike a missing icon, a missing image gets no placeholder: the key still has its background, icon and label, so it stays usable.

### Editor
`KeyDocument` gains `image: String?`. The YAML reader accepts it. The writer emits it after `icon` (order: icon, image, label, background, action, dynamic). The inspector gets an Image row below Icon: a text field, Choose… (reusing `choosePath(types: [.png, .jpeg], …)`, which stores paths relative to the config directory) and a remove button. The grid and the device preview go through `KeyRenderer`, so they need no change.

## Risks / Trade-offs

- [A large image (e.g. a 4000 px photo) is decoded on every render of that key, and dynamic keys can render every second] → Acceptable for 15 keys at 1 s minimum interval. `docs/config.md` recommends small square images. Add a cache keyed by path and modification date only if it shows up in practice.
- [The device shows JPEG at 72x72, so photos lose detail] → Inherent to the hardware. No mitigation.
- [A label shadow alone may not be enough on bright, busy images] → This was the user's choice over a dark strip. A strip can be added later as an option without changing the config format.
- [The specs this change modifies are still in unarchived changes] → Archive `streamdeck-menubar-controller`, `2-dynamic-key-json` and `1-config-editor` before this one, in that order.
