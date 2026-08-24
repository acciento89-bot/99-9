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

KEY_DIR="$RUNNER_TEMP/shk-build3-review"
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

find_submission_for_version() {
  FOUND_SID=''
  FOUND_SUB_STATE=''
  local list="$RUNNER_TEMP/$key-submissions-all.json" code sid st items ic have
  code=$(raw_get "/v1/apps/$app_id/reviewSubmissions?limit=50" "$list")
  require_code 200 "$code" "$list" "$name: list review submissions"
  while IFS=$'\t' read -r sid st; do
    [[ -n "$sid" ]] || continue
    items="$RUNNER_TEMP/$key-submission-$sid-items.json"
    ic=$(raw_get "/v1/reviewSubmissions/$sid/items?limit=200" "$items")
    [[ "$ic" == '200' ]] || continue
    have=$(jq -r --arg vid "$version_id" '[.data[]? | select(.relationships.appStoreVersion.data.id==$vid)] | length' "$items")
    if [[ "$have" -ge 1 ]]; then
      case "$st" in
        COMPLETE|CANCELED) ;;
        *) FOUND_SID="$sid"; FOUND_SUB_STATE="$st"; return 0 ;;
      esac
    fi
  done < <(jq -r '.data[]? | [.id,.attributes.state] | @tsv' "$list")
}

read_version_state() {
  local out="$1" code
  code=$(raw_get "/v1/appStoreVersions/$version_id?include=build" "$out")
  require_code 200 "$code" "$out" "$name: read version"
  CURRENT_VSTATE=$(jq -r '.data.attributes.appStoreState // .data.attributes.appVersionState // empty' "$out")
  CURRENT_RELEASE_TYPE=$(jq -r '.data.attributes.releaseType // empty' "$out")
  CURRENT_BUILD_ID=$(jq -r '.included[]? | select(.type=="builds") | .id' "$out" | head -1)
  CURRENT_BUILD_NUMBER=$(jq -r '.included[]? | select(.type=="builds") | .attributes.version' "$out" | head -1)
}

