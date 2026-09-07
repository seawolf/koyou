#!/usr/bin/env bash
# Stages wllama's browser build into web/wllama/, for the web model tier.
#
# Not committed: it is 9MB of third-party binary, and npm is the right source
# of truth for a JavaScript dependency. Without it the web build still works —
# the model backend declines and the dictionary answers, which is the same
# thing that happens on a phone with no weights downloaded.
#
# Usage, from the repository root:
#
#   tool/fetch_wllama.sh
set -euo pipefail

# Pinned. wllama's worker protocol is not stable across majors, and the API
# changed shape between 2.x and 3.x: options moved into a single
# llama.cpp-server-shaped object, so `createCompletion(prompt, opts)` became
# `createCompletion({prompt, n_predict, stop})`.
VERSION="3.6.1"
DESTINATION="web/wllama"

command -v npm >/dev/null || { echo "npm is needed to fetch wllama" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Fetching @wllama/wllama@$VERSION"
( cd "$WORK" && npm pack --silent "@wllama/wllama@$VERSION" >/dev/null )
tar -xzf "$WORK"/wllama-wllama-*.tgz -C "$WORK"

rm -rf "$DESTINATION"
mkdir -p "$(dirname "$DESTINATION")"
cp -R "$WORK/package/esm" "$DESTINATION"

# The type declarations and source maps are for a bundler, not a browser.
find "$DESTINATION" -name '*.d.ts' -o -name '*.map' -o -name '*.cjs' | xargs rm -f

printf '%s\n' "$VERSION" > "$DESTINATION/VERSION"
echo "Staged $DESTINATION ($(du -sh "$DESTINATION" | cut -f1)), wllama $VERSION"
ls "$DESTINATION"/wasm/*.wasm >/dev/null || { echo "no wasm staged" >&2; exit 1; }
