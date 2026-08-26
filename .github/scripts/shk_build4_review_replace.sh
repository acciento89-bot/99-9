#!/usr/bin/env bash
set -euo pipefail

SRC='bridge/.github/scripts/shk_build3_review_replace.sh'
DST="$RUNNER_TEMP/shk_build4_review_replace_runtime.sh"
test -s "$SRC"
cp "$SRC" "$DST"

python3 - "$DST" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
replacements = [
    ('shk-build3-review-request.json', 'shk-build4-review-request.json'),
    ('.replace_with_build == "3"', '.replace_with_build == "4"'),
    ("TARGET_BUILD='3'", "TARGET_BUILD='4'"),
    ("CURRENT_BUILD_NUMBER == '3'", "CURRENT_BUILD_NUMBER == '4'"),
    ('Build 3', 'Build 4'),
    ('build3', 'build4'),
    ('BUILD3', 'BUILD4'),
]
for old, new in replacements:
    if old not in s:
        raise SystemExit(f'Expected Build 3 pattern missing: {old}')
    s = s.replace(old, new)
p.write_text(s)
PY

bash "$DST"
