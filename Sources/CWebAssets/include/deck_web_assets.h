#ifndef DECK_WEB_ASSETS_H
#define DECK_WEB_ASSETS_H

#include <stddef.h>

// The web editor's files, compiled into the binary with #embed (see assets.c).
typedef struct {
    const char *path;
    const unsigned char *bytes;
    size_t size;
} deck_web_asset;

// Returns the table and sets *count.
const deck_web_asset *deck_web_assets(size_t *count);

#endif
