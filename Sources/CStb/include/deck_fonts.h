#ifndef DECK_FONTS_H
#define DECK_FONTS_H

#include <stddef.h>

// Files compiled into the binary; see README.md. Each returns the bytes and sets *size.
const unsigned char *deck_font_inter_semibold(size_t *size);
const unsigned char *deck_font_material_outlined(size_t *size);
const unsigned char *deck_font_material_filled(size_t *size);
const unsigned char *deck_material_codepoints(size_t *size);

#endif
