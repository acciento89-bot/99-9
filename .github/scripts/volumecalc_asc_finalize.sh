#!/usr/bin/env bash
set -euo pipefail

API='https://api.appstoreconnect.apple.com'
APP_ID='6804672773'
APP_INFO_ID='b3ce09f2-a3d4-4681-a5e9-315326a8dc6f'
VERSION_ID='ca53ae3a-fb00-4a93-9203-b69b2c6845d5'
LOC_ID='b236c044-e75f-4581-97e2-d4ae71e5c1a6'
BUILD_ID='0645f390-218a-42a4-a230-8bf3ea2a6978'
PRICE_POINT_ID='eyJzIjoiNjgwNDY3Mjc3MyIsInQiOiJERVUiLCJwIjoiMTAwNjIifQ'

: "${ASC_ISSUER_ID:?missing ASC_ISSUER_ID}"
: "${ASC_KEY_ID:?missing ASC_KEY_ID}"
: "${ASC_PRIVATE_KEY_B64:?missing ASC_PRIVATE_KEY_B64}"

KEY_DIR="$RUNNER_TEMP/volumecalc-asc"
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
p=b(JSON.generate({iss:ENV.fetch('ASC_ISSUER_ID'),iat:now,exp:now+900,aud:'appstoreconnect-v1'}))
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
require_code() {
  local expected="$1" actual="$2" file="$3" label="$4"
  if [[ "$actual" != "$expected" ]]; then
    echo "$label failed: HTTP $actual"
    jq '.' "$file" 2>/dev/null || cat "$file" || true
    exit 1
  fi
}

echo '=== PRICE: 4.99 EUR / Germany ==='
SFILE="$RUNNER_TEMP/volumecalc-schedule.json"
SCODE=$(raw_get "/v1/apps/$APP_ID/appPriceSchedule" "$SFILE")
if [[ "$SCODE" == '404' ]]; then
  BODY=$(jq -nc --arg app "$APP_ID" --arg pp "$PRICE_POINT_ID" '{data:{type:"appPriceSchedules",relationships:{app:{data:{type:"apps",id:$app}},baseTerritory:{data:{type:"territories",id:"DEU"}},manualPrices:{data:[{type:"appPrices",id:"manualPrice-0"}]}}},included:[{type:"appPrices",id:"manualPrice-0",relationships:{appPricePoint:{data:{type:"appPricePoints",id:$pp}}}}]}')
  PFILE="$RUNNER_TEMP/volumecalc-price-create.json"
  PCODE=$(raw_post '/v1/appPriceSchedules' "$BODY" "$PFILE")
  require_code 201 "$PCODE" "$PFILE" 'Create price schedule'
elif [[ "$SCODE" != '200' ]]; then
  require_code 200 "$SCODE" "$SFILE" 'Read price schedule'
fi
MFILE="$RUNNER_TEMP/volumecalc-manual-prices.json"
MCODE=$(raw_get "/v1/appPriceSchedules/$APP_ID/manualPrices?include=appPricePoint,territory&limit=100" "$MFILE")
require_code 200 "$MCODE" "$MFILE" 'Read manual prices'
jq -e --arg pp "$PRICE_POINT_ID" '.data[] | select(.relationships.appPricePoint.data.id==$pp and .attributes.endDate==null)' "$MFILE" >/dev/null
echo 'PRICE_RESULT=VERIFIED_4_99_EUR_DEU'

echo '=== VERSION / BUILD ==='
VFILE="$RUNNER_TEMP/volumecalc-version.json"
VCODE=$(raw_get "/v1/appStoreVersions/$VERSION_ID?include=build" "$VFILE")
require_code 200 "$VCODE" "$VFILE" 'Read App Store version'
jq -e --arg bid "$BUILD_ID" '.included[]? | select(.type=="builds" and .id==$bid and .attributes.version=="2" and .attributes.processingState=="VALID")' "$VFILE" >/dev/null
echo "VERSION_STATE=$(jq -r '.data.attributes.appStoreState' "$VFILE")"
echo 'BUILD_RESULT=BUILD_2_ATTACHED_VALID'

echo '=== EXPORT COMPLIANCE ==='
EBODY=$(jq -nc --arg id "$BUILD_ID" '{data:{type:"builds",id:$id,attributes:{usesNonExemptEncryption:false}}}')
EFILE="$RUNNER_TEMP/volumecalc-build-patch.json"
ECODE=$(raw_patch "/v1/builds/$BUILD_ID" "$EBODY" "$EFILE")
require_code 200 "$ECODE" "$EFILE" 'Set export compliance'
BFILE="$RUNNER_TEMP/volumecalc-build.json"
BCODE=$(raw_get "/v1/builds/$BUILD_ID" "$BFILE")
require_code 200 "$BCODE" "$BFILE" 'Verify build compliance'
[[ "$(jq -r '.data.attributes.usesNonExemptEncryption' "$BFILE")" == 'false' ]]
echo 'EXPORT_RESULT=NO_NONEXEMPT_ENCRYPTION'

