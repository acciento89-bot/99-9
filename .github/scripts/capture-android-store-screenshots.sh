#!/usr/bin/env bash
set -euo pipefail

: "${PACKAGE_NAME:?PACKAGE_NAME is required}"
: "${APK_PATH:?APK_PATH is required}"
: "${OUTPUT_DIR:?OUTPUT_DIR is required}"
: "${SECOND_ACTION:?SECOND_ACTION is required}"

readonly apk_path="$GITHUB_WORKSPACE/$APK_PATH"
readonly output_dir="$GITHUB_WORKSPACE/$OUTPUT_DIR"

current_focus() {
  local dump
  local line
  dump="$(adb shell dumpsys window)"
  while IFS= read -r line; do
    if [[ "$line" == *"mCurrentFocus="* ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done <<< "$dump"
  return 0
}

wait_for_foreground() {
  local attempt
  local component
  local focus
  for attempt in $(seq 1 45); do
    focus="$(current_focus)"
    if [[ "$focus" == *"$PACKAGE_NAME"* ]]; then
      return 0
    fi
    if [[ "$focus" == *"ImmersiveModeConfirmation"* ]]; then
      adb shell input keyevent 4
    fi
    if [[ "$focus" == *"Application Not Responding: com.android.launcher3"* ]]; then
      adb shell am force-stop com.android.launcher3
      component="$(resolve_launcher_component)"
      adb shell am start -W -n "$component"
    fi
    sleep 1
  done
  echo "Timed out waiting for $PACKAGE_NAME to become the foreground game." >&2
  current_focus >&2
  return 1
}

resolve_launcher_component() {
  local output
  local line
  local component=""
  output="$(adb shell cmd package resolve-activity --brief \
    -a android.intent.action.MAIN \
    -c android.intent.category.LAUNCHER \
    "$PACKAGE_NAME")"
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "$PACKAGE_NAME/"* ]]; then
      component="$line"
    fi
  done <<< "$output"
  if [[ -z "$component" ]]; then
    echo "Could not resolve exported MAIN/LAUNCHER activity for $PACKAGE_NAME." >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
  printf '%s\n' "$component"
}

launch_app() {
  local component
  component="$(resolve_launcher_component)"
  adb shell am force-stop "$PACKAGE_NAME"
  adb shell am start -W -n "$component"
  wait_for_foreground
  sleep 8
}

assert_clean_foreground() {
  local focus
  focus="$(current_focus)"
  if [[ "$focus" != *"$PACKAGE_NAME"* ]]; then
    echo "Expected $PACKAGE_NAME in mCurrentFocus; refusing to capture a system overlay." >&2
    printf '%s\n' "$focus" >&2
    return 1
  fi
}

mkdir -p "$output_dir"
rm -f "$output_dir"/*.png
test -s "$apk_path"
adb install -r "$apk_path"
adb shell settings put global hide_error_dialogs 1
adb shell settings put secure immersive_mode_confirmations confirmed
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 0

launch_app
assert_clean_foreground
adb exec-out screencap -p > "$output_dir/01-current-ui.png"

case "$SECOND_ACTION" in
  tap)
    adb shell input tap "${TAP_X:-540}" "${TAP_Y:-1900}"
    sleep 4
    ;;
  swipe)
    adb shell input swipe 540 1900 540 650 600
    sleep 4
    ;;
  dark)
    adb shell cmd uimode night yes
    launch_app
    ;;
  *)
    echo "Unsupported SECOND_ACTION: $SECOND_ACTION" >&2
    exit 1
    ;;
esac

assert_clean_foreground
adb exec-out screencap -p > "$output_dir/02-current-ui-detail.png"

if ! python3 - "$output_dir" <<'PY'
import hashlib
import math
import struct
import sys
import zlib
from pathlib import Path

def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else b if pb <= pc else c

def png_samples(data):
    pos = 8
    compressed = bytearray()
    width = height = bit_depth = color_type = None
    while pos < len(data):
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b'IHDR':
            width, height, bit_depth, color_type = struct.unpack('>IIBB', payload[:10])
        elif kind == b'IDAT':
            compressed.extend(payload)
        elif kind == b'IEND':
            break
    assert (width, height) == (1080, 2400), (width, height)
    assert bit_depth == 8 and color_type in (2, 6), (bit_depth, color_type)
    channels = 3 if color_type == 2 else 4
    stride = width * channels
    raw = zlib.decompress(bytes(compressed))
    previous = bytearray(stride)
    colors = set()
    luminances = []
    offset = 0
    for y in range(height):
        filter_type = raw[offset]
        scan = bytearray(raw[offset + 1:offset + 1 + stride])
        offset += stride + 1
        for i, value in enumerate(scan):
            left = scan[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 1:
                scan[i] = (value + left) & 255
            elif filter_type == 2:
                scan[i] = (value + up) & 255
            elif filter_type == 3:
                scan[i] = (value + ((left + up) // 2)) & 255
            elif filter_type == 4:
                scan[i] = (value + paeth(left, up, upper_left)) & 255
            elif filter_type != 0:
                raise AssertionError(f'Unsupported PNG filter: {filter_type}')
        if y % 24 == 0:
            for x in range(0, width, 24):
                index = x * channels
                r, g, b = scan[index:index + 3]
                colors.add((r // 16, g // 16, b // 16))
                luminances.append((299 * r + 587 * g + 114 * b) / 1000)
        previous = scan
    mean = sum(luminances) / len(luminances)
    deviation = math.sqrt(sum((value - mean) ** 2 for value in luminances) / len(luminances))
    return len(colors), max(luminances) - min(luminances), deviation

paths = sorted(Path(sys.argv[1]).glob('*.png'))
assert len(paths) == 2, paths
digests = set()
for path in paths:
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    colors, luminance_range, deviation = png_samples(data)
    assert colors >= 24 and luminance_range >= 48 and deviation >= 10, (
        f'{path} looks near-monochrome or like a splash/system overlay: '
        f'colors={colors}, luminance_range={luminance_range:.1f}, deviation={deviation:.1f}'
    )
    digests.add(hashlib.sha256(data).hexdigest())
assert len(digests) == 2, 'Screenshots must show two distinct real game states'
PY
then
  echo "Screenshot validation failed; dumping Godot and Android runtime logs." >&2
  adb logcat -d -v brief 'Godot:*' 'godot:*' 'AndroidRuntime:E' '*:S' >&2 || true
  exit 1
fi
