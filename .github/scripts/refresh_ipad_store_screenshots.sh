#!/usr/bin/env bash
set -euo pipefail

API='https://api.appstoreconnect.apple.com'
REQUEST='.github/ipad-store-screenshot-refresh-request.json'
TARGET_TYPE='APP_IPAD_PRO_3GEN_129'

: "${ASC_ISSUER_ID:?missing ASC_ISSUER_ID}"
: "${ASC_KEY_ID:?missing ASC_KEY_ID}"
: "${ASC_PRIVATE_KEY_B64:?missing ASC_PRIVATE_KEY_B64}"
test -s "$REQUEST"
jq -e '.version == "1.0" and .generate_real_ipad_screenshots == true and .replace_existing_ipad == true' "$REQUEST" >/dev/null

test -d shk
test -d volumecalc

OUT="$RUNNER_TEMP/ipad-store-screenshots"
rm -rf "$OUT" && mkdir -p "$OUT"

cleanup() {
  if [[ -n "${UDID:-}" ]]; then
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  fi
  rm -rf "${KEY_DIR:-}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

DEVICE_TYPE=$(xcrun simctl list devicetypes -j | jq -r '.devicetypes[] | select(.name | test("iPad (Pro|Air) 13-inch")) | .identifier' | head -1)
if [[ -z "$DEVICE_TYPE" ]]; then
  DEVICE_TYPE=$(xcrun simctl list devicetypes -j | jq -r '.devicetypes[] | select(.name | test("iPad Pro \(12.9-inch\)")) | .identifier' | head -1)
fi
[[ -n "$DEVICE_TYPE" ]] || { echo 'ERROR: no 13-inch/12.9-inch iPad device type available'; xcrun simctl list devicetypes; exit 1; }

RUNTIME=$(xcrun simctl list runtimes -j | jq -r '.runtimes[] | select(.platform=="iOS" and .isAvailable==true) | .identifier' | tail -1)
[[ -n "$RUNTIME" ]] || { echo 'ERROR: no available iOS simulator runtime'; xcrun simctl list runtimes; exit 1; }

UDID=$(xcrun simctl create 'Kamilunavo Store iPad' "$DEVICE_TYPE" "$RUNTIME")
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time '9:41' --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true

echo "SIMULATOR=$UDID"
echo "DEVICE_TYPE=$DEVICE_TYPE"
echo "RUNTIME=$RUNTIME"

capture_app() {
  local project="$1"
  local scheme="$2"
  local product="$3"
  local bundle="$4"
  local key="$5"
  local base_dir="$6"
  local dd="$RUNNER_TEMP/dd-$key"
  local image="$OUT/$key.png"

  rm -rf "$dd"
  (
    cd "$base_dir"
    xcodebuild \
      -project "$project" \
      -scheme "$scheme" \
      -configuration Debug \
      -sdk iphonesimulator \
      -destination "id=$UDID" \
      -derivedDataPath "$dd" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      clean build
  )

  local app="$dd/Build/Products/Debug-iphonesimulator/${product}.app"
  [[ -d "$app" ]] || { echo "ERROR: app not found: $app"; find "$dd/Build/Products" -maxdepth 3 -type d -name '*.app' -print || true; exit 1; }

  xcrun simctl terminate "$UDID" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$app"
  xcrun simctl launch "$UDID" "$bundle"
  sleep 4
  xcrun simctl io "$UDID" screenshot --type=png "$image"
  xcrun simctl terminate "$UDID" "$bundle" >/dev/null 2>&1 || true

  local dims
  dims=$(sips -g pixelWidth -g pixelHeight "$image" 2>/dev/null | awk '/pixelWidth:/{w=$2}/pixelHeight:/{h=$2}END{print w"x"h}')
  case "$dims" in
    2064x2752|2048x2732) ;;
    *)
      echo "ERROR: unexpected iPad screenshot size for $key: $dims"
      exit 1
      ;;
  esac
  echo "CAPTURED=$key:$dims:$image"
}

cd shk
xcodegen generate
cd ..

