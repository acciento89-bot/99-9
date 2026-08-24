#!/usr/bin/env bash
set -euo pipefail

API='https://api.appstoreconnect.apple.com'
META='shk/release/store_metadata.json'

: "${ASC_ISSUER_ID:?missing ASC_ISSUER_ID}"
: "${ASC_KEY_ID:?missing ASC_KEY_ID}"
: "${ASC_PRIVATE_KEY_B64:?missing ASC_PRIVATE_KEY_B64}"

test -s "$META"

KEY_DIR="$RUNNER_TEMP/shk-asc-finalize"
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
require_code() {
  local expected="$1" actual="$2" file="$3" label="$4"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: $label failed: HTTP $actual"
    jq '.' "$file" 2>/dev/null || cat "$file" || true
    exit 1
  fi
}

VERSION_STRING=$(jq -r '.version' "$META")
BUILD_NUMBER=$(jq -r '.build' "$META")
COPYRIGHT=$(jq -r '.copyright' "$META")
PRIMARY_CATEGORY=$(jq -r '.primary_category' "$META")
SECONDARY_CATEGORY=$(jq -r '.secondary_category' "$META")
PRIVACY_URL=$(jq -r '.privacy_url' "$META")
SUPPORT_URL=$(jq -r '.support_url' "$META")
MARKETING_URL=$(jq -r '.marketing_url' "$META")
EULA_URL=$(jq -r '.standard_eula_url' "$META")
RELEASE_TYPE=$(jq -r '.release_type' "$META")

[[ "$VERSION_STRING" == '1.0' ]]
[[ "$BUILD_NUMBER" == '2' ]]
[[ "$RELEASE_TYPE" == 'AFTER_APPROVAL' ]]

# Reuse a known-good App Review contact from an existing app without printing it.
CONTACT=''
VOLUMECALC_VERSION='ca53ae3a-fb00-4a93-9203-b69b2c6845d5'
CF="$RUNNER_TEMP/review-contact.json"
CC=$(raw_get "/v1/appStoreVersions/$VOLUMECALC_VERSION/appStoreReviewDetail" "$CF")
if [[ "$CC" == '200' ]]; then
  F=$(jq -r '.data.attributes.contactFirstName // empty' "$CF")
  L=$(jq -r '.data.attributes.contactLastName // empty' "$CF")
  P=$(jq -r '.data.attributes.contactPhone // empty' "$CF")
  E=$(jq -r '.data.attributes.contactEmail // empty' "$CF")
  if [[ -n "$F" && -n "$L" && -n "$P" && -n "$E" ]]; then
    CONTACT=$(jq -nc --arg f "$F" --arg l "$L" --arg p "$P" --arg e "$E" '{first:$f,last:$l,phone:$p,email:$e}')
  fi
fi
if [[ -z "$CONTACT" ]]; then
  AF="$RUNNER_TEMP/all-apps.json"
  AC=$(raw_get '/v1/apps?limit=200' "$AF")
  require_code 200 "$AC" "$AF" 'List apps for review contact'
  while read -r aid; do
    VF="$RUNNER_TEMP/contact-versions-$aid.json"
    VC=$(raw_get "/v1/apps/$aid/appStoreVersions?filter%5Bplatform%5D=IOS&limit=20" "$VF")
    [[ "$VC" == '200' ]] || continue
    while read -r vid; do
      RF="$RUNNER_TEMP/contact-review-$vid.json"
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
  done < <(jq -r '.data[]?.id' "$AF")
fi
[[ -n "$CONTACT" ]] || { echo 'ERROR: no reusable App Review contact found'; exit 1; }

CONTACT_FIRST=$(jq -r '.first' <<<"$CONTACT")
CONTACT_LAST=$(jq -r '.last' <<<"$CONTACT")
CONTACT_PHONE=$(jq -r '.phone' <<<"$CONTACT")
CONTACT_EMAIL=$(jq -r '.email' <<<"$CONTACT")

