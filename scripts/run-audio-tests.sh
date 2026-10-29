#!/bin/sh
# Isolated script execution only: no Editor/import/export, providers or user data.
set -eu
audio_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
audio_godot=${1:-/Volumes/SSK SSD/Kamilunavo/Cache/Godot/4.7.2/Godot.app/Contents/MacOS/Godot}
audio_suite=${2:-audio}
case "$audio_suite" in
    audio) audio_test=audio_tests.gd; audio_marker='NN AUDIO PASS checks=' ;;
    practice) audio_test=practice_integration_tests.gd; audio_marker='NN PRACTICE INTEGRATION PASS checks=' ;;
    *) printf '%s\n' 'Expected suite: audio or practice' >&2; exit 2 ;;
esac
audio_temp=$(mktemp -d "${TMPDIR:-/tmp}/ninenine-audio-tests.XXXXXX")
trap 'rm -rf -- "$audio_temp"' EXIT HUP INT TERM
printf '%s\n' 'config_version=5' '[application]' 'config/name="NineNineOfflineAudioTests"' '[display]' 'window/size/viewport_width=1080' 'window/size/viewport_height=1920' '[input_devices]' 'pointing/emulate_mouse_from_touch=false' '[rendering]' 'renderer/rendering_method="gl_compatibility"' > "$audio_temp/project.godot"
mkdir -p "$audio_temp/scripts" "$audio_temp/data" "$audio_temp/assets/fonts/hammersmithone" "$audio_temp/assets/audio"
cp "$audio_repo"/scripts/main_v*.gd "$audio_repo/scripts/main_practice.gd" "$audio_repo/scripts/practice_model.gd" "$audio_repo/scripts/practice_archive.gd" "$audio_temp/scripts/"
for audio_source in audio_service.gd main_audio.gd ranking_captions.gd; do
    if [ -f "$audio_repo/scripts/$audio_source" ]; then cp "$audio_repo/scripts/$audio_source" "$audio_temp/scripts/"; fi
done
cp "$audio_repo/assets/fonts/hammersmithone/HammersmithOne-Regular.ttf" "$audio_temp/assets/fonts/hammersmithone/"
if [ -d "$audio_repo/assets/audio" ]; then cp "$audio_repo/assets/audio/"*.wav "$audio_temp/assets/audio/"; fi
cp "$audio_repo/tests/$audio_test" "$audio_temp/test.gd"
# Only the font-loader declaration differs in this inert fixture. Raw FontFile
# loads the exact original TTF without a local Editor/import or cached .godot.
python3 - "$audio_temp/scripts/main_v3.gd" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); s = p.read_text()
old = 'const PRODUCT_FONT = preload("res://assets/fonts/hammersmithone/HammersmithOne-Regular.ttf")'
assert s.count(old) == 1
new = '''var PRODUCT_FONT := _audio_fixture_raw_font()
func _audio_fixture_raw_font() -> FontFile:
    var font := FontFile.new()
    assert(font.load_dynamic_font("res://assets/fonts/hammersmithone/HammersmithOne-Regular.ttf") == OK)
    return font'''
p.write_text(s.replace(old, new))
PY
audio_status=0
"$audio_godot" --headless --audio-driver Dummy --path "$audio_temp" --check-only --script "$audio_temp/scripts/main_audio.gd" > "$audio_temp/parse.log" 2>&1 || audio_status=$?
cat "$audio_temp/parse.log"
[ "$audio_status" -eq 0 ] || exit "$audio_status"
if grep -E 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$audio_temp/parse.log" >/dev/null; then exit 1; fi
"$audio_godot" --headless --audio-driver Dummy --path "$audio_temp" --script "$audio_temp/test.gd" -- "$audio_temp/data" > "$audio_temp/output.log" 2>&1 || audio_status=$?
cat "$audio_temp/output.log"
[ "$audio_status" -eq 0 ] || exit "$audio_status"
if grep -E 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$audio_temp/output.log" >/dev/null; then exit 1; fi
grep -F "$audio_marker" "$audio_temp/output.log" >/dev/null
