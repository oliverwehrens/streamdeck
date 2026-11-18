# CStb

Vendored C used by `DeckRender`, and the fonts it embeds.

| File | Source | License |
|---|---|---|
| `include/stb_truetype.h` (v1.28), `include/stb_image.h` (v2.32), `include/stb_image_write.h` (v1.18) | [nothings/stb](https://github.com/nothings/stb) at commit `9600522de53973336fa033a289858a4354cbb04c` | Public domain or MIT, see `LICENSE-stb` |

To update, download the three headers from a newer commit, replace them, and update the commit here.

`stb.c` compiles the implementations with PNG and JPEG decoding only and without stdio. Swift reads files itself and passes the bytes in.

## Fonts

`fonts/` holds the fonts compiled into the binary by `fonts.c`. Regenerate them with `scripts/make-fonts.sh`, which pins every source:

| File | Source | License |
|---|---|---|
| `Inter-SemiBold.ttf` | [Inter](https://github.com/rsms/inter) 4.1 release, `extras/ttf` | SIL OFL 1.1, see `fonts/LICENSE-Inter` |
| `MaterialSymbolsOutlined-400.ttf`, `MaterialSymbolsOutlined-400-Fill.ttf`, `MaterialSymbols.codepoints` | [google/material-design-icons](https://github.com/google/material-design-icons) `variablefont/` at commit `10ecc14`, instanced at wght 400, GRAD 0, opsz 48, FILL 0 and 1, and subset to the codepoints | Apache-2.0, see `fonts/LICENSE-MaterialSymbols` |
