// Embeds the font files with C23 #embed; see README.md.
#include "deck_fonts.h"

static const unsigned char inter_semibold[] = {
#embed "fonts/Inter-SemiBold.ttf"
};

static const unsigned char material_outlined[] = {
#embed "fonts/MaterialSymbolsOutlined-400.ttf"
};

static const unsigned char material_filled[] = {
#embed "fonts/MaterialSymbolsOutlined-400-Fill.ttf"
};

static const unsigned char material_codepoints[] = {
#embed "fonts/MaterialSymbols.codepoints"
};

#define ACCESSOR(name, data) \
    const unsigned char *name(size_t *size) { *size = sizeof(data); return data; }

ACCESSOR(deck_font_inter_semibold, inter_semibold)
ACCESSOR(deck_font_material_outlined, material_outlined)
ACCESSOR(deck_font_material_filled, material_filled)
ACCESSOR(deck_material_codepoints, material_codepoints)
