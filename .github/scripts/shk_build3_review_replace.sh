#!/usr/bin/env bash
set -euo pipefail

API='https://api.appstoreconnect.apple.com'
REQUEST='bridge/.github/shk-build3-review-request.json'

: "${ASC_ISSUER_ID:?missing ASC_ISSUER_ID}"
: "${ASC_KEY_ID:?missing ASC_KEY_ID}"
: "${ASC_PRIVATE_KEY_B64:?missing ASC_PRIVATE_KEY_B64}"
test -s "$REQUEST"

jq -e '.repository == "acciento89-bot/SHK"' "$REQUEST" >/dev/null
jq -e '.version == "1.0" and .replace_with_build == "3"' "$REQUEST" >/dev/null
jq -e '.resubmit == true and .release_after_approval == true' "$REQUEST" >/dev/null
jq -e '.apps | sort == ["anlagencheck","heizkoerpercalc","kaltecalc","lueftungscalc","rohrcalc"]' "$REQUEST" >/dev/null

KEY_DIR="$RUNNER_TEMP/shk-build3-review-v2"
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

VERSION='1.0'
TARGET_BUILD='3'

app_line() {
  case "$1" in
    kaltecalc) echo 'KälteCalc|de.kamilunav.kaltecalc' ;;
    lueftungscalc) echo 'LüftungsCalc|de.kamilunavo.luftungscalc' ;;
    heizkoerpercalc) echo 'HeizkörperCalc|de.kamilunavo.heizkorpercalc' ;;
    rohrcalc) echo 'RohrCalc|de.kamilunavo.rohrcalc' ;;
    anlagencheck) echo 'AnlagenCheck|de.kamilunavo.servicecheck' ;;
    *) echo "unsupported app key: $1" >&2; exit 2 ;;
  esac
}

read_version() {
  local out="$1" code
  code=$(raw_get "/v1/appStoreVersions/$version_id?include=build" "$out")
  require_code 200 "$code" "$out" "$name: read version"
  CURRENT_VSTATE=$(jq -r '.data.attributes.appStoreState // .data.attributes.appVersionState // empty' "$out")
  CURRENT_RELEASE_TYPE=$(jq -r '.data.attributes.releaseType // empty' "$out")
  CURRENT_BUILD_ID=$(jq -r '.included[]? | select(.type=="builds") | .id' "$out" | head -1)
  CURRENT_BUILD_NUMBER=$(jq -r '.included[]? | select(.type=="builds") | .attributes.version' "$out" | head -1)
}

