#!/usr/bin/env bash
set -euo pipefail

SRC='bridge/.github/scripts/shk_appstore_finalize.sh'
DST="$RUNNER_TEMP/shk_appstore_finalize_v2_runtime.sh"
test -s "$SRC"
cp "$SRC" "$DST"

python3 - "$DST" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
s = p.read_text()
pattern = re.compile(r'''  # Explicit export-compliance declaration in ASC too; Info\.plist already carries the same declaration\.\n  body=\$\(jq -nc --arg id "\$build_id" '\{data:\{type:"builds",id:\$id,attributes:\{usesNonExemptEncryption:false\}\}\}'\)\n  f="\$RUNNER_TEMP/\$key-compliance\.json"\n  code=\$\(raw_patch "/v1/builds/\$build_id" "\$body" "\$f"\)\n  require_code 200 "\$code" "\$f" "\$name: export compliance"\n  echo 'EXPORT_COMPLIANCE=NO_NONEXEMPT_ENCRYPTION'\n''')
replacement = '''  # Explicit export-compliance declaration in ASC too; Info.plist already carries the same declaration.
  # Apple makes this write-once. If Build 2 already says false, verify and continue.
  f="$RUNNER_TEMP/$key-compliance-current.json"
  code=$(raw_get "/v1/builds/$build_id" "$f")
  require_code 200 "$code" "$f" "$name: read export compliance"
  local encryption_value
  encryption_value=$(jq -r '.data.attributes.usesNonExemptEncryption // "UNSET"' "$f")
  if [[ "$encryption_value" == 'UNSET' ]]; then
    body=$(jq -nc --arg id "$build_id" '{data:{type:"builds",id:$id,attributes:{usesNonExemptEncryption:false}}}')
    f="$RUNNER_TEMP/$key-compliance-set.json"
    code=$(raw_patch "/v1/builds/$build_id" "$body" "$f")
    require_code 200 "$code" "$f" "$name: set export compliance"
    encryption_value=$(jq -r '.data.attributes.usesNonExemptEncryption' "$f")
  fi
  [[ "$encryption_value" == 'false' ]] || { echo "ERROR: $name export compliance is $encryption_value, expected false"; exit 1; }
  echo 'EXPORT_COMPLIANCE=NO_NONEXEMPT_ENCRYPTION'
'''
ns, n = pattern.subn(replacement, s, count=1)
if n != 1:
    raise SystemExit(f'Expected to patch one compliance block, patched {n}')
p.write_text(ns)
PY

bash "$DST"
