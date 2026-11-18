#!/bin/bash
# Runs the web editor's JavaScript tests (Tests/web/*.test.mjs) with Node in Docker, without installing Node.
#   ./scripts/test-web.sh
# The source tree is mounted read-only. NODE_IMAGE overrides the pinned image.
set -euo pipefail

cd "$(dirname "$0")/.."

NODE_IMAGE="${NODE_IMAGE:-node:22.12.0-alpine3.20}"

exec docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$PWD:/src:ro" \
    -w /src \
    "$NODE_IMAGE" \
    node --test 'Tests/web/**/*.test.mjs'
