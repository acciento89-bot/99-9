#!/usr/bin/env bash
set -euo pipefail

PLATFORM="${1:-all}"
ADMOB_VERSION="v5.0.0"
GODOT_VERSION="4.7.2"
BASE_URL="https://github.com/poingstudios/godot-admob-plugin/releases/download/${ADMOB_VERSION}"
ROOT="${RUNNER_TEMP:-/tmp}/ninenine-admob-native"
rm -rf "$ROOT"
mkdir -p "$ROOT"

install_platform() {
  local platform="$1"
  local archive="${platform}-template-v${GODOT_VERSION}.zip"
  local tmp="$ROOT/$platform"
  local target="addons/admob/${platform}/bin"

  mkdir -p "$tmp"
  curl -L --fail --retry 3 -o "$ROOT/$archive" "$BASE_URL/$archive"
  unzip -q "$ROOT/$archive" -d "$tmp"

  local config
  config=$(find "$tmp" -type f -name 'poing_godot_admob_ads.gd' | head -1)
  if [[ -z "$config" ]]; then
    echo "AdMob $platform template does not contain poing_godot_admob_ads.gd" >&2
    find "$tmp" -maxdepth 6 -type f | sort | head -200 >&2
    exit 1
  fi

  local source_bin
  source_bin=$(dirname "$(dirname "$config")")
  rm -rf "$target"
  mkdir -p "$target"
  cp -R "$source_bin/." "$target/"

  test -f "$target/ads/poing_godot_admob_ads.gd"
  echo "Installed AdMob ${ADMOB_VERSION} ${platform} template for Godot ${GODOT_VERSION}"
}

case "$PLATFORM" in
  ios) install_platform ios ;;
  android) install_platform android ;;
  all)
    install_platform ios
    install_platform android
    ;;
  *)
    echo "Usage: $0 [ios|android|all]" >&2
    exit 2
    ;;
esac
