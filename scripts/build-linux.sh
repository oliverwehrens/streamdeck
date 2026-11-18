#!/bin/bash
# Builds a fully static x86_64 `streamdeckd` (Swift Static Linux SDK, musl) in Docker.
#   ./scripts/build-linux.sh          # -> build/linux/streamdeckd
# The SDK is downloaded once into ~/.cache/streamdeck-linux-build/<version>/swift-sdks.
# SWIFT_VERSION, STATIC_SDK_VERSION and STATIC_SDK_CHECKSUM must match each other; keep them in step with
# scripts/test-linux.sh. Checksums: https://www.swift.org/api/v1/install/releases.json ("Static SDK").
set -euo pipefail

cd "$(dirname "$0")/.."

SWIFT_VERSION="${SWIFT_VERSION:-6.4.2}"
STATIC_SDK_VERSION="${STATIC_SDK_VERSION:-0.1.0}"
STATIC_SDK_CHECKSUM="${STATIC_SDK_CHECKSUM:-3786b179936d9cc9e266dd506bd1654176358d7b25288e243359f4d17cc4dc5a}"
TAG="swift-$SWIFT_VERSION-RELEASE"
SDK_URL="https://download.swift.org/swift-$SWIFT_VERSION-release/static-sdk/$TAG/${TAG}_static-linux-$STATIC_SDK_VERSION.artifactbundle.tar.gz"
SDK_TRIPLE="x86_64-swift-linux-musl"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/streamdeck-linux-build/$SWIFT_VERSION"
mkdir -p "$CACHE" build/linux

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "$PWD:/src" \
    -v "$CACHE:/build" \
    -w /src \
    "swift:$SWIFT_VERSION" \
    bash -euo pipefail -c "
        if ! swift sdk list --swift-sdks-path /build/swift-sdks 2>/dev/null | grep -q '_static-linux-$STATIC_SDK_VERSION'; then
            swift sdk install '$SDK_URL' --checksum '$STATIC_SDK_CHECKSUM' --swift-sdks-path /build/swift-sdks
        fi
        args=(-c release --swift-sdk '$SDK_TRIPLE' --swift-sdks-path /build/swift-sdks --scratch-path /build/static -Xlinker --strip-all)
        swift build \"\${args[@]}\" --product streamdeckd
        cp \"\$(swift build \"\${args[@]}\" --show-bin-path)/streamdeckd\" /src/build/linux/streamdeckd
    "

binary=build/linux/streamdeckd
description="$(file -b "$binary")"
if [[ "$description" != *"statically linked"* && "$description" != *"static-pie linked"* ]]; then
    echo "error: $binary is not statically linked: $description" >&2
    exit 1
fi
echo "$binary: $(du -h "$binary" | cut -f1), $description"