find_active_submission() {
  FOUND_SID=''
  FOUND_SUB_STATE=''
  local out="$RUNNER_TEMP/$key-active-submissions.json" code count
  code=$(raw_get "/v1/apps/$app_id/reviewSubmissions?include=appStoreVersionForReview&limit=50" "$out")
  require_code 200 "$code" "$out" "$name: list review submissions"

  FOUND_SID=$(jq -r --arg vid "$version_id" '
    [.data[]? |
      select(.attributes.state=="WAITING_FOR_REVIEW" or .attributes.state=="IN_REVIEW" or .attributes.state=="UNRESOLVED_ISSUES" or .attributes.state=="CANCELING") |
      select(.relationships.appStoreVersionForReview.data.id==$vid)] | .[0].id // empty' "$out")

  if [[ -z "$FOUND_SID" ]]; then
    count=$(jq '[.data[]? | select(.attributes.state=="WAITING_FOR_REVIEW" or .attributes.state=="IN_REVIEW" or .attributes.state=="UNRESOLVED_ISSUES" or .attributes.state=="CANCELING")] | length' "$out")
    if [[ "$count" -eq 1 ]]; then
      FOUND_SID=$(jq -r '.data[]? | select(.attributes.state=="WAITING_FOR_REVIEW" or .attributes.state=="IN_REVIEW" or .attributes.state=="UNRESOLVED_ISSUES" or .attributes.state=="CANCELING") | .id' "$out" | head -1)
    fi
  fi

  if [[ -n "$FOUND_SID" ]]; then
    FOUND_SUB_STATE=$(jq -r --arg id "$FOUND_SID" '.data[]? | select(.id==$id) | .attributes.state' "$out" | head -1)
  fi
}

for key in kaltecalc lueftungscalc heizkoerpercalc rohrcalc anlagencheck; do
  IFS='|' read -r name bundle <<<"$(app_line "$key")"
  echo
  echo "========== $name: Build 3 review replacement v2 =========="

  f="$RUNNER_TEMP/$key-app.json"
  code=$(raw_get "/v1/apps?filter%5BbundleId%5D=$bundle&limit=10" "$f")
  require_code 200 "$code" "$f" "$name: find app"
  app_id=$(jq -r '.data[0].id // empty' "$f")
  [[ -n "$app_id" ]] || { echo "ERROR: $name app record missing"; exit 1; }

  f="$RUNNER_TEMP/$key-version-list.json"
  code=$(raw_get "/v1/apps/$app_id/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BversionString%5D=$VERSION&limit=50" "$f")
  require_code 200 "$code" "$f" "$name: find version"
  version_id=$(jq -r '.data[0].id // empty' "$f")
  [[ -n "$version_id" ]] || { echo "ERROR: $name version $VERSION missing"; exit 1; }

  f="$RUNNER_TEMP/$key-build3.json"
  code=$(raw_get "/v1/builds?filter%5Bapp%5D=$app_id&filter%5Bversion%5D=$TARGET_BUILD&sort=-uploadedDate&limit=10" "$f")
  require_code 200 "$code" "$f" "$name: find Build 3"
  build3_id=$(jq -r '.data[]? | select(.attributes.processingState=="VALID") | .id' "$f" | head -1)
  [[ -n "$build3_id" ]] || { echo "ERROR: $name Build 3 not VALID"; exit 1; }
  echo "TARGET_BUILD=3:$build3_id:VALID"

  read_version "$RUNNER_TEMP/$key-before.json"
  echo "BEFORE_STATE=$CURRENT_VSTATE BEFORE_BUILD=${CURRENT_BUILD_NUMBER:-none} RELEASE_TYPE=$CURRENT_RELEASE_TYPE"

  find_active_submission
  echo "ACTIVE_SUBMISSION=${FOUND_SID:-none}:${FOUND_SUB_STATE:-none}"

  if [[ "$CURRENT_BUILD_ID" == "$build3_id" && "$CURRENT_BUILD_NUMBER" == '3' && ( "$CURRENT_VSTATE" == 'WAITING_FOR_REVIEW' || "$CURRENT_VSTATE" == 'IN_REVIEW' ) ]]; then
    echo "APP_BUILD3_REVIEW_RESULT=$key:ALREADY_OK:$CURRENT_VSTATE"
    continue
  fi

  if [[ "$CURRENT_BUILD_ID" != "$build3_id" && ( "$CURRENT_VSTATE" == 'WAITING_FOR_REVIEW' || "$CURRENT_VSTATE" == 'IN_REVIEW' || "$CURRENT_VSTATE" == 'WAITING_FOR_EXPORT_COMPLIANCE' ) ]]; then
    [[ -n "$FOUND_SID" ]] || { echo "ERROR: $name active review submission not found"; exit 1; }
    body=$(jq -nc --arg id "$FOUND_SID" '{data:{type:"reviewSubmissions",id:$id,attributes:{canceled:true}}}')
    f="$RUNNER_TEMP/$key-cancel.json"
    code=$(raw_patch "/v1/reviewSubmissions/$FOUND_SID" "$body" "$f")
    require_code 200 "$code" "$f" "$name: cancel review submission"
    echo "CANCEL_REQUESTED=$FOUND_SID"

    editable='false'
    for attempt in $(seq 1 48); do
      sleep 5
      read_version "$RUNNER_TEMP/$key-after-cancel-$attempt.json"
      echo "POST_CANCEL_STATE=$CURRENT_VSTATE attempt=$attempt"
      case "$CURRENT_VSTATE" in
        DEVELOPER_REJECTED|PREPARE_FOR_SUBMISSION|READY_FOR_REVIEW)
          editable='true'; break ;;
      esac
    done
    [[ "$editable" == 'true' ]] || { echo "ERROR: $name did not become editable after cancellation"; exit 1; }
  fi

  if [[ "$CURRENT_RELEASE_TYPE" != 'AFTER_APPROVAL' ]]; then
    body=$(jq -nc --arg id "$version_id" '{data:{type:"appStoreVersions",id:$id,attributes:{releaseType:"AFTER_APPROVAL"}}}')
    f="$RUNNER_TEMP/$key-release.json"
    code=$(raw_patch "/v1/appStoreVersions/$version_id" "$body" "$f")
    require_code 200 "$code" "$f" "$name: set release type"
  fi

  if [[ "$CURRENT_BUILD_ID" != "$build3_id" ]]; then
    body=$(jq -nc --arg id "$build3_id" '{data:{type:"builds",id:$id}}')
    f="$RUNNER_TEMP/$key-attach.json"
    code=$(raw_patch "/v1/appStoreVersions/$version_id/relationships/build" "$body" "$f")
    if [[ "$code" != '204' && "$code" != '200' ]]; then
      echo "ERROR: $name attach Build 3 failed HTTP $code"
      jq '.' "$f" 2>/dev/null || cat "$f" || true
      exit 1
    fi
  fi

  read_version "$RUNNER_TEMP/$key-after-attach.json"
  [[ "$CURRENT_BUILD_ID" == "$build3_id" && "$CURRENT_BUILD_NUMBER" == '3' ]] || { echo "ERROR: $name Build 3 was not attached"; exit 1; }
  [[ "$CURRENT_RELEASE_TYPE" == 'AFTER_APPROVAL' ]] || { echo "ERROR: $name release type is $CURRENT_RELEASE_TYPE"; exit 1; }
  echo "BUILD3_ATTACHED=YES STATE=$CURRENT_VSTATE"

  # Create/reuse a READY_FOR_REVIEW review package, add the exact version, then submit it.
  f="$RUNNER_TEMP/$key-ready.json"
  code=$(raw_get "/v1/apps/$app_id/reviewSubmissions?filter%5Bstate%5D=READY_FOR_REVIEW&limit=50" "$f")
  require_code 200 "$code" "$f" "$name: list ready submissions"
  sid=$(jq -r '.data[0].id // empty' "$f")
  if [[ -z "$sid" ]]; then
    body=$(jq -nc --arg app "$app_id" '{data:{type:"reviewSubmissions",relationships:{app:{data:{type:"apps",id:$app}}}}}')
    f="$RUNNER_TEMP/$key-create.json"
    code=$(raw_post '/v1/reviewSubmissions' "$body" "$f")
    require_code 201 "$code" "$f" "$name: create review submission"
    sid=$(jq -r '.data.id' "$f")
  fi

  f="$RUNNER_TEMP/$key-items.json"
  code=$(raw_get "/v1/reviewSubmissions/$sid/items?limit=200" "$f")
  require_code 200 "$code" "$f" "$name: list review items"
  have=$(jq -r --arg vid "$version_id" '[.data[]? | select(.relationships.appStoreVersion.data.id==$vid)] | length' "$f")
  if [[ "$have" -eq 0 ]]; then
    body=$(jq -nc --arg sid "$sid" --arg vid "$version_id" '{data:{type:"reviewSubmissionItems",relationships:{reviewSubmission:{data:{type:"reviewSubmissions",id:$sid}},appStoreVersion:{data:{type:"appStoreVersions",id:$vid}}}}}')
    f="$RUNNER_TEMP/$key-add-item.json"
    code=$(raw_post '/v1/reviewSubmissionItems' "$body" "$f")
    require_code 201 "$code" "$f" "$name: add version to review submission"
  fi

  body=$(jq -nc --arg id "$sid" '{data:{type:"reviewSubmissions",id:$id,attributes:{submitted:true}}}')
  f="$RUNNER_TEMP/$key-submit.json"
  code=$(raw_patch "/v1/reviewSubmissions/$sid" "$body" "$f")
  require_code 200 "$code" "$f" "$name: submit Build 3 review"

  submitted='false'
  for attempt in $(seq 1 36); do
    sleep 5
    read_version "$RUNNER_TEMP/$key-final-$attempt.json"
    echo "FINAL_STATE=$CURRENT_VSTATE FINAL_BUILD=$CURRENT_BUILD_NUMBER attempt=$attempt"
    if [[ "$CURRENT_BUILD_NUMBER" == '3' && ( "$CURRENT_VSTATE" == 'WAITING_FOR_REVIEW' || "$CURRENT_VSTATE" == 'IN_REVIEW' ) ]]; then
      submitted='true'; break
    fi
  done
  [[ "$submitted" == 'true' ]] || { echo "ERROR: $name did not return to review with Build 3"; exit 1; }
  echo "APP_BUILD3_REVIEW_RESULT=$key:BUILD3:$CURRENT_VSTATE"
done

echo 'SHK_BUILD3_REVIEW_REPLACEMENT_SUCCESS=1'