echo '=== AGE RATING ==='
AFILE="$RUNNER_TEMP/volumecalc-age-before.json"
ACODE=$(raw_get "/v1/appInfos/$APP_INFO_ID/ageRatingDeclaration" "$AFILE")
require_code 200 "$ACODE" "$AFILE" 'Read age rating declaration'
AGE_ID=$(jq -r '.data.id' "$AFILE")
AATTR=$(jq -nc '{advertising:false,alcoholTobaccoOrDrugUseOrReferences:"NONE",contests:"NONE",gambling:false,gamblingSimulated:"NONE",gunsOrOtherWeapons:"NONE",healthOrWellnessTopics:false,lootBox:false,medicalOrTreatmentInformation:"NONE",messagingAndChat:false,parentalControls:false,profanityOrCrudeHumor:"NONE",ageAssurance:false,sexualContentGraphicAndNudity:"NONE",sexualContentOrNudity:"NONE",socialMedia:false,socialMediaAgeRestricted:false,horrorOrFearThemes:"NONE",matureOrSuggestiveThemes:"NONE",unrestrictedWebAccess:false,userGeneratedContent:false,violenceCartoonOrFantasy:"NONE",violenceRealisticProlongedGraphicOrSadistic:"NONE",violenceRealistic:"NONE"}')
ABODY=$(jq -nc --arg id "$AGE_ID" --argjson a "$AATTR" '{data:{type:"ageRatingDeclarations",id:$id,attributes:$a}}')
APFILE="$RUNNER_TEMP/volumecalc-age-patch.json"
APCODE=$(raw_patch "/v1/ageRatingDeclarations/$AGE_ID" "$ABODY" "$APFILE")
require_code 200 "$APCODE" "$APFILE" 'Set age rating declaration'
ACHECK="$RUNNER_TEMP/volumecalc-age-after.json"
ACCODE=$(raw_get "/v1/appInfos/$APP_INFO_ID/ageRatingDeclaration" "$ACHECK")
require_code 200 "$ACCODE" "$ACHECK" 'Verify age rating declaration'
[[ "$(jq -r '.data.attributes.advertising' "$ACHECK")" == 'false' ]]
[[ "$(jq -r '.data.attributes.gambling' "$ACHECK")" == 'false' ]]
[[ "$(jq -r '.data.attributes.unrestrictedWebAccess' "$ACHECK")" == 'false' ]]
[[ "$(jq -r '.data.attributes.violenceRealistic' "$ACHECK")" == 'NONE' ]]
IFILE="$RUNNER_TEMP/volumecalc-app-info.json"
ICODE=$(raw_get "/v1/appInfos/$APP_INFO_ID" "$IFILE")
require_code 200 "$ICODE" "$IFILE" 'Read calculated age rating'
echo "AGE_RESULT=$(jq -r '.data.attributes.appStoreAgeRating // "CALCULATING"' "$IFILE")"

echo '=== APP REVIEW INFORMATION ==='
RFILE="$RUNNER_TEMP/volumecalc-review-current.json"
RCODE=$(raw_get "/v1/appStoreVersions/$VERSION_ID/appStoreReviewDetail" "$RFILE")
[[ "$RCODE" == '200' ]] || require_code 200 "$RCODE" "$RFILE" 'Read current review detail'
RID=$(jq -r '.data.id // empty' "$RFILE" 2>/dev/null || true)
CONTACT=''
if [[ -n "$RID" ]]; then
  F=$(jq -r '.data.attributes.contactFirstName // empty' "$RFILE")
  L=$(jq -r '.data.attributes.contactLastName // empty' "$RFILE")
  P=$(jq -r '.data.attributes.contactPhone // empty' "$RFILE")
  E=$(jq -r '.data.attributes.contactEmail // empty' "$RFILE")
  if [[ -n "$F" && -n "$L" && -n "$P" && -n "$E" ]]; then
    CONTACT=$(jq -nc --arg f "$F" --arg l "$L" --arg p "$P" --arg e "$E" '{first:$f,last:$l,phone:$p,email:$e}')
  fi
fi
if [[ -z "$CONTACT" ]]; then
  APPS_FILE="$RUNNER_TEMP/volumecalc-apps.json"
  APPS_CODE=$(raw_get '/v1/apps?limit=200' "$APPS_FILE")
  require_code 200 "$APPS_CODE" "$APPS_FILE" 'List apps for review contact'
  while read -r aid; do
    [[ -z "$aid" || "$aid" == "$APP_ID" ]] && continue
    VF="$RUNNER_TEMP/volumecalc-versions-$aid.json"
    VC=$(raw_get "/v1/apps/$aid/appStoreVersions?filter%5Bplatform%5D=IOS&limit=50" "$VF")
    [[ "$VC" == '200' ]] || continue
    while read -r vid; do
      [[ -z "$vid" ]] && continue
      RF="$RUNNER_TEMP/volumecalc-review-$vid.json"
      RC=$(raw_get "/v1/appStoreVersions/$vid/appStoreReviewDetail" "$RF")
      [[ "$RC" == '200' ]] || continue
      F=$(jq -r '.data.attributes.contactFirstName // empty' "$RF" 2>/dev/null || true)
      L=$(jq -r '.data.attributes.contactLastName // empty' "$RF" 2>/dev/null || true)
      P=$(jq -r '.data.attributes.contactPhone // empty' "$RF" 2>/dev/null || true)
      E=$(jq -r '.data.attributes.contactEmail // empty' "$RF" 2>/dev/null || true)
      if [[ -n "$F" && -n "$L" && -n "$P" && -n "$E" ]]; then
        CONTACT=$(jq -nc --arg f "$F" --arg l "$L" --arg p "$P" --arg e "$E" '{first:$f,last:$l,phone:$p,email:$e}')
        break 2
      fi
    done < <(jq -r '.data[]?.id' "$VF")
  done < <(jq -r '.data[]?.id' "$APPS_FILE")