for key in kaltecalc lueftungscalc heizkoerpercalc rohrcalc anlagencheck; do
  IFS='|' read -r name bundle <<<"$(app_line "$key")"
  echo
  echo "========== $name: switch review to Build 3 =========="

  f="$RUNNER_TEMP/$key-app.json"
  code=$(raw_get "/v1/apps?filter%5BbundleId%5D=$bundle&limit=10" "$f")
  require_code 200 "$code" "$f" "$name: find app"
  app_id=$(jq -r '.data[0].id // empty' "$f")
  [[ -n "$app_id" ]] || { echo "ERROR: $name app record missing"; exit 1; }

  f="$RUNNER_TEMP/$key-versions.json"
  code=$(raw_get "/v1/apps/$app_id/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BversionString%5D=$VERSION&limit=50" "$f")
  require_code 200 "$code" "$f" "$name: find version"
  version_id=$(jq -r '.data[0].id // empty' "$f")
  [[ -n "$version_id" ]] || { echo "ERROR: $name version $VERSION missing"; exit 1; }

  f="$RUNNER_TEMP/$key-build3.json"
  code=$(raw_get "/v1/builds?filter%5Bapp%5D=$app_id&filter%5Bversion%5D=$TARGET_BUILD&sort=-uploadedDate&limit=10" "$f")
  require_code 200 "$code" "$f" "$name: find Build 3"
  build3_id=$(jq -r '.data[]? | select(.attributes.processingState=="VALID") | .id' "$f" | head -1)
  build3_state=$(jq -r --arg id "$build3_id" '.data[]? | select(.id==$id) | .attributes.processingState' "$f" | head -1)
  [[ -n "$build3_id" && "$build3_state" == 'VALID' ]] || { echo "ERROR: $name Build 3 is not VALID"; exit 1; }
  echo "TARGET_BUILD=3:$build3_id:VALID"

  audit="$RUNNER_TEMP/$key-before.json"
  read_version_state "$audit"
  echo "BEFORE_VERSION_STATE=${CURRENT_VSTATE:-unknown} BEFORE_BUILD=${CURRENT_BUILD_NUMBER:-none} RELEASE_TYPE=${CURRENT_RELEASE_TYPE:-unknown}"

  find_submission_for_version
  if [[ -n "$FOUND_SID" ]]; then
    echo "CURRENT_REVIEW_SUBMISSION=$FOUND_SID:$FOUND_SUB_STATE"
  else
    echo 'CURRENT_REVIEW_SUBMISSION=NONE_ACTIVE'
  fi

  # If Build 3 is already attached and already submitted, do not disturb the review.
  if [[ "$CURRENT_BUILD_ID" == "$build3_id" && "$CURRENT_BUILD_NUMBER" == '3' && "$CURRENT_VSTATE" != 'PREPARE_FOR_SUBMISSION' && "$CURRENT_VSTATE" != 'READY_FOR_REVIEW' ]]; then
    [[ "$CURRENT_RELEASE_TYPE" == 'AFTER_APPROVAL' ]] || { echo "ERROR: $name is already submitted with Build 3 but releaseType=$CURRENT_RELEASE_TYPE"; exit 1; }
    [[ -n "$FOUND_SID" ]] || { echo "ERROR: $name looks submitted with Build 3 but no active review submission was found"; exit 1; }
    echo "APP_BUILD3_REVIEW_RESULT=$key:ALREADY_SUBMITTED_BUILD3:$CURRENT_VSTATE:$FOUND_SUB_STATE"
    continue
  fi

  # A submitted version is locked. Cancel its current review package before changing the build.
  if [[ "$CURRENT_BUILD_ID" != "$build3_id" && "$CURRENT_VSTATE" != 'PREPARE_FOR_SUBMISSION' && "$CURRENT_VSTATE" != 'READY_FOR_REVIEW' ]]; then
    [[ -n "$FOUND_SID" ]] || { echo "ERROR: $name is locked in state $CURRENT_VSTATE but no active review submission was found"; exit 1; }
    body=$(jq -nc --arg id "$FOUND_SID" '{data:{type:"reviewSubmissions",id:$id,attributes:{canceled:true}}}')
    f="$RUNNER_TEMP/$key-cancel.json"
    code=$(raw_patch "/v1/reviewSubmissions/$FOUND_SID" "$body" "$f")
    require_code 200 "$code" "$f" "$name: cancel current review submission"
    echo "REVIEW_CANCEL_REQUESTED=$FOUND_SID"

    editable='false'
    for attempt in $(seq 1 36); do
      sleep 5
      f="$RUNNER_TEMP/$key-after-cancel-$attempt.json"
      read_version_state "$f"
      echo "POST_CANCEL_VERSION_STATE=$CURRENT_VSTATE attempt=$attempt"
      if [[ "$CURRENT_VSTATE" == 'PREPARE_FOR_SUBMISSION' || "$CURRENT_VSTATE" == 'READY_FOR_REVIEW' ]]; then
        editable='true'
        break
      fi
    done
    [[ "$editable" == 'true' ]] || { echo "ERROR: $name did not become editable after review cancellation"; exit 1; }
  fi

  # Keep automatic release after approval and attach the exact VALID Build 3.
  if [[ "$CURRENT_RELEASE_TYPE" != 'AFTER_APPROVAL' ]]; then
    body=$(jq -nc --arg id "$version_id" '{data:{type:"appStoreVersions",id:$id,attributes:{releaseType:"AFTER_APPROVAL"}}}')
    f="$RUNNER_TEMP/$key-release-type.json"
    code=$(raw_patch "/v1/appStoreVersions/$version_id" "$body" "$f")
    require_code 200 "$code" "$f" "$name: set automatic release after approval"
  fi

  if [[ "$CURRENT_BUILD_ID" != "$build3_id" ]]; then
    body=$(jq -nc --arg id "$build3_id" '{data:{type:"builds",id:$id}}')
    f="$RUNNER_TEMP/$key-attach-build3.json"
    code=$(raw_patch "/v1/appStoreVersions/$version_id/relationships/build" "$body" "$f")
    if [[ "$code" != '204' && "$code" != '200' ]]; then
      echo "ERROR: $name attach Build 3 failed: HTTP $code"
      jq '.' "$f" 2>/dev/null || cat "$f" || true
      exit 1
    fi
  fi

  f="$RUNNER_TEMP/$key-after-attach.json"
  read_version_state "$f"
  [[ "$CURRENT_BUILD_ID" == "$build3_id" && "$CURRENT_BUILD_NUMBER" == '3' ]] || {
    echo "ERROR: $name version does not point to Build 3 after update (id=$CURRENT_BUILD_ID build=$CURRENT_BUILD_NUMBER)"
    exit 1
  }
  [[ "$CURRENT_RELEASE_TYPE" == 'AFTER_APPROVAL' ]] || { echo "ERROR: $name release type not AFTER_APPROVAL"; exit 1; }
  echo "BUILD3_ATTACHED=YES VERSION_STATE=$CURRENT_VSTATE RELEASE_TYPE=$CURRENT_RELEASE_TYPE"

  # Reuse or create a READY_FOR_REVIEW package.
  f="$RUNNER_TEMP/$key-ready-submissions.json"
  code=$(raw_get "/v1/apps/$app_id/reviewSubmissions?filter%5Bstate%5D=READY_FOR_REVIEW&limit=50" "$f")
  require_code 200 "$code" "$f" "$name: list ready review submissions"
  sid=$(jq -r '.data[0].id // empty' "$f")
  if [[ -z "$sid" ]]; then
    body=$(jq -nc --arg app "$app_id" '{data:{type:"reviewSubmissions",relationships:{app:{data:{type:"apps",id:$app}}}}}')
    f="$RUNNER_TEMP/$key-create-submission.json"
    code=$(raw_post '/v1/reviewSubmissions' "$body" "$f")
    require_code 201 "$code" "$f" "$name: create review submission"
    sid=$(jq -r '.data.id' "$f")
  fi

  f="$RUNNER_TEMP/$key-ready-items.json"
  code=$(raw_get "/v1/reviewSubmissions/$sid/items?limit=200" "$f")
  require_code 200 "$code" "$f" "$name: list ready submission items"
  have=$(jq -r --arg vid "$version_id" '[.data[]? | select(.relationships.appStoreVersion.data.id==$vid)] | length' "$f")
  if [[ "$have" -eq 0 ]]; then
    body=$(jq -nc --arg sid "$sid" --arg vid "$version_id" '{data:{type:"reviewSubmissionItems",relationships:{reviewSubmission:{data:{type:"reviewSubmissions",id:$sid}},appStoreVersion:{data:{type:"appStoreVersions",id:$vid}}}}}')
    f="$RUNNER_TEMP/$key-add-item.json"
    code=$(raw_post '/v1/reviewSubmissionItems' "$body" "$f")
    require_code 201 "$code" "$f" "$name: add version to review package"
  fi

  body=$(jq -nc --arg id "$sid" '{data:{type:"reviewSubmissions",id:$id,attributes:{submitted:true}}}')
  f="$RUNNER_TEMP/$key-resubmit.json"
  code=$(raw_patch "/v1/reviewSubmissions/$sid" "$body" "$f")
  require_code 200 "$code" "$f" "$name: resubmit Build 3"

  submitted='false'
  final_sub_state=''
  for attempt in $(seq 1 24); do
    sleep 5
    f="$RUNNER_TEMP/$key-submission-poll-$attempt.json"
    code=$(raw_get "/v1/reviewSubmissions/$sid" "$f")
    require_code 200 "$code" "$f" "$name: poll resubmission"
    final_sub_state=$(jq -r '.data.attributes.state // empty' "$f")
    echo "RESUBMISSION_STATE=$final_sub_state attempt=$attempt"
    if [[ -n "$final_sub_state" && "$final_sub_state" != 'READY_FOR_REVIEW' ]]; then
      submitted='true'
      break
    fi
  done
  [[ "$submitted" == 'true' ]] || { echo "ERROR: $name review submission stayed READY_FOR_REVIEW"; exit 1; }

  f="$RUNNER_TEMP/$key-final-version.json"
  read_version_state "$f"
  [[ "$CURRENT_BUILD_ID" == "$build3_id" && "$CURRENT_BUILD_NUMBER" == '3' ]] || { echo "ERROR: $name final build is not 3"; exit 1; }
  [[ "$CURRENT_RELEASE_TYPE" == 'AFTER_APPROVAL' ]] || { echo "ERROR: $name final release type changed"; exit 1; }
  echo "APP_BUILD3_REVIEW_RESULT=$key:SUBMITTED_BUILD3:$CURRENT_VSTATE:$final_sub_state"
done

echo
echo 'SHK_BUILD3_REVIEW_REPLACEMENT_SUCCESS=1'