capture_app 'KamilunavoSHK.xcodeproj' 'KalteCalc' 'KalteCalc' 'de.kamilunav.kaltecalc' 'kaltecalc' 'shk'
capture_app 'KamilunavoSHK.xcodeproj' 'LueftungsCalc' 'LueftungsCalc' 'de.kamilunavo.luftungscalc' 'lueftungscalc' 'shk'
capture_app 'KamilunavoSHK.xcodeproj' 'HeizkoerperCalc' 'HeizkoerperCalc' 'de.kamilunavo.heizkorpercalc' 'heizkoerpercalc' 'shk'
capture_app 'KamilunavoSHK.xcodeproj' 'RohrCalc' 'RohrCalc' 'de.kamilunavo.rohrcalc' 'rohrcalc' 'shk'
capture_app 'KamilunavoSHK.xcodeproj' 'AnlagenCheck' 'AnlagenCheck' 'de.kamilunavo.servicecheck' 'anlagencheck' 'shk'
capture_app 'AnlagenVolumen.xcodeproj' 'VolumeCalc' 'VolumeCalc' 'de.kamilunavo.volumecalc' 'volumecalc' 'volumecalc'

KEY_DIR="$RUNNER_TEMP/ipad-store-key"
mkdir -p "$KEY_DIR"
KEY_PATH="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
printf '%s' "$ASC_PRIVATE_KEY_B64" | tr -d '\r\n ' | base64 --decode > "$KEY_PATH"
chmod 600 "$KEY_PATH"
export ASC_KEY_PATH="$KEY_PATH"

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
  local image="$1"
  local reservation="$2"
  python3 - "$image" "$reservation" <<'PY'
import json, sys, urllib.request
image_path, reservation_path = sys.argv[1], sys.argv[2]
with open(reservation_path, encoding='utf-8') as f: payload=json.load(f)
with open(image_path,'rb') as src:
    for op in payload['data']['attributes']['uploadOperations']:
        src.seek(int(op['offset']))
        data=src.read(int(op['length']))
        headers={h['name']:h['value'] for h in op.get('requestHeaders',[])}
        req=urllib.request.Request(op['url'],data=data,headers=headers,method=op['method'])
        with urllib.request.urlopen(req,timeout=120) as r:
            if not 200 <= r.status < 300:
                raise RuntimeError(r.status)
PY
}

wait_complete(){
  local sid="$1"
  local label="$2"
  local f code state
  for _ in $(seq 1 80); do
    f="$RUNNER_TEMP/ipad-state-$sid.json"
    code=$(raw_get "/v1/appScreenshots/$sid" "$f")
    require_code 200 "$code" "$f" "$label state"
    state=$(jq -r '.data.attributes.assetDeliveryState.state // empty' "$f")
    [[ "$state" == COMPLETE ]] && return 0
    [[ "$state" == FAILED ]] && { jq '.data.attributes.assetDeliveryState' "$f"; exit 1; }
    sleep 3
  done
  echo "ERROR: timeout $label"
  exit 1
}

