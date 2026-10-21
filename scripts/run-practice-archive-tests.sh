#!/bin/sh
set -eu
practice_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
practice_godot=${1:-/Volumes/SSK SSD/Kamilunavo/Cache/Godot/4.7.1/Godot.app/Contents/MacOS/Godot}
practice_temp=$(mktemp -d "${TMPDIR:-/tmp}/ninenine-practice-archive.XXXXXX")
trap 'rm -rf -- "$practice_temp"' EXIT HUP INT TERM
printf '%s\n' 'config_version=5' '[application]' 'config/name="NineNinePurePracticeArchiveQA"' '[rendering]' 'renderer/rendering_method="gl_compatibility"' > "$practice_temp/project.godot"
cp "$practice_repo/tests/practice_archive_tests.gd" "$practice_temp/test.gd"
mkdir "$practice_temp/scripts"
cp "$practice_repo/scripts/practice_model.gd" "$practice_temp/scripts/practice_model.gd"
if [ -f "$practice_repo/scripts/practice_archive.gd" ]; then cp "$practice_repo/scripts/practice_archive.gd" "$practice_temp/scripts/practice_archive.gd"; fi
mkdir "$practice_temp/data"
practice_status=0
"$practice_godot" --headless --quit-after 120 --path "$practice_temp" --script "$practice_temp/test.gd" -- "$practice_temp/data" > "$practice_temp/output.log" 2>&1 || practice_status=$?
cat "$practice_temp/output.log"
[ "$practice_status" -eq 0 ] || exit "$practice_status"
if grep -E 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$practice_temp/output.log" >/dev/null; then exit 1; fi
grep -F 'NN PRACTICE ARCHIVE PASS checks=' "$practice_temp/output.log" >/dev/null
