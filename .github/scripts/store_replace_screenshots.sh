#!/usr/bin/env bash
set -euo pipefail

API='https://api.appstoreconnect.apple.com'
REQUEST='.github/store-screenshot-replace-request.json'
PAYLOAD_ROOT='.github/screenshot_payloads'

: "${ASC_ISSUER_ID:?missing ASC_ISSUER_ID}"
: "${ASC_KEY_ID:?missing ASC_KEY_ID}"
: "${ASC_PRIVATE_KEY_B64:?missing ASC_PRIVATE_KEY_B64}"
test -s "$REQUEST"
jq -e '.version == "1.0" and .replace_existing_iphone == true' "$REQUEST" >/dev/null

KEY_DIR="$RUNNER_TEMP/store-screenshot-replace"
mkdir -p "$KEY_DIR"
KEY_PATH="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
printf '%s' "$ASC_PRIVATE_KEY_B64" | tr -d '\r\n ' | base64 --decode > "$KEY_PATH"
chmod 600 "$KEY_PATH"
export ASC_KEY_PATH="$KEY_PATH"
trap 'rm -rf "$KEY_DIR"' EXIT

TOKEN=$(ruby <<'RUBY'
require 'openssl'; require 'base64'; require 'json'
def b(v); Base64.urlsafe_encode64(v,padding:false); end
key=OpenSSL::PKey.read(File.read(ENV.fetch('ASC_KEY_PATH'))); now=Time.now.to_i
h=b(JSON.generate({alg:'ES256',kid:ENV.fetch('ASC_KEY_ID'),typ:'JWT'}))
p=b(JSON.generate({iss:ENV.fetch('ASC_ISSUER_ID'),iat:now,exp:now+1200,aud:'appstoreconnect-v1'}))
s="#{h}.#{p}"
seq=OpenSSL::ASN1.decode(key.sign(OpenSSL::Digest::SHA256.new,s))
raw=seq.value.map{|i|[i.value.to_i.to_s(16).rjust(64,'0')].pack('H*')}.join
puts "#{s}.#{b(raw)}"
RUBY
)

raw_get() {
  local path="$1" out="$2"
  /usr/bin/curl --globoff --silent --show-error --output "$out" --write-out '%{http_code}' \
    -H "Authorization: Bearer $TOKEN" "$API$path"
}
raw_post() {
  local path="$1" body="$2" out="$3"
  /usr/bin/curl --globoff --silent --show-error --output "$out" --write-out '%{http_code}' -X POST \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$body" "$API$path"
}
raw_patch() {
  local path="$1" body="$2" out="$3"
  /usr/bin/curl --globoff --silent --show-error --output "$out" --write-out '%{http_code}' -X PATCH \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$body" "$API$path"
}
raw_delete() {
  local path="$1" out="$2"
  /usr/bin/curl --globoff --silent --show-error --output "$out" --write-out '%{http_code}' -X DELETE \
    -H "Authorization: Bearer $TOKEN" "$API$path"
}
require_code() {
  local expected="$1" actual="$2" file="$3" label="$4"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: $label failed: HTTP $actual"
    jq '.' "$file" 2>/dev/null || cat "$file" || true
    exit 1
  fi
}

upload_parts() {
  local image="$1" reservation="$2"
  python3 - "$image" "$reservation" <<'PY'
import json, sys, urllib.request
image_path, reservation_path = sys.argv[1], sys.argv[2]
with open(reservation_path, 'r', encoding='utf-8') as f:
    payload = json.load(f)
ops = payload['data']['attributes']['uploadOperations']
with open(image_path, 'rb') as src:
    for op in ops:
        src.seek(int(op['offset']))
        data = src.read(int(op['length']))
        headers = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
        req = urllib.request.Request(op['url'], data=data, headers=headers, method=op['method'])
        with urllib.request.urlopen(req, timeout=120) as resp:
            if not 200 <= resp.status < 300:
                raise RuntimeError(f"upload operation failed with HTTP {resp.status}")
PY
}

wait_complete() {
  local sid="$1" label="$2" f code state
  for _ in $(seq 1 60); do
    f="$RUNNER_TEMP/screenshot-state-$sid.json"
    code=$(raw_get "/v1/appScreenshots/$sid" "$f")
    require_code 200 "$code" "$f" "$label: read screenshot state"
    state=$(jq -r '.data.attributes.assetDeliveryState.state // empty' "$f")
    case "$state" in
      COMPLETE) return 0 ;;
      FAILED)
        echo "ERROR: $label processing failed"
        jq '.data.attributes.assetDeliveryState' "$f" || true
        exit 1
        ;;
      *) sleep 3 ;;
    esac
  done
  echo "ERROR: timed out waiting for $label"
  exit 1
}

