#!/bin/bash
# Development only: adds a paired browser with a known token to streamdeckd's token file, so the web
# editor can be tried without a deck (pairing needs one). Then set the cookie in the browser's devtools:
#   streamdeck_token=<token>   (Path=/, HttpOnly, SameSite=Strict)
#   ./scripts/dev-web-token.sh [token-file] [token]
# The token file defaults to $XDG_STATE_HOME/streamdeck/web-clients.json (~/.local/state/...).
# streamdeckd notices the change on the next request; no restart needed.
set -euo pipefail

file="${1:-${XDG_STATE_HOME:-$HOME/.local/state}/streamdeck/web-clients.json}"
token="${2:-dev-$(head -c 24 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')}"
hash="$(printf '%s' "$token" | sha256sum | cut -d' ' -f1)"
id="$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
entry="{\"created\":\"$now\",\"id\":\"$id\",\"lastUsed\":\"$now\",\"name\":\"Development token\",\"sha256\":\"$hash\"}"

mkdir -p "$(dirname "$file")"
chmod 700 "$(dirname "$file")"
umask 077
if [[ -s "$file" ]] && grep -q '{' "$file"; then
    # Append to the JSON array: drop the closing bracket, add the entry.
    content="$(sed '$ s/]\s*$//' "$file")"
    printf '%s,\n%s\n]\n' "$content" "$entry" > "$file.tmp"
else
    printf '[\n%s\n]\n' "$entry" > "$file.tmp"
fi
mv "$file.tmp" "$file"

echo "token: $token"
echo "cookie: streamdeck_token=$token"
