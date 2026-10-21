#!/bin/sh
set -eu
practice_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
practice_godot=${1:-/Volumes/SSK SSD/Kamilunavo/Cache/Godot/4.7.1/Godot.app/Contents/MacOS/Godot}
practice_temp=$(mktemp -d "${TMPDIR:-/tmp}/ninenine-practice-pure.XXXXXX")
trap 'rm -rf -- "$practice_temp"' EXIT HUP INT TERM
# Deliberately minimal disposable project: no original main scene, autoloads,
# native addons, credentials, ad/IAP initialization or leaderboard requests.
printf '%s\n' 'config_version=5' '[application]' 'config/name="NineNinePurePracticeQA"' '[rendering]' 'renderer/rendering_method="gl_compatibility"' > "$practice_temp/project.godot"
cp "$practice_repo/tests/practice_core_tests.gd" "$practice_temp/test.gd"
if [ -f "$practice_repo/scripts/practice_model.gd" ]; then cp "$practice_repo/scripts/practice_model.gd" "$practice_temp/practice_model.gd"; fi
practice_status=0
"$practice_godot" --headless --quit-after 120 --path "$practice_temp" --script "$practice_temp/test.gd" > "$practice_temp/output.log" 2>&1 || practice_status=$?
cat "$practice_temp/output.log"
[ "$practice_status" -eq 0 ] || exit "$practice_status"
if grep -E 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$practice_temp/output.log" >/dev/null; then exit 1; fi
grep -F 'NN PRACTICE CORE PASS checks=' "$practice_temp/output.log" >/dev/null
