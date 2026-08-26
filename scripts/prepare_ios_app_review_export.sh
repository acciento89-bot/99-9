#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path

replacements = {
    "iOS + ANDROID": "ALL PLAYERS",
    "iOS + Android": "ALL PLAYERS",
    "Store available on iOS / Android device": "Store unavailable on this device",
}

for path in Path("scripts").glob("*.gd"):
    text = path.read_text(encoding="utf-8")
    updated = text
    for old, new in replacements.items():
        updated = updated.replace(old, new)
    if updated != text:
        path.write_text(updated, encoding="utf-8")
        print(f"Neutralized iOS App Store copy in {path}")
PY

if grep -R -n -E 'iOS \+ ANDROID|iOS \+ Android|Store available on iOS / Android device' scripts --include='*.gd'; then
  echo "Third-party platform wording remains in customer-facing scripts" >&2
  exit 1
fi

# The Build 17 Settings screen must expose a distinct user-initiated restore action.
grep -q 'RESTORE PURCHASES' scripts/main_v12_app_review.gd
grep -q 'restore_theme_purchases' scripts/main_v12_app_review.gd

# ATT must be the first gate before the iOS advertising stack can initialize.
grep -q 'Engine.has_singleton("GodotxATT")' scripts/ads_service_ios_safe.gd
grep -q 'ATT_AUTHORIZED' scripts/ads_service_ios_safe.gd
grep -q 'not _att_allows_tracking()' scripts/ads_service_ios_safe.gd

echo "iOS App Review export preflight passed."