replace_ipad_app(){
  local key="$1"
  local bundle="$2"
  local image="$3"
  local work="$RUNNER_TEMP/ipad-asc-$key"
  rm -rf "$work" && mkdir -p "$work"

  local f code app_id version_id loc_id set_id body
  f="$work/app.json"; code=$(raw_get "/v1/apps?filter%5BbundleId%5D=$bundle&limit=5" "$f"); require_code 200 "$code" "$f" "$key find app"
  app_id=$(jq -r '.data[0].id // empty' "$f"); [[ -n "$app_id" ]]
  f="$work/ver.json"; code=$(raw_get "/v1/apps/$app_id/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BversionString%5D=1.0&limit=20" "$f"); require_code 200 "$code" "$f" "$key version"
  version_id=$(jq -r '.data[0].id // empty' "$f"); [[ -n "$version_id" ]]
  f="$work/loc.json"; code=$(raw_get "/v1/appStoreVersions/$version_id/appStoreVersionLocalizations?limit=50" "$f"); require_code 200 "$code" "$f" "$key locales"
  loc_id=$(jq -r '.data[] | select(.attributes.locale=="de-DE") | .id' "$f" | head -1); [[ -n "$loc_id" ]]
  f="$work/sets.json"; code=$(raw_get "/v1/appStoreVersionLocalizations/$loc_id/appScreenshotSets?limit=100" "$f"); require_code 200 "$code" "$f" "$key sets"
  set_id=$(jq -r --arg t "$TARGET_TYPE" '.data[] | select(.attributes.screenshotDisplayType==$t) | .id' "$f" | head -1)
  if [[ -z "$set_id" ]]; then
    body=$(jq -nc --arg loc "$loc_id" --arg t "$TARGET_TYPE" '{data:{type:"appScreenshotSets",attributes:{screenshotDisplayType:$t},relationships:{appStoreVersionLocalization:{data:{type:"appStoreVersionLocalizations",id:$loc}}}}}')
    f="$work/create-set.json"; code=$(raw_post '/v1/appScreenshotSets' "$body" "$f"); require_code 201 "$code" "$f" "$key create iPad set"
    set_id=$(jq -r '.data.id' "$f")
  fi

  local base size reservation sid checksum commit
  base="01-${key}-iPad.png"
  size=$(stat -f%z "$image")
  body=$(jq -nc --arg fn "$base" --argjson fs "$size" --arg set "$set_id" '{data:{type:"appScreenshots",attributes:{fileName:$fn,fileSize:$fs},relationships:{appScreenshotSet:{data:{type:"appScreenshotSets",id:$set}}}}}')
  reservation="$work/reserve.json"; code=$(raw_post '/v1/appScreenshots' "$body" "$reservation"); require_code 201 "$code" "$reservation" "$key reserve iPad screenshot"
  sid=$(jq -r '.data.id' "$reservation")
  upload_parts "$image" "$reservation"
  checksum=$(md5 -q "$image")
  body=$(jq -nc --arg id "$sid" --arg md5 "$checksum" '{data:{type:"appScreenshots",id:$id,attributes:{uploaded:true,sourceFileChecksum:$md5}}}')
  commit="$work/commit.json"; code=$(raw_patch "/v1/appScreenshots/$sid" "$body" "$commit"); require_code 200 "$code" "$commit" "$key commit iPad screenshot"
  wait_complete "$sid" "$key/$base"

  f="$work/sets-after.json"; code=$(raw_get "/v1/appStoreVersionLocalizations/$loc_id/appScreenshotSets?limit=100" "$f"); require_code 200 "$code" "$f" "$key sets after upload"
  while IFS=$'\t' read -r ipad_set ipad_type; do
    [[ -n "$ipad_set" ]] || continue
    local sf="$work/set-$ipad_set.json"
    local sc
    sc=$(raw_get "/v1/appScreenshotSets/$ipad_set/appScreenshots?limit=200" "$sf"); require_code 200 "$sc" "$sf" "$key list $ipad_type"
    while read -r old_sid; do
      [[ -n "$old_sid" ]] || continue
      [[ "$old_sid" == "$sid" ]] && continue
      local df="$work/delete-$old_sid.json"
      local dc
      dc=$(raw_delete "/v1/appScreenshots/$old_sid" "$df")
      require_code 204 "$dc" "$df" "$key delete old $ipad_type screenshot"
    done < <(jq -r '.data[]?.id' "$sf")
  done < <(jq -r '.data[] | select(.attributes.screenshotDisplayType | startswith("APP_IPAD")) | [.id,.attributes.screenshotDisplayType] | @tsv' "$f")

  f="$work/final.json"; code=$(raw_get "/v1/appScreenshotSets/$set_id/appScreenshots?limit=200" "$f"); require_code 200 "$code" "$f" "$key final iPad"
  local complete total
  complete=$(jq '[.data[] | select(.attributes.assetDeliveryState.state=="COMPLETE")]|length' "$f")
  total=$(jq '.data|length' "$f")
  [[ "$complete" -eq 1 && "$total" -eq 1 ]] || { echo "ERROR: $key final iPad set total=$total complete=$complete"; exit 1; }
  echo "IPAD_SCREENSHOT_REPLACE_SUCCESS=$key:$TARGET_TYPE:1"
}

replace_ipad_app 'kaltecalc' 'de.kamilunav.kaltecalc' "$OUT/kaltecalc.png"
replace_ipad_app 'lueftungscalc' 'de.kamilunavo.luftungscalc' "$OUT/lueftungscalc.png"
replace_ipad_app 'heizkoerpercalc' 'de.kamilunavo.heizkorpercalc' "$OUT/heizkoerpercalc.png"
replace_ipad_app 'rohrcalc' 'de.kamilunavo.rohrcalc' "$OUT/rohrcalc.png"
replace_ipad_app 'anlagencheck' 'de.kamilunavo.servicecheck' "$OUT/anlagencheck.png"
replace_ipad_app 'volumecalc' 'de.kamilunavo.volumecalc' "$OUT/volumecalc.png"

echo 'IPAD_STORE_SCREENSHOT_REFRESH_SUCCESS=1'
