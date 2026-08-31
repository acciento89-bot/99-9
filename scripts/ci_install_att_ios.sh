#!/usr/bin/env bash
set -euo pipefail

VERSION="3.0.0"
URL="https://github.com/godot-x/att/releases/download/${VERSION}/godotx_att.zip"
EXPECTED_SHA256="92cfda0999c545c4bb9ebf1e06aacf648cfbbc22d7564a4a951767768df894c0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ZIP_PATH="$TMP_DIR/godotx_att.zip"
UNPACK_DIR="$TMP_DIR/unpack"
mkdir -p "$UNPACK_DIR"

curl -L --fail --retry 3 --retry-delay 2 -o "$ZIP_PATH" "$URL"

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(sha256sum "$ZIP_PATH" | awk '{print $1}')"
else
  ACTUAL_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
fi

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "Godotx ATT checksum mismatch" >&2
  echo "expected: $EXPECTED_SHA256" >&2
  echo "actual:   $ACTUAL_SHA256" >&2
  exit 1
fi

unzip -q "$ZIP_PATH" -d "$UNPACK_DIR"
ADDON_DIR="$(find "$UNPACK_DIR" -type d -path '*/addons/godotx_att' -print -quit)"
if [[ -z "$ADDON_DIR" ]]; then
  echo "Godotx ATT addon directory missing from release archive" >&2
  exit 1
fi
PACKAGE_ROOT="$(cd "$ADDON_DIR/../.." && pwd)"

if [[ ! -d "$PACKAGE_ROOT/ios/plugins/att" ]]; then
  echo "Godotx ATT iOS native plugin missing from release archive" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/addons" "$ROOT_DIR/ios/plugins"
rm -rf "$ROOT_DIR/addons/godotx_att" "$ROOT_DIR/ios/plugins/att"
cp -R "$PACKAGE_ROOT/addons/godotx_att" "$ROOT_DIR/addons/"
cp -R "$PACKAGE_ROOT/ios/plugins/att" "$ROOT_DIR/ios/plugins/"

test -f "$ROOT_DIR/addons/godotx_att/plugin.cfg"
test -f "$ROOT_DIR/ios/plugins/att/att.gdip"
find "$ROOT_DIR/ios/plugins/att" -maxdepth 1 -name 'GodotxATT*.xcframework' -print -quit | grep -q .

echo "Installed Godotx ATT ${VERSION} for iOS."
