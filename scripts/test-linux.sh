#!/bin/bash
# Runs `swift` for Linux in the official Docker image. Without arguments it runs `swift test`.
#   ./scripts/test-linux.sh                          # swift test
#   ./scripts/test-linux.sh test --filter DeckHIDTests
#   ./scripts/test-linux.sh build --target DeckConfig
#   ./scripts/test-linux.sh --version
# Build products go to ~/.cache/streamdeck-linux-build, never to the macOS .build directory.
# SWIFT_VERSION overrides the image's Swift version; keep the default in step with the macOS toolchain.
set -euo pipefail

cd "$(dirname "$0")/.."

SWIFT_VERSION="${SWIFT_VERSION:-6.4.2}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/streamdeck-linux-build/$SWIFT_VERSION"
mkdir -p "$CACHE"

if [[ $# -eq 0 ]]; then
    set -- test
fi

# Subcommands (build, test, run, package) take the scratch path; options such as --version do not.
if [[ "$1" != -* ]]; then
    subcommand="$1"
    shift
    set -- "$subcommand" --scratch-path /build "$@"
fi

exec docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "$PWD:/src" \
    -v "$CACHE:/build" \
    -w /src \
    "swift:$SWIFT_VERSION" \
    swift "$@"