replace_app() {
  local key="$1" bundle="$2"
  local payload_b64="$PAYLOAD_ROOT/$key.zip.b64"
  test -s "$payload_b64" || { echo "ERROR: payload missing for $key"; exit 1; }

  local work="$RUNNER_TEMP/screens-$key"
  rm -rf "$work" && mkdir -p "$work"
  base64 --decode < "$payload_b64" > "$work/screens.zip"
  unzip -q "$work/screens.zip" -d "$work/images"
  mapfile -t images < <(find "$work/images" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort)
  [[ ${#images[@]} -ge 1 && ${#images[@]} -le 10 ]] || { echo "ERROR: invalid screenshot count for $key"; exit 1; }

  for image in "${images[@]}"; do
    local dims
    dims=$(sips -g pixelWidth -g pixelHeight "$image" 2>/dev/null | awk '/pixelWidth:/{w=$2}/pixelHeight:/{h=$2}END{print w"x"h}')
    [[ "$dims" == '1320x2868' ]] || { echo "ERROR: $key $(basename "$image") is $dims, expected 1320x2868"; exit 1; }
  done

  echo "========== $key / $bundle =========="
  local f code app_id version_id loc_id set_id
  f="$work/app.json"; code=$(raw_get "/v1/apps?filter%5BbundleId%5D=$bundle&limit=5" "$f"); require_code 200 "$code" "$f" "$key: find app"
  app_id=$(jq -r '.data[0].id // empty' "$f"); [[ -n "$app_id" ]] || { echo "ERROR: app not found for $bundle"; exit 1; }

  f="$work/versions.json"; code=$(raw_get "/v1/apps/$app_id/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BversionString%5D=1.0&limit=20" "$f"); require_code 200 "$code" "$f" "$key: find version"
  version_id=$(jq -r '.data[0].id // empty' "$f"); [[ -n "$version_id" ]] || { echo "ERROR: version 1.0 not found for $key"; exit 1; }

  f="$work/locs.json"; code=$(raw_get "/v1/appStoreVersions/$version_id/appStoreVersionLocalizations?limit=50" "$f"); require_code 200 "$code" "$f" "$key: localizations"
  loc_id=$(jq -r '.data[] | select(.attributes.locale=="de-DE") | .id' "$f" | head -1)
  [[ -n "$loc_id" ]] || { echo "ERROR: de-DE localization missing for $key"; exit 1; }

  f="$work/sets.json"; code=$(raw_get "/v1/appStoreVersionLocalizations/$loc_id/appScreenshotSets?limit=100" "$f"); require_code 200 "$code" "$f" "$key: screenshot sets"
  set_id=$(jq -r '.data[] | select(.attributes.screenshotDisplayType=="APP_IPHONE_67") | .id' "$f" | head -1)
  if [[ -z "$set_id" ]]; then
    local body
    body=$(jq -nc --arg loc "$loc_id" '{data:{type:"appScreenshotSets",attributes:{screenshotDisplayType:"APP_IPHONE_67"},relationships:{appStoreVersionLocalization:{data:{type:"appStoreVersionLocalizations",id:$loc}}}}}')
    f="$work/set-create.json"; code=$(raw_post '/v1/appScreenshotSets' "$body" "$f"); require_code 201 "$code" "$f" "$key: create iPhone set"
    set_id=$(jq -r '.data.id' "$f")
  fi

  f="$work/current.json"; code=$(raw_get "/v1/appScreenshotSets/$set_id/appScreenshots?limit=200" "$f"); require_code 200 "$code" "$f" "$key: current screenshots"
  local old_count
  old_count=$(jq '.data | length' "$f")
  while read -r sid; do
    [[ -n "$sid" ]] || continue
    local df="$work/delete-$sid.json" dc
    dc=$(raw_delete "/v1/appScreenshots/$sid" "$df")
    require_code 204 "$dc" "$df" "$key: delete old screenshot"
  done < <(jq -r '.data[]?.id' "$f")
  echo "OLD_IPHONE_SCREENSHOTS_REMOVED=$old_count"

  local image base size body reservation sid checksum commit statef statecode
  local uploaded=0
  for image in "${images[@]}"; do
    base=$(basename "$image")
    size=$(stat -f%z "$image")
    body=$(jq -nc --arg fn "$base" --argjson fs "$size" --arg set "$set_id" '{data:{type:"appScreenshots",attributes:{fileName:$fn,fileSize:$fs},relationships:{appScreenshotSet:{data:{type:"appScreenshotSets",id:$set}}}}}')
    reservation="$work/reserve-$base.json"
    code=$(raw_post '/v1/appScreenshots' "$body" "$reservation")
    require_code 201 "$code" "$reservation" "$key: reserve $base"
    sid=$(jq -r '.data.id' "$reservation")

    upload_parts "$image" "$reservation"
    checksum=$(md5 -q "$image")
    body=$(jq -nc --arg id "$sid" --arg md5 "$checksum" '{data:{type:"appScreenshots",id:$id,attributes:{uploaded:true,sourceFileChecksum:$md5}}}')
    commit="$work/commit-$base.json"
    code=$(raw_patch "/v1/appScreenshots/$sid" "$body" "$commit")
    require_code 200 "$code" "$commit" "$key: commit $base"
    wait_complete "$sid" "$key/$base"
    uploaded=$((uploaded + 1))
    echo "UPLOADED=$key/$base"
  done

  f="$work/final.json"; code=$(raw_get "/v1/appScreenshotSets/$set_id/appScreenshots?limit=200" "$f"); require_code 200 "$code" "$f" "$key: final screenshots"
  local complete
  complete=$(jq '[.data[]? | select(.attributes.assetDeliveryState.state=="COMPLETE")] | length' "$f")
  [[ "$complete" -eq "$uploaded" ]] || { echo "ERROR: $key final COMPLETE count $complete != uploaded $uploaded"; exit 1; }
  echo "SCREENSHOT_REPLACE_SUCCESS=$key:$complete"
}

replace_app 'kaltecalc' 'de.kamilunav.kaltecalc'
replace_app 'lueftungscalc' 'de.kamilunavo.luftungscalc'
replace_app 'heizkoerpercalc' 'de.kamilunavo.heizkorpercalc'
replace_app 'rohrcalc' 'de.kamilunavo.rohrcalc'
replace_app 'anlagencheck' 'de.kamilunavo.servicecheck'
replace_app 'volumecalc' 'de.kamilunavo.volumecalc'

echo 'STORE_SCREENSHOT_REPLACEMENT_SUCCESS=1'
