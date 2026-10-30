#!/bin/sh
# Exact exported-resource mixer regression. No Editor/import/build/provider/key.
set -eu
[ "$#" -eq 3 ] || { printf '%s\n' 'Usage: run-qoa-loop-tests.sh GODOT AAB AAB_SHA256' >&2; exit 2; }
qoa_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
qoa_godot=$1
qoa_bundle=$2
qoa_sha=$3
qoa_temp=$(mktemp -d "${TMPDIR:-/tmp}/nine-qoa-loop.XXXXXX")
trap 'rm -rf -- "$qoa_temp"' EXIT HUP INT TERM
mkdir -p "$qoa_temp/exported" "$qoa_temp/data"
printf '%s\n' 'config_version=5' '[application]' 'config/name="CodexNineExportedQoaLoopTests"' '[audio]' 'driver/mix_rate=22050' '[debug]' 'file_logging/enable_file_logging=false' '[rendering]' 'renderer/rendering_method="gl_compatibility"' > "$qoa_temp/project.godot"
cp "$qoa_repo/scripts/audio_service.gd" "$qoa_temp/audio_service.gd"
cp "$qoa_repo/tests/qoa_loop_boundary_tests.gd" "$qoa_temp/test.gd"
python3 - "$qoa_bundle" "$qoa_sha" "$qoa_temp/exported" <<'PY'
import hashlib, pathlib, re, sys, zipfile
bundle, expected, output = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
assert re.fullmatch('[a-f0-9]{64}', expected), 'Explicit whole-AAB SHA256 required'
def sha_file(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''): value.update(block)
    return value.hexdigest()
assert 0 < bundle.stat().st_size < 768 * 1024 * 1024 and sha_file(bundle) == expected, 'AAB differs from explicit reviewed input'
resources = {
    'precision-loop.wav': ('534b65b6413d5e8654ecb3a078104415', 'b4424c66ea1b8978aade130ea3bf47fad6cdb8fb638d927ab0b209b4c2539a9e'),
    'ui.wav': ('d54e8bc37b8ccee18240932350cecc18', '766308e0779fe0ccca78c77aeec71e1ce8759da3e850109a7df1b326151998f6'),
    'hit.wav': ('96dc477cdf4a42f381370dba6e3f75ce', 'ba6446c7986f98f78c9a86912868036704ac6bca720deb2c62d61ea410e45177'),
    'miss.wav': ('4696074401e3ee5b47b2144bfa6ac22c', '0ab0cd6622092a0b51a96b19f6cd5d6d5a92b3432684299ab7daa99583e4aac8'),
}
with zipfile.ZipFile(bundle) as archive:
    for name, (suffix, digest) in resources.items():
        entry = 'assetPackInstallTime/assets/.godot/imported/' + name + '-' + suffix + '.sample'
        matches = [item for item in archive.infolist() if item.filename == entry]
        assert len(matches) == 1 and 0 < matches[0].file_size < 2 * 1024 * 1024, 'Missing/ambiguous/oversized reviewed resource'
        with archive.open(matches[0]) as source: raw = source.read(2 * 1024 * 1024)
        assert hashlib.sha256(raw).hexdigest() == digest, 'Exported resource bytes changed'
        with (output / (name + '.sample')).open('xb') as target: target.write(raw)
assert sha_file(bundle) == expected, 'AAB changed during extraction'
print('NINE QOA INPUT AAB_SHA256=' + expected + ' exactExportedResources=4')
PY
qoa_status=0
"$qoa_godot" --headless --audio-driver Dummy --path "$qoa_temp" --script res://test.gd -- "$qoa_temp/data" > "$qoa_temp/result.log" 2>&1 || qoa_status=$?
cat "$qoa_temp/result.log"
[ "$qoa_status" -eq 0 ] || exit "$qoa_status"
if grep -E 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script' "$qoa_temp/result.log" >/dev/null; then exit 1; fi
grep -F 'NINE EXPORTED QOA LOOP PASS checks=' "$qoa_temp/result.log" >/dev/null
