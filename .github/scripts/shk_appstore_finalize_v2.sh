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

# Patch 1: export compliance is write-once in App Store Connect.
pattern = re.compile(r'''  # Explicit export-compliance declaration in ASC too; Info\.plist already carries the same declaration\.\n  body=\$\(jq -nc --arg id "\$build_id" '\{data:\{type:"builds",id:\$id,attributes:\{usesNonExemptEncryption:false\}\}\}'\)\n  f="\$RUNNER_TEMP/\$key-compliance\.json"\n  code=\$\(raw_patch "/v1/builds/\$build_id" "\$body" "\$f"\)\n  require_code 200 "\$code" "\$f" "\$name: export compliance"\n  echo 'EXPORT_COMPLIANCE=NO_NONEXEMPT_ENCRYPTION'\n''')
replacement = '''  # Explicit export-compliance declaration in ASC too; Info.plist already carries the same declaration.
  # Apple makes this write-once. Preserve an actual boolean false instead of treating it like a missing value.
  f="$RUNNER_TEMP/$key-compliance-current.json"
  code=$(raw_get "/v1/builds/$build_id" "$f")
  require_code 200 "$code" "$f" "$name: read export compliance"
  local encryption_value
  encryption_value=$(jq -r 'if (.data.attributes | has("usesNonExemptEncryption")) then (.data.attributes.usesNonExemptEncryption | tostring) else "UNSET" end' "$f")
  if [[ "$encryption_value" == 'UNSET' ]]; then
    body=$(jq -nc --arg id "$build_id" '{data:{type:"builds",id:$id,attributes:{usesNonExemptEncryption:false}}}')
    f="$RUNNER_TEMP/$key-compliance-set.json"
    code=$(raw_patch "/v1/builds/$build_id" "$body" "$f")
    require_code 200 "$code" "$f" "$name: set export compliance"
    encryption_value=$(jq -r '.data.attributes.usesNonExemptEncryption | tostring' "$f")
  fi
  [[ "$encryption_value" == 'false' ]] || { echo "ERROR: $name export compliance is $encryption_value, expected false"; exit 1; }
  echo 'EXPORT_COMPLIANCE=NO_NONEXEMPT_ENCRYPTION'
'''
s, n = pattern.subn(replacement, s, count=1)
if n != 1:
    raise SystemExit(f'Expected to patch one compliance block, patched {n}')

# Patch 2: new paid apps can return an appPriceSchedule relationship before manualPrices exists.
old = '''  if [[ "$code" == '200' ]]; then
    schedule_id=$(jq -r '.data.id // empty' "$f")
    local mf mc
    mf="$RUNNER_TEMP/$key-manual-prices.json"
    mc=$(raw_get "/v1/appPriceSchedules/$schedule_id/manualPrices?include=appPricePoint,territory&limit=200" "$mf")
    require_code 200 "$mc" "$mf" "$name: manual prices"
    if jq -e --arg pp "$price_point_id" '.data[]? | select(.relationships.appPricePoint.data.id==$pp and .attributes.endDate==null)' "$mf" >/dev/null; then
      price_ok='true'
    fi
  elif [[ "$code" != '404' ]]; then
    require_code 200 "$code" "$f" "$name: read price schedule"
  fi
'''
new = '''  if [[ "$code" == '200' ]]; then
    schedule_id=$(jq -r '.data.id // empty' "$f")
    local mf mc
    mf="$RUNNER_TEMP/$key-manual-prices.json"
    mc=$(raw_get "/v1/appPriceSchedules/$schedule_id/manualPrices?include=appPricePoint,territory&limit=200" "$mf")
    if [[ "$mc" == '200' ]]; then
      if jq -e --arg pp "$price_point_id" '.data[]? | select(.relationships.appPricePoint.data.id==$pp and .attributes.endDate==null)' "$mf" >/dev/null; then
        price_ok='true'
      fi
    elif [[ "$mc" == '404' ]]; then
      echo "PRICE_SCHEDULE_PLACEHOLDER=NO_MANUAL_PRICE_YET"
      schedule_id=''
    else
      require_code 200 "$mc" "$mf" "$name: manual prices"
    fi
  elif [[ "$code" != '404' ]]; then
    require_code 200 "$code" "$f" "$name: read price schedule"
  fi
'''
if old not in s:
    raise SystemExit('Expected price schedule block not found')
s = s.replace(old, new, 1)

# Patch 3: ASC now requires local inline IDs in ${local-id} format.
count = s.count('manualPrice-0')
if count != 2:
    raise SystemExit(f'Expected exactly 2 legacy price local IDs, found {count}')
s = s.replace('manualPrice-0', '${manualPrice}', 2)

# Patch 4: explicitly declare these first-party offline tools do not use third-party content.
needle = '''  echo "VERSION_ID=$version_id RELEASE_TYPE=$RELEASE_TYPE"
'''
insert = '''  echo "VERSION_ID=$version_id RELEASE_TYPE=$RELEASE_TYPE"

  body=$(jq -nc --arg id "$version_id" '{data:{type:"appStoreVersions",id:$id,attributes:{contentRightsDeclaration:"DOES_NOT_USE_THIRD_PARTY_CONTENT"}}}')
  f="$RUNNER_TEMP/$key-content-rights.json"
  code=$(raw_patch "/v1/appStoreVersions/$version_id" "$body" "$f")
  require_code 200 "$code" "$f" "$name: content rights"
  echo 'CONTENT_RIGHTS=DOES_NOT_USE_THIRD_PARTY_CONTENT'
'''
if needle not in s:
    raise SystemExit('Version ID marker not found for content-rights patch')
s = s.replace(needle, insert, 1)

# Patch 5: App Privacy answers are the only App Store form not exposed by the public ASC API.
# If Apple reports that they are not published, finish preparing this app, record the blocker,
# and continue with the remaining apps instead of stopping at app #1.
if 'SUBMIT_BLOCKERS=0\n\nfinalize_app() {' not in s:
    s = s.replace('finalize_app() {', 'SUBMIT_BLOCKERS=0\n\nfinalize_app() {', 1)

old_item = '''    code=$(raw_post '/v1/reviewSubmissionItems' "$body" "$f")
    require_code 201 "$code" "$f" "$name: add version to review package"
'''
new_item = '''    code=$(raw_post '/v1/reviewSubmissionItems' "$body" "$f")
    if [[ "$code" != '201' ]]; then
      if [[ "$code" == '409' ]] && jq -e '.. | objects | select(.code? == "STATE_ERROR.APP_DATA_USAGES_REQUIRED")' "$f" >/dev/null 2>&1; then
        echo "SUBMIT_BLOCKER=$key:APP_PRIVACY_NOT_PUBLISHED"
        SUBMIT_BLOCKERS=$((SUBMIT_BLOCKERS + 1))
        return 0
      fi
      require_code 201 "$code" "$f" "$name: add version to review package"
    fi
'''
if old_item not in s:
    raise SystemExit('Review submission item block not found')
s = s.replace(old_item, new_item, 1)

old_end = '''echo
echo 'SHK_APPSTORE_FINALIZER_SUCCESS=1'
'''
new_end = '''echo
if (( SUBMIT_BLOCKERS > 0 )); then
  echo "SHK_APPSTORE_FINALIZER_BLOCKED_APP_PRIVACY=$SUBMIT_BLOCKERS"
  exit 2
fi
echo 'SHK_APPSTORE_FINALIZER_SUCCESS=1'
'''
if old_end not in s:
    raise SystemExit('Final success marker not found')
s = s.replace(old_end, new_end, 1)

p.write_text(s)
PY

bash "$DST"
