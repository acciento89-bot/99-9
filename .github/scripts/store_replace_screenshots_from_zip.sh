#!/usr/bin/env bash
set -euo pipefail

API='https://api.appstoreconnect.apple.com'
REQUEST='.github/store-screenshot-replace-request.json'
ARCHIVE='.github/Kamilunavo_AppStore_Screenshots_iPhone_69.zip'

: "${ASC_ISSUER_ID:?missing ASC_ISSUER_ID}"
: "${ASC_KEY_ID:?missing ASC_KEY_ID}"
: "${ASC_PRIVATE_KEY_B64:?missing ASC_PRIVATE_KEY_B64}"
test -s "$REQUEST"
test -s "$ARCHIVE" || { echo "ERROR: upload $ARCHIVE first"; exit 1; }
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

raw_get(){ local p="$1" o="$2"; curl --globoff -sS -o "$o" -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$API$p"; }
raw_post(){ local p="$1" b="$2" o="$3"; curl --globoff -sS -o "$o" -w '%{http_code}' -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$b" "$API$p"; }
raw_patch(){ local p="$1" b="$2" o="$3"; curl --globoff -sS -o "$o" -w '%{http_code}' -X PATCH -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$b" "$API$p"; }
raw_delete(){ local p="$1" o="$2"; curl --globoff -sS -o "$o" -w '%{http_code}' -X DELETE -H "Authorization: Bearer $TOKEN" "$API$p"; }
require_code(){ local e="$1" a="$2" f="$3" l="$4"; [[ "$a" == "$e" ]] || { echo "ERROR: $l HTTP $a"; jq '.' "$f" 2>/dev/null || cat "$f" || true; exit 1; }; }

upload_parts(){
  local image="$1" reservation="$2"
  python3 - "$image" "$reservation" <<'PY'
import json, sys, urllib.request
image_path, reservation_path = sys.argv[1], sys.argv[2]
with open(reservation_path, encoding='utf-8') as f: payload=json.load(f)
with open(image_path,'rb') as src:
    for op in payload['data']['attributes']['uploadOperations']:
        src.seek(int(op['offset'])); data=src.read(int(op['length']))
        headers={h['name']:h['value'] for h in op.get('requestHeaders',[])}
        req=urllib.request.Request(op['url'],data=data,headers=headers,method=op['method'])
        with urllib.request.urlopen(req,timeout=120) as r:
            if not 200 <= r.status < 300: raise RuntimeError(r.status)
PY
}

wait_complete(){
  local sid="$1" label="$2" f code state
  for _ in $(seq 1 80); do
    f="$RUNNER_TEMP/state-$sid.json"; code=$(raw_get "/v1/appScreenshots/$sid" "$f"); require_code 200 "$code" "$f" "$label state"
    state=$(jq -r '.data.attributes.assetDeliveryState.state // empty' "$f")
    [[ "$state" == COMPLETE ]] && return 0
    [[ "$state" == FAILED ]] && { jq '.data.attributes.assetDeliveryState' "$f"; exit 1; }
    sleep 3
  done
  echo "ERROR: timeout $label"; exit 1
}

ROOT="$RUNNER_TEMP/store-screenshots"
rm -rf "$ROOT" && mkdir -p "$ROOT"
unzip -q "$ARCHIVE" -d "$ROOT"

replace_app(){
  local key="$1" folder="$2" bundle="$3"
  local work="$RUNNER_TEMP/screens-$key"
  rm -rf "$work" && mkdir -p "$work"
  local folder_path="$ROOT/$folder"
  test -d "$folder_path" || { echo "ERROR: missing folder $folder"; exit 1; }
  local images=()
  while IFS= read -r p; do images+=("$p"); done < <(find "$folder_path" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort)
  [[ ${#images[@]} -ge 1 && ${#images[@]} -le 10 ]] || { echo "ERROR: $key screenshot count ${#images[@]}"; exit 1; }

  for image in "${images[@]}"; do
    dims=$(sips -g pixelWidth -g pixelHeight "$image" 2>/dev/null | awk '/pixelWidth:/{w=$2}/pixelHeight:/{h=$2}END{print w"x"h}')
    [[ "$dims" == 1320x2868 ]] || { echo "ERROR: $image has $dims"; exit 1; }
  done

  echo "===== $key (${#images[@]} screenshots) ====="
  local f code app_id version_id loc_id set_id body
  f="$work/app.json"; code=$(raw_get "/v1/apps?filter%5BbundleId%5D=$bundle&limit=5" "$f"); require_code 200 "$code" "$f" "$key find app"; app_id=$(jq -r '.data[0].id // empty' "$f"); [[ -n "$app_id" ]]
  f="$work/ver.json"; code=$(raw_get "/v1/apps/$app_id/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BversionString%5D=1.0&limit=20" "$f"); require_code 200 "$code" "$f" "$key version"; version_id=$(jq -r '.data[0].id // empty' "$f"); [[ -n "$version_id" ]]
  f="$work/loc.json"; code=$(raw_get "/v1/appStoreVersions/$version_id/appStoreVersionLocalizations?limit=50" "$f"); require_code 200 "$code" "$f" "$key locales"; loc_id=$(jq -r '.data[] | select(.attributes.locale=="de-DE") | .id' "$f" | head -1); [[ -n "$loc_id" ]]
  f="$work/sets.json"; code=$(raw_get "/v1/appStoreVersionLocalizations/$loc_id/appScreenshotSets?limit=100" "$f"); require_code 200 "$code" "$f" "$key sets"; set_id=$(jq -r '.data[] | select(.attributes.screenshotDisplayType=="APP_IPHONE_67") | .id' "$f" | head -1)
  if [[ -z "$set_id" ]]; then
    body=$(jq -nc --arg loc "$loc_id" '{data:{type:"appScreenshotSets",attributes:{screenshotDisplayType:"APP_IPHONE_67"},relationships:{appStoreVersionLocalization:{data:{type:"appStoreVersionLocalizations",id:$loc}}}}}')
    f="$work/create-set.json"; code=$(raw_post '/v1/appScreenshotSets' "$body" "$f"); require_code 201 "$code" "$f" "$key create set"; set_id=$(jq -r '.data.id' "$f")
  fi

  f="$work/old.json"; code=$(raw_get "/v1/appScreenshotSets/$set_id/appScreenshots?limit=200" "$f"); require_code 200 "$code" "$f" "$key old screenshots"
  old=$(jq '.data|length' "$f")
  while read -r sid; do
    [[ -n "$sid" ]] || continue
    df="$work/delete-$sid.json"; dc=$(raw_delete "/v1/appScreenshots/$sid" "$df"); require_code 204 "$dc" "$df" "$key delete old screenshot"
  done < <(jq -r '.data[]?.id' "$f")
  echo "REMOVED=$old"

  local uploaded=0 image base size reservation sid checksum commit
  for image in "${images[@]}"; do
    base=$(basename "$image"); size=$(stat -f%z "$image")
    body=$(jq -nc --arg fn "$base" --argjson fs "$size" --arg set "$set_id" '{data:{type:"appScreenshots",attributes:{fileName:$fn,fileSize:$fs},relationships:{appScreenshotSet:{data:{type:"appScreenshotSets",id:$set}}}}}')
    reservation="$work/reserve-$base.json"; code=$(raw_post '/v1/appScreenshots' "$body" "$reservation"); require_code 201 "$code" "$reservation" "$key reserve $base"; sid=$(jq -r '.data.id' "$reservation")
    upload_parts "$image" "$reservation"
    checksum=$(md5 -q "$image")
    body=$(jq -nc --arg id "$sid" --arg md5 "$checksum" '{data:{type:"appScreenshots",id:$id,attributes:{uploaded:true,sourceFileChecksum:$md5}}}')
    commit="$work/commit-$base.json"; code=$(raw_patch "/v1/appScreenshots/$sid" "$body" "$commit"); require_code 200 "$code" "$commit" "$key commit $base"
    wait_complete "$sid" "$key/$base"
    uploaded=$((uploaded+1)); echo "UPLOADED=$key/$base"
  done

  f="$work/final.json"; code=$(raw_get "/v1/appScreenshotSets/$set_id/appScreenshots?limit=200" "$f"); require_code 200 "$code" "$f" "$key final"
  complete=$(jq '[.data[] | select(.attributes.assetDeliveryState.state=="COMPLETE")]|length' "$f")
  [[ "$complete" -eq "$uploaded" ]] || { echo "ERROR: $key COMPLETE=$complete expected=$uploaded"; exit 1; }
  echo "SCREENSHOT_REPLACE_SUCCESS=$key:$complete"
}

replace_app 'kaltecalc' 'KaelteCalc' 'de.kamilunav.kaltecalc'
replace_app 'lueftungscalc' 'LueftungsCalc' 'de.kamilunavo.luftungscalc'
replace_app 'heizkoerpercalc' 'HeizkoerperCalc' 'de.kamilunavo.heizkorpercalc'
replace_app 'rohrcalc' 'RohrCalc' 'de.kamilunavo.rohrcalc'
replace_app 'anlagencheck' 'AnlagenCheck' 'de.kamilunavo.servicecheck'
replace_app 'volumecalc' 'VolumeCalc' 'de.kamilunavo.volumecalc'

echo 'STORE_SCREENSHOT_REPLACEMENT_SUCCESS=1'
