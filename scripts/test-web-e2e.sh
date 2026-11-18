#!/bin/bash
# Runs the web editor's browser checks (Tests/web-e2e/check.mjs) in headless Chromium and Firefox, against
# build/linux/streamdeckd with a fresh config and no deck. Everything runs in Docker.
#   ./scripts/build-linux.sh && ./scripts/test-web-e2e.sh            # both browsers
#   ./scripts/test-web-e2e.sh firefox                                # one browser
# Screenshots and the daemon's config end up in build/web-e2e/<browser>/.
# The Playwright image must match the version in Tests/web-e2e/package.json.
set -euo pipefail

cd "$(dirname "$0")/.."

PLAYWRIGHT_IMAGE="${PLAYWRIGHT_IMAGE:-mcr.microsoft.com/playwright:v1.49.1-noble}"
DAEMON_IMAGE="${DAEMON_IMAGE:-alpine:3.20}"
network="streamdeck-e2e-$$"
daemon="streamdeck-e2e-daemon-$$"

if [[ ! -x build/linux/streamdeckd ]]; then
    echo "error: build/linux/streamdeckd is missing; run ./scripts/build-linux.sh first" >&2
    exit 1
fi

# shellcheck disable=SC2317 # called by the EXIT trap
cleanup() {
    docker rm -f "$daemon" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker network create "$network" >/dev/null

run() {
    local browser="$1"
    local work="$PWD/build/web-e2e/$browser"
    rm -rf "$work"
    mkdir -p "$work/state" "$work/config" "$work/out"
    local token
    token="$(./scripts/dev-web-token.sh "$work/state/streamdeck/web-clients.json" | sed -n 's/^token: //p')"

    docker rm -f "$daemon" >/dev/null 2>&1 || true
    docker run -d --name "$daemon" --network "$network" \
        -v "$PWD/build/linux:/b:ro" -v "$work/state:/root/.local/state" -v "$work/config:/root/.config/streamdeck" \
        "$DAEMON_IMAGE" /b/streamdeckd >/dev/null
    sleep 2

    echo "== $browser"
    local status=0
    docker run --rm --network "$network" \
        -v "$PWD/Tests/web-e2e:/e2e:ro" -v "$work/out:/out" -v "$work/config:/cfg" \
        -e BASE="http://$daemon:3325" -e TOKEN="$token" -e BROWSER="$browser" \
        "$PLAYWRIGHT_IMAGE" \
        sh -c 'cp -r /e2e /tmp/e2e && cd /tmp/e2e && npm install --silent --no-audit --no-fund >/dev/null && node check.mjs' \
        || status=$?
    if [[ $status -ne 0 ]]; then
        echo "--- daemon log"
        docker logs "$daemon" 2>&1 | tail -20
    fi
    return $status
}

browsers=("$@")
[[ ${#browsers[@]} -eq 0 ]] && browsers=(chromium firefox)
failed=0
for browser in "${browsers[@]}"; do
    run "$browser" || failed=1
done
exit $failed
