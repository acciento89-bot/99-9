#!/bin/sh
set -eu
practice_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
practice_godot=${1:-/Volumes/SSK SSD/Kamilunavo/Cache/Godot/4.7.1/Godot.app/Contents/MacOS/Godot}
practice_temp=$(mktemp -d "${TMPDIR:-/tmp}/ninenine-practice-integration.XXXXXX")
trap 'rm -rf -- "$practice_temp"' EXIT HUP INT TERM
printf '%s\n' 'config_version=5' '[application]' 'config/name="NineNineInertProviderIntegrationQA"' '[display]' 'window/size/viewport_width=1080' 'window/size/viewport_height=1920' '[input_devices]' 'pointing/emulate_mouse_from_touch=false' '[rendering]' 'renderer/rendering_method="gl_compatibility"' > "$practice_temp/project.godot"
mkdir "$practice_temp/scripts" "$practice_temp/data"
mkdir -p "$practice_temp/assets/fonts/hammersmithone"
cp "$practice_repo/assets/fonts/hammersmithone/HammersmithOne-Regular.ttf" "$practice_temp/assets/fonts/hammersmithone/"
cp "$practice_repo/assets/fonts/hammersmithone/OFL.txt" "$practice_temp/assets/fonts/hammersmithone/"
cp "$practice_repo/tests/practice_integration_tests.gd" "$practice_temp/test.gd"
# Exact actual ancestor UI/model/archive; original provider scripts, native
# addons, main scene, user profile and all network configuration are excluded.
for practice_source in "$practice_repo"/scripts/main_v*.gd "$practice_repo"/scripts/practice_model.gd "$practice_repo"/scripts/practice_archive.gd "$practice_repo"/scripts/main_practice.gd "$practice_repo"/scripts/ranking_captions.gd; do
 [ -f "$practice_source" ] || continue
 cp "$practice_source" "$practice_temp/scripts/"
done
practice_status=0
"$practice_godot" --headless --editor --import --quit --path "$practice_temp" > "$practice_temp/import.log" 2>&1 || practice_status=$?
cat "$practice_temp/import.log"
[ "$practice_status" -eq 0 ] || exit "$practice_status"
if grep -E 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$practice_temp/import.log" >/dev/null; then exit 1; fi
"$practice_godot" --headless --quit-after 120 --path "$practice_temp" --script "$practice_temp/test.gd" -- "$practice_temp/data" > "$practice_temp/output.log" 2>&1 || practice_status=$?
cat "$practice_temp/output.log"
[ "$practice_status" -eq 0 ] || exit "$practice_status"
if grep -E 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$practice_temp/output.log" >/dev/null; then exit 1; fi
grep -F 'NN PRACTICE INTEGRATION PASS checks=' "$practice_temp/output.log" >/dev/null
