#!/usr/bin/env bash
set -euo pipefail

# Native iOS share sheet for 99.9%.
# kyoz/godot-share v1.0.9 explicitly ships a Godot 4.7 iOS template.
VERSION="v1.0.9"
GODOT_TEMPLATE="4.7"
URL="https://github.com/kyoz/godot-share/releases/download/${VERSION}/ios-template-${GODOT_TEMPLATE}.zip"
TMP="${RUNNER_TEMP:-/tmp}/ninenine-share-ios.zip"
DEST="ios/plugins"

rm -rf "${DEST}/share"
mkdir -p "${DEST}"

curl -L --fail --retry 3 --retry-delay 2 -o "$TMP" "$URL"
unzip -q "$TMP" -d "$DEST"

test -f "${DEST}/share/share.gdip"
test -f "${DEST}/share/share.release.a"
test -f "${DEST}/share/share.debug.a"

grep -q 'name="Share"' "${DEST}/share/share.gdip"
grep -q 'binary="share.a"' "${DEST}/share/share.gdip"

echo "Installed native iOS Share plugin ${VERSION} for Godot ${GODOT_TEMPLATE}."
