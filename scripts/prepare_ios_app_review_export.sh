#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path
import re

# 1) Remove Android-only project settings from the Apple review copy.
project = Path("project.godot")
text = project.read_text(encoding="utf-8")
text = "\n".join(
    line for line in text.splitlines()
    if not line.startswith("general/android/")
) + "\n"
project.write_text(text, encoding="utf-8")

# 2) Make the shared IAP service iOS-only in the generated review workspace.
iap = Path("scripts/iap_service.gd")
text = iap.read_text(encoding="utf-8")
text = text.replace('if OS.get_name() not in ["iOS", "Android"]:', 'if OS.get_name() != "iOS":')
text = text.replace('Store available on iOS / Android device', 'App Store unavailable on this device')
text = text.replace('    props.request.google = Types.RequestPurchaseAndroidProps.new()\n', '')
text = text.replace('    var google_skus: Array[String] = [product_id]\n', '')
text = text.replace('    props.request.google.skus = google_skus\n', '')
iap.write_text(text, encoding="utf-8")

# 3) Make the shared AdMob service iOS-only in the generated review workspace.
ads = Path("scripts/ads_service.gd")
text = ads.read_text(encoding="utf-8")
text = text.replace('const TEST_INTERSTITIAL_ANDROID := "ca-app-pub-3940256099942544/1033173712"\n', '')
text = text.replace('OS.get_name() not in ["iOS", "Android"]', 'OS.get_name() != "iOS"')
text = text.replace('var unit_id := TEST_INTERSTITIAL_ANDROID if OS.get_name() == "Android" else INTERSTITIAL_IOS', 'var unit_id := INTERSTITIAL_IOS')
ads.write_text(text, encoding="utf-8")

# 4) Remove every customer-facing third-party-platform wording and stale Android
# platform-detection branch from scripts that are bundled by Godot all_resources.
replacements = {
    "iOS + ANDROID": "ALL PLAYERS",
    "iOS + Android": "ALL PLAYERS",
    "Store available on iOS / Android device": "App Store unavailable on this device",
    "Google Play": "App Store",
    "Play Store": "App Store",
}
for path in Path("scripts").glob("*.gd"):
    source = path.read_text(encoding="utf-8")
    updated = source
    for old, new in replacements.items():
        updated = updated.replace(old, new)
    updated = updated.replace('This remains iOS-only and does not alter the Android path.', 'This remains iOS-only for the App Store build.')
    updated = re.sub(
        r'(?m)^([ \t]*)if os_name == "android":\n\1[ \t]+return "android"\n',
        '',
        updated,
    )
    if updated != source:
        path.write_text(updated, encoding="utf-8")
        print(f"Sanitized iOS App Store copy in {path}")
PY

# Hard gate: no Android / Google Play wording may remain in customer-facing scripts
# or in the project settings used for the Apple export.
if grep -R -n -Ei 'android|google play|play store' scripts --include='*.gd'; then
  echo "ERROR: third-party platform wording remains in iOS App Review scripts" >&2
  exit 1
fi
if grep -n -Ei 'android|google play|play store' project.godot; then
  echo "ERROR: third-party platform configuration remains in iOS App Review project.godot" >&2
  exit 1
fi

grep -q 'RESTORE PURCHASES' scripts/main_v12_app_review.gd
grep -q 'restore_theme_purchases' scripts/main_v12_app_review.gd
grep -q 'Engine.has_singleton("GodotxATT")' scripts/ads_service_ios_safe.gd
grep -q 'ATT_AUTHORIZED' scripts/ads_service_ios_safe.gd
grep -q 'not _att_allows_tracking()' scripts/ads_service_ios_safe.gd

echo "iOS App Review export preflight passed: Apple-only copy, no Android/Google Play wording."
