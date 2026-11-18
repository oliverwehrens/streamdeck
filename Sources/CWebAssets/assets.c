// Embeds the web editor's files with C23 #embed, like CStb/fonts.c. Add new files to both lists.
#include "deck_web_assets.h"

static const unsigned char index_html[] = {
#embed "web/index.html"
};
static const unsigned char app_css[] = {
#embed "web/app.css"
};
static const unsigned char app_js[] = {
#embed "web/app.js"
};
static const unsigned char keys_js[] = {
#embed "web/keys.js"
};
static const unsigned char picker_js[] = {
#embed "web/picker.js"
};
static const unsigned char pairing_js[] = {
#embed "web/pairing.js"
};

#define ASSET(path, data) { path, data, sizeof(data) }

static const deck_web_asset assets[] = {
    ASSET("index.html", index_html),
    ASSET("app.css", app_css),
    ASSET("app.js", app_js),
    ASSET("keys.js", keys_js),
    ASSET("picker.js", picker_js),
    ASSET("pairing.js", pairing_js),
};

const deck_web_asset *deck_web_assets(size_t *count) {
    *count = sizeof(assets) / sizeof(assets[0]);
    return assets;
}