echo "SHK_FINALIZER_VERSION=$VERSION_STRING BUILD=$BUILD_NUMBER RELEASE=$RELEASE_TYPE"
echo 'APP_REVIEW_CONTACT=FOUND'

finalize_app() {
  local key="$1"
  local entry name bundle price de_sub de_desc de_keys de_promo en_sub en_desc en_keys en_promo review_notes
  entry=$(jq -cer --arg key "$key" '.apps[] | select(.key==$key)' "$META")
  name=$(jq -r '.name' <<<"$entry")
  bundle=$(jq -r '.bundle_id' <<<"$entry")
  price=$(jq -r '.price_eur' <<<"$entry")
  de_sub=$(jq -r '.de.subtitle' <<<"$entry")
  de_desc=$(jq -r '.de.description' <<<"$entry")
  de_keys=$(jq -r '.de.keywords' <<<"$entry")
  de_promo=$(jq -r '.de.promotional_text' <<<"$entry")
  en_sub=$(jq -r '.en.subtitle' <<<"$entry")
  en_desc=$(jq -r '.en.description' <<<"$entry")
  en_keys=$(jq -r '.en.keywords' <<<"$entry")
  en_promo=$(jq -r '.en.promotional_text' <<<"$entry")
  review_notes=$(jq -r '.review_notes' <<<"$entry")

  # Apple's subtitle limit is 30 characters. Keep this English localization compliant.
  if [[ "$key" == 'heizkoerpercalc' ]]; then en_sub='Radiator output calculator'; fi

  echo
  echo "========== $name / $bundle =========="

  local f code app_id app_info_id
  f="$RUNNER_TEMP/$key-app.json"
  code=$(raw_get "/v1/apps?filter%5BbundleId%5D=$bundle&limit=10" "$f")
  require_code 200 "$code" "$f" "$name: find app"
  app_id=$(jq -r '.data[0].id // empty' "$f")
  [[ -n "$app_id" ]] || { echo "ERROR: $name App Store record not found"; exit 1; }
  echo "APP_ID=$app_id"

  f="$RUNNER_TEMP/$key-appinfos.json"
  code=$(raw_get "/v1/apps/$app_id/appInfos?limit=50" "$f")
  require_code 200 "$code" "$f" "$name: app infos"
  app_info_id=$(jq -r '.data[0].id // empty' "$f")
  [[ -n "$app_info_id" ]]

  local cat_body
  cat_body=$(jq -nc --arg id "$app_info_id" --arg p "$PRIMARY_CATEGORY" --arg s "$SECONDARY_CATEGORY" '{data:{type:"appInfos",id:$id,relationships:{primaryCategory:{data:{type:"appCategories",id:$p}},secondaryCategory:{data:{type:"appCategories",id:$s}}}}}')
  f="$RUNNER_TEMP/$key-categories.json"
  code=$(raw_patch "/v1/appInfos/$app_info_id" "$cat_body" "$f")
  require_code 200 "$code" "$f" "$name: categories"
  echo "CATEGORY_RESULT=$PRIMARY_CATEGORY+$SECONDARY_CATEGORY"

  # App-info localizations (name, subtitle, privacy URL)
  f="$RUNNER_TEMP/$key-info-locs.json"
  code=$(raw_get "/v1/appInfos/$app_info_id/appInfoLocalizations?limit=50" "$f")
  require_code 200 "$code" "$f" "$name: info localizations"
  local info_locs="$f"
  for locale in de-DE en-US; do
    local subtitle loc_id attrs body out c
    if [[ "$locale" == 'de-DE' ]]; then subtitle="$de_sub"; else subtitle="$en_sub"; fi
    loc_id=$(jq -r --arg loc "$locale" '.data[] | select(.attributes.locale==$loc) | .id' "$info_locs" | head -1)
    attrs=$(jq -nc --arg n "$name" --arg st "$subtitle" --arg pu "$PRIVACY_URL" '{name:$n,subtitle:$st,privacyPolicyUrl:$pu}')
    out="$RUNNER_TEMP/$key-info-$locale.json"
    if [[ -n "$loc_id" ]]; then
      body=$(jq -nc --arg id "$loc_id" --argjson a "$attrs" '{data:{type:"appInfoLocalizations",id:$id,attributes:$a}}')
      c=$(raw_patch "/v1/appInfoLocalizations/$loc_id" "$body" "$out")
      require_code 200 "$c" "$out" "$name: update app info $locale"
    else
      body=$(jq -nc --arg loc "$locale" --arg info "$app_info_id" --argjson a "$attrs" '{data:{type:"appInfoLocalizations",attributes:($a+{locale:$loc}),relationships:{appInfo:{data:{type:"appInfos",id:$info}}}}}')
      c=$(raw_post '/v1/appInfoLocalizations' "$body" "$out")
      require_code 201 "$c" "$out" "$name: create app info $locale"
    fi
  done
  echo 'APP_INFO_LOCALIZATIONS=DE+EN'

  # Version 1.0; automatic release immediately after approval.
  local version_id versions body
  f="$RUNNER_TEMP/$key-versions.json"
  code=$(raw_get "/v1/apps/$app_id/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BversionString%5D=$VERSION_STRING&limit=50" "$f")
  require_code 200 "$code" "$f" "$name: versions"
  version_id=$(jq -r '.data[0].id // empty' "$f")
  if [[ -z "$version_id" ]]; then
    body=$(jq -nc --arg app "$app_id" --arg ver "$VERSION_STRING" --arg cr "$COPYRIGHT" --arg rt "$RELEASE_TYPE" '{data:{type:"appStoreVersions",attributes:{platform:"IOS",versionString:$ver,copyright:$cr,releaseType:$rt,usesIdfa:false},relationships:{app:{data:{type:"apps",id:$app}}}}}')
    f="$RUNNER_TEMP/$key-version-create.json"
    code=$(raw_post '/v1/appStoreVersions' "$body" "$f")
    require_code 201 "$code" "$f" "$name: create version"
    version_id=$(jq -r '.data.id' "$f")
  else
    body=$(jq -nc --arg id "$version_id" --arg cr "$COPYRIGHT" --arg rt "$RELEASE_TYPE" '{data:{type:"appStoreVersions",id:$id,attributes:{copyright:$cr,releaseType:$rt,usesIdfa:false}}}')
    f="$RUNNER_TEMP/$key-version-update.json"
    code=$(raw_patch "/v1/appStoreVersions/$version_id" "$body" "$f")
    require_code 200 "$code" "$f" "$name: update version"
  fi
  echo "VERSION_ID=$version_id RELEASE_TYPE=$RELEASE_TYPE"

  # Version localizations. Standard Apple EULA link is intentionally the final line.
  f="$RUNNER_TEMP/$key-version-locs.json"
  code=$(raw_get "/v1/appStoreVersions/$version_id/appStoreVersionLocalizations?limit=50" "$f")
  require_code 200 "$code" "$f" "$name: version localizations"
  local version_locs="$f" de_loc_id=''
  for locale in de-DE en-US; do
    local desc keys promo loc_id attrs out c
    if [[ "$locale" == 'de-DE' ]]; then desc="$de_desc"; keys="$de_keys"; promo="$de_promo"; else desc="$en_desc"; keys="$en_keys"; promo="$en_promo"; fi
    desc="${desc}"$'\n\n'"End User License Agreement (EULA): ${EULA_URL}"
    loc_id=$(jq -r --arg loc "$locale" '.data[] | select(.attributes.locale==$loc) | .id' "$version_locs" | head -1)
    attrs=$(jq -nc --arg d "$desc" --arg k "$keys" --arg p "$promo" --arg su "$SUPPORT_URL" --arg mu "$MARKETING_URL" '{description:$d,keywords:$k,promotionalText:$p,supportUrl:$su,marketingUrl:$mu}')
    out="$RUNNER_TEMP/$key-version-$locale.json"
    if [[ -n "$loc_id" ]]; then
      body=$(jq -nc --arg id "$loc_id" --argjson a "$attrs" '{data:{type:"appStoreVersionLocalizations",id:$id,attributes:$a}}')
      c=$(raw_patch "/v1/appStoreVersionLocalizations/$loc_id" "$body" "$out")
      require_code 200 "$c" "$out" "$name: update version localization $locale"
    else
      body=$(jq -nc --arg loc "$locale" --arg ver "$version_id" --argjson a "$attrs" '{data:{type:"appStoreVersionLocalizations",attributes:($a+{locale:$loc}),relationships:{appStoreVersion:{data:{type:"appStoreVersions",id:$ver}}}}}')
      c=$(raw_post '/v1/appStoreVersionLocalizations' "$body" "$out")
      require_code 201 "$c" "$out" "$name: create version localization $locale"
      loc_id=$(jq -r '.data.id' "$out")
    fi
    [[ "$locale" == 'de-DE' ]] && de_loc_id="$loc_id"
  done
  echo 'VERSION_LOCALIZATIONS=DE+EN EULA=STANDARD_APPLE'

  # Exact Build 2 must be processed and attached.
  local build_id state
  f="$RUNNER_TEMP/$key-builds.json"
  code=$(raw_get "/v1/builds?filter%5Bapp%5D=$app_id&filter%5Bversion%5D=$BUILD_NUMBER&sort=-uploadedDate&limit=10" "$f")
  require_code 200 "$code" "$f" "$name: build lookup"
  build_id=$(jq -r '.data[0].id // empty' "$f")
  state=$(jq -r '.data[0].attributes.processingState // empty' "$f")
  [[ -n "$build_id" && "$state" == 'VALID' ]] || { echo "ERROR: $name Build $BUILD_NUMBER is not VALID"; jq '.data[0]' "$f"; exit 1; }
  body=$(jq -nc --arg id "$build_id" '{data:{type:"builds",id:$id}}')
  f="$RUNNER_TEMP/$key-attach.json"
  code=$(raw_patch "/v1/appStoreVersions/$version_id/relationships/build" "$body" "$f")
  [[ "$code" == '204' || "$code" == '200' ]] || require_code 204 "$code" "$f" "$name: attach build"
  echo "BUILD_RESULT=$BUILD_NUMBER:$build_id:VALID"

  # Explicit export-compliance declaration in ASC too; Info.plist already carries the same declaration.
  body=$(jq -nc --arg id "$build_id" '{data:{type:"builds",id:$id,attributes:{usesNonExemptEncryption:false}}}')
  f="$RUNNER_TEMP/$key-compliance.json"
  code=$(raw_patch "/v1/builds/$build_id" "$body" "$f")
  require_code 200 "$code" "$f" "$name: export compliance"
  echo 'EXPORT_COMPLIANCE=NO_NONEXEMPT_ENCRYPTION'

  # Age rating: these offline calculation/documentation tools contain none of the rated content classes.
  f="$RUNNER_TEMP/$key-age-current.json"
  code=$(raw_get "/v1/appInfos/$app_info_id/ageRatingDeclaration" "$f")
  require_code 200 "$code" "$f" "$name: age rating"
  local age_id age_attrs
  age_id=$(jq -r '.data.id' "$f")
  age_attrs=$(jq -nc '{advertising:false,alcoholTobaccoOrDrugUseOrReferences:"NONE",contests:"NONE",gambling:false,gamblingSimulated:"NONE",gunsOrOtherWeapons:"NONE",healthOrWellnessTopics:false,lootBox:false,medicalOrTreatmentInformation:"NONE",messagingAndChat:false,parentalControls:false,profanityOrCrudeHumor:"NONE",ageAssurance:false,sexualContentGraphicAndNudity:"NONE",sexualContentOrNudity:"NONE",socialMedia:false,socialMediaAgeRestricted:false,horrorOrFearThemes:"NONE",matureOrSuggestiveThemes:"NONE",unrestrictedWebAccess:false,userGeneratedContent:false,violenceCartoonOrFantasy:"NONE",violenceRealisticProlongedGraphicOrSadistic:"NONE",violenceRealistic:"NONE"}')
  body=$(jq -nc --arg id "$age_id" --argjson a "$age_attrs" '{data:{type:"ageRatingDeclarations",id:$id,attributes:$a}}')
  f="$RUNNER_TEMP/$key-age-patch.json"
  code=$(raw_patch "/v1/ageRatingDeclarations/$age_id" "$body" "$f")
  require_code 200 "$code" "$f" "$name: set age rating"
  echo 'AGE_RATING=NO_RATED_CONTENT'

  # Review contact and app-specific instructions.
  local review_id rattrs
  f="$RUNNER_TEMP/$key-review-current.json"
  code=$(raw_get "/v1/appStoreVersions/$version_id/appStoreReviewDetail" "$f")
  require_code 200 "$code" "$f" "$name: review detail"
  review_id=$(jq -r '.data.id // empty' "$f")
  rattrs=$(jq -nc --arg f "$CONTACT_FIRST" --arg l "$CONTACT_LAST" --arg p "$CONTACT_PHONE" --arg e "$CONTACT_EMAIL" --arg n "$review_notes" '{contactFirstName:$f,contactLastName:$l,contactPhone:$p,contactEmail:$e,demoAccountRequired:false,notes:$n}')
  if [[ -n "$review_id" ]]; then
    body=$(jq -nc --arg id "$review_id" --argjson a "$rattrs" '{data:{type:"appStoreReviewDetails",id:$id,attributes:$a}}')
    f="$RUNNER_TEMP/$key-review-patch.json"
    code=$(raw_patch "/v1/appStoreReviewDetails/$review_id" "$body" "$f")
    require_code 200 "$code" "$f" "$name: update review detail"
  else
    body=$(jq -nc --arg vid "$version_id" --argjson a "$rattrs" '{data:{type:"appStoreReviewDetails",attributes:$a,relationships:{appStoreVersion:{data:{type:"appStoreVersions",id:$vid}}}}}')
    f="$RUNNER_TEMP/$key-review-create.json"
    code=$(raw_post '/v1/appStoreReviewDetails' "$body" "$f")
    require_code 201 "$code" "$f" "$name: create review detail"
  fi
  echo 'REVIEW_DETAIL=CONTACT+NOTES+NO_DEMO_ACCOUNT'

  # Paid-app price in Germany, with Apple deriving equivalent territory prices.
  f="$RUNNER_TEMP/$key-price-points.json"
  code=$(raw_get "/v1/apps/$app_id/appPricePoints?filter%5Bterritory%5D=DEU&include=territory&limit=200" "$f")
  require_code 200 "$code" "$f" "$name: price points"
  local price_point_id schedule_id price_ok='false'
  price_point_id=$(jq -r --arg p "$price" '.data[] | select(.attributes.customerPrice==$p) | .id' "$f" | head -1)
  [[ -n "$price_point_id" ]] || { echo "ERROR: $name price point $price EUR not found"; exit 1; }

  f="$RUNNER_TEMP/$key-price-schedule.json"
  code=$(raw_get "/v1/apps/$app_id/appPriceSchedule" "$f")
  if [[ "$code" == '200' ]]; then
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

  if [[ "$price_ok" != 'true' ]]; then
    local price_body pf pc
    price_body=$(jq -nc --arg app "$app_id" --arg pp "$price_point_id" '{data:{type:"appPriceSchedules",relationships:{app:{data:{type:"apps",id:$app}},baseTerritory:{data:{type:"territories",id:"DEU"}},manualPrices:{data:[{type:"appPrices",id:"manualPrice-0"}]}}},included:[{type:"appPrices",id:"manualPrice-0",relationships:{appPricePoint:{data:{type:"appPricePoints",id:$pp}}}}]}')
    pf="$RUNNER_TEMP/$key-price-create.json"
    pc=$(raw_post '/v1/appPriceSchedules' "$price_body" "$pf")
    require_code 201 "$pc" "$pf" "$name: set price"
  fi

  f="$RUNNER_TEMP/$key-price-verify-schedule.json"
  code=$(raw_get "/v1/apps/$app_id/appPriceSchedule" "$f")
  require_code 200 "$code" "$f" "$name: verify price schedule"
  schedule_id=$(jq -r '.data.id' "$f")
  local vf vc
  vf="$RUNNER_TEMP/$key-price-verify.json"
  vc=$(raw_get "/v1/appPriceSchedules/$schedule_id/manualPrices?include=appPricePoint,territory&limit=200" "$vf")
  require_code 200 "$vc" "$vf" "$name: verify manual price"
  jq -e --arg pp "$price_point_id" '.data[]? | select(.relationships.appPricePoint.data.id==$pp and .attributes.endDate==null)' "$vf" >/dev/null
  echo "PRICE_RESULT=${price}_EUR_DEU"

  # User said screenshots/manual privacy answers are done. Enforce real screenshot presence before submitting.
  [[ -n "$de_loc_id" ]]
  f="$RUNNER_TEMP/$key-screenshot-sets.json"
  code=$(raw_get "/v1/appStoreVersionLocalizations/$de_loc_id/appScreenshotSets?limit=50" "$f")
  require_code 200 "$code" "$f" "$name: screenshot sets"
  local iphone_complete=0 ipad_complete=0 set_id dtype sf sc count
  while IFS=$'\t' read -r set_id dtype; do
    [[ -z "$set_id" ]] && continue
    sf="$RUNNER_TEMP/$key-shots-$set_id.json"
    sc=$(raw_get "/v1/appScreenshotSets/$set_id/appScreenshots?limit=50" "$sf")
    require_code 200 "$sc" "$sf" "$name: screenshots $dtype"
    count=$(jq '[.data[]? | select(.attributes.assetDeliveryState.state=="COMPLETE")] | length' "$sf")
    if [[ "$dtype" == *IPHONE* ]]; then iphone_complete=$((iphone_complete + count)); fi
    if [[ "$dtype" == *IPAD* ]]; then ipad_complete=$((ipad_complete + count)); fi
  done < <(jq -r '.data[]? | [.id,.attributes.screenshotDisplayType] | @tsv' "$f")
  [[ "$iphone_complete" -ge 1 ]] || { echo "ERROR: $name has no COMPLETE iPhone screenshot"; exit 1; }
  [[ "$ipad_complete" -ge 1 ]] || { echo "ERROR: $name has no COMPLETE iPad screenshot"; exit 1; }
  echo "SCREENSHOTS=IPHONE:$iphone_complete IPAD:$ipad_complete"

  # Final editable-state audit before creating/submitting the review package.
  f="$RUNNER_TEMP/$key-version-before-submit.json"
  code=$(raw_get "/v1/appStoreVersions/$version_id?include=build" "$f")
  require_code 200 "$code" "$f" "$name: final version audit"
  local vstate
  vstate=$(jq -r '.data.attributes.appStoreState // .data.attributes.appVersionState // empty' "$f")
  echo "PRE_SUBMIT_VERSION_STATE=$vstate"
  if [[ "$vstate" != 'PREPARE_FOR_SUBMISSION' && "$vstate" != 'READY_FOR_REVIEW' ]]; then
    echo "ERROR: $name version is not in a submittable state: $vstate"
    exit 1
  fi

  # Find or create a READY_FOR_REVIEW package.
  local sid sub_state
  f="$RUNNER_TEMP/$key-submissions.json"
  code=$(raw_get "/v1/apps/$app_id/reviewSubmissions?filter%5Bstate%5D=READY_FOR_REVIEW&limit=50" "$f")
  require_code 200 "$code" "$f" "$name: list review submissions"
  sid=$(jq -r '.data[0].id // empty' "$f")
  if [[ -z "$sid" ]]; then
    body=$(jq -nc --arg app "$app_id" '{data:{type:"reviewSubmissions",relationships:{app:{data:{type:"apps",id:$app}}}}}')
    f="$RUNNER_TEMP/$key-submission-create.json"
    code=$(raw_post '/v1/reviewSubmissions' "$body" "$f")
    require_code 201 "$code" "$f" "$name: create review submission"
    sid=$(jq -r '.data.id' "$f")
  fi

  # Add this exact App Store version to the package if not already there.
  f="$RUNNER_TEMP/$key-submission-items.json"
  code=$(raw_get "/v1/reviewSubmissions/$sid/items?limit=200" "$f")
  require_code 200 "$code" "$f" "$name: review submission items"
  local have
  have=$(jq -r --arg vid "$version_id" '[.data[]? | select(.relationships.appStoreVersion.data.id==$vid)] | length' "$f")
  if [[ "$have" -eq 0 ]]; then
    body=$(jq -nc --arg sid "$sid" --arg vid "$version_id" '{data:{type:"reviewSubmissionItems",relationships:{reviewSubmission:{data:{type:"reviewSubmissions",id:$sid}},appStoreVersion:{data:{type:"appStoreVersions",id:$vid}}}}}')
    f="$RUNNER_TEMP/$key-submission-item-create.json"
    code=$(raw_post '/v1/reviewSubmissionItems' "$body" "$f")
    require_code 201 "$code" "$f" "$name: add version to review package"
  fi
  echo "REVIEW_PACKAGE=$sid VERSION_ITEM=READY"

  # Explicit user authorization in this conversation: submit for review.
  body=$(jq -nc --arg id "$sid" '{data:{type:"reviewSubmissions",id:$id,attributes:{submitted:true}}}')
  f="$RUNNER_TEMP/$key-submit.json"
  code=$(raw_patch "/v1/reviewSubmissions/$sid" "$body" "$f")
  require_code 200 "$code" "$f" "$name: submit review package"

  for attempt in $(seq 1 20); do
    f="$RUNNER_TEMP/$key-submission-after-$attempt.json"
    code=$(raw_get "/v1/reviewSubmissions/$sid" "$f")
    require_code 200 "$code" "$f" "$name: poll submission"
    sub_state=$(jq -r '.data.attributes.state // empty' "$f")
    echo "SUBMISSION_STATE=$sub_state attempt=$attempt"
    if [[ "$sub_state" != 'READY_FOR_REVIEW' && -n "$sub_state" ]]; then break; fi
    sleep 5
  done
  [[ "$sub_state" != 'READY_FOR_REVIEW' && -n "$sub_state" ]] || { echo "ERROR: $name submission did not leave READY_FOR_REVIEW"; exit 1; }

  f="$RUNNER_TEMP/$key-version-after-submit.json"
  code=$(raw_get "/v1/appStoreVersions/$version_id" "$f")
  require_code 200 "$code" "$f" "$name: read submitted version"
  vstate=$(jq -r '.data.attributes.appStoreState // .data.attributes.appVersionState // empty' "$f")
  echo "FINAL_VERSION_STATE=$vstate"
  echo "FINAL_RELEASE_TYPE=$(jq -r '.data.attributes.releaseType' "$f")"
  echo "APP_FINAL_RESULT=$key:SUBMITTED"
}

for key in kaltecalc lueftungscalc heizkoerpercalc rohrcalc anlagencheck; do
  finalize_app "$key"
done

echo
echo 'SHK_APPSTORE_FINALIZER_SUCCESS=1'