fi
[[ -n "$CONTACT" ]]
F=$(jq -r '.first' <<<"$CONTACT")
L=$(jq -r '.last' <<<"$CONTACT")
P=$(jq -r '.phone' <<<"$CONTACT")
E=$(jq -r '.email' <<<"$CONTACT")
NOTES=$(cat <<'EOF'
VolumeCalc requires no sign-in, account or network connection. All core calculations work offline and projects are stored locally on the device.

Suggested review path:
1. Tap the + button or "Erstes Bauteil hinzufügen".
2. Add a pipe using a preset or a custom inner diameter and length.
3. Add floor, wall or ceiling heating, a panel radiator, or a steel/cast-iron sectional radiator. Manufacturer water content can always be entered directly.
4. Add a buffer/storage tank, heat generator, hydraulic separator, distributor/collector, heat exchanger or any known manual water volume.
5. The main screen shows calculated system volume and a separately configurable planning reserve.
6. Results can be shared through the standard iOS share sheet.

There are no in-app purchases, subscriptions, ads, external payment methods, user accounts or server-backed user content. VolumeCalc is sold as a one-time paid App Store download.
EOF
)
RATTR=$(jq -nc --arg f "$F" --arg l "$L" --arg p "$P" --arg e "$E" --arg n "$NOTES" '{contactFirstName:$f,contactLastName:$l,contactPhone:$p,contactEmail:$e,demoAccountRequired:false,notes:$n}')
if [[ -n "$RID" ]]; then
  RBODY=$(jq -nc --arg id "$RID" --argjson a "$RATTR" '{data:{type:"appStoreReviewDetails",id:$id,attributes:$a}}')
  RPFILE="$RUNNER_TEMP/volumecalc-review-patch.json"
  RPCODE=$(raw_patch "/v1/appStoreReviewDetails/$RID" "$RBODY" "$RPFILE")
  require_code 200 "$RPCODE" "$RPFILE" 'Update review detail'
else
  RBODY=$(jq -nc --arg vid "$VERSION_ID" --argjson a "$RATTR" '{data:{type:"appStoreReviewDetails",attributes:$a,relationships:{appStoreVersion:{data:{type:"appStoreVersions",id:$vid}}}}}')
  RPFILE="$RUNNER_TEMP/volumecalc-review-create.json"
  RPCODE=$(raw_post '/v1/appStoreReviewDetails' "$RBODY" "$RPFILE")
  require_code 201 "$RPCODE" "$RPFILE" 'Create review detail'
fi
RCHECK="$RUNNER_TEMP/volumecalc-review-check.json"
RCCODE=$(raw_get "/v1/appStoreVersions/$VERSION_ID/appStoreReviewDetail" "$RCHECK")
require_code 200 "$RCCODE" "$RCHECK" 'Verify review detail'
[[ -n "$(jq -r '.data.attributes.contactPhone // empty' "$RCHECK")" ]]
[[ "$(jq -r '.data.attributes.demoAccountRequired' "$RCHECK")" == 'false' ]]
[[ -n "$(jq -r '.data.attributes.notes // empty' "$RCHECK")" ]]
echo 'REVIEW_RESULT=CONTACT_AND_NOTES_COMPLETE'

echo '=== SCREENSHOTS ==='
SSFILE="$RUNNER_TEMP/volumecalc-screenshots.json"
SSCODE=$(raw_get "/v1/appStoreVersionLocalizations/$LOC_ID/appScreenshotSets?limit=50" "$SSFILE")
require_code 200 "$SSCODE" "$SSFILE" 'Read screenshot sets'
echo "SCREENSHOT_SET_COUNT=$(jq '.data | length' "$SSFILE")"
jq '[.data[] | {id,displayType:.attributes.screenshotDisplayType}]' "$SSFILE"

echo '=== FINAL ==='
VFINAL="$RUNNER_TEMP/volumecalc-version-final.json"
VFCODE=$(raw_get "/v1/appStoreVersions/$VERSION_ID?include=build" "$VFINAL")
require_code 200 "$VFCODE" "$VFINAL" 'Read final version state'
echo "FINAL_VERSION_STATE=$(jq -r '.data.attributes.appStoreState' "$VFINAL")"
echo 'VOLUMECALC_ASC_FINALIZER_SUCCESS=1'
