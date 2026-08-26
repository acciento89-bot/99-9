#!/usr/bin/env bash
set -euo pipefail

API='https://api.appstoreconnect.apple.com'
REQUEST='bridge/.github/volumecalc-build3-review-request.json'
BUNDLE='de.kamilunavo.volumecalc'
NAME='VolumeCalc'
VERSION='1.0'
TARGET_BUILD='3'

: "${ASC_ISSUER_ID:?missing ASC_ISSUER_ID}"
: "${ASC_KEY_ID:?missing ASC_KEY_ID}"
: "${ASC_PRIVATE_KEY_B64:?missing ASC_PRIVATE_KEY_B64}"
test -s "$REQUEST"
jq -e '.repository == "acciento89-bot/AnlagenVolumen"' "$REQUEST" >/dev/null
jq -e '.version == "1.0" and .replace_with_build == "3" and .resubmit == true' "$REQUEST" >/dev/null

KEY_DIR="$RUNNER_TEMP/volumecalc-build3-review"
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

raw_get() { local path="$1" out="$2"; /usr/bin/curl --globoff --silent --show-error --output "$out" --write-out '%{http_code}' -H "Authorization: Bearer $TOKEN" "$API$path"; }
raw_post() { local path="$1" body="$2" out="$3"; /usr/bin/curl --globoff --silent --show-error --output "$out" --write-out '%{http_code}' -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$body" "$API$path"; }
raw_patch() { local path="$1" body="$2" out="$3"; /usr/bin/curl --globoff --silent --show-error --output "$out" --write-out '%{http_code}' -X PATCH -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$body" "$API$path"; }
require_code() { local expected="$1" actual="$2" file="$3" label="$4"; [[ "$actual" == "$expected" ]] || { echo "ERROR: $label failed: HTTP $actual"; jq '.' "$file" 2>/dev/null || cat "$file" || true; exit 1; }; }

read_version() {
  local out="$1" code
  code=$(raw_get "/v1/appStoreVersions/$version_id?include=build" "$out")
  require_code 200 "$code" "$out" "$NAME: read version"
  CURRENT_VSTATE=$(jq -r '.data.attributes.appStoreState // .data.attributes.appVersionState // empty' "$out")
  CURRENT_RELEASE_TYPE=$(jq -r '.data.attributes.releaseType // empty' "$out")
  CURRENT_BUILD_ID=$(jq -r '.included[]? | select(.type=="builds") | .id' "$out" | head -1)
  CURRENT_BUILD_NUMBER=$(jq -r '.included[]? | select(.type=="builds") | .attributes.version' "$out" | head -1)
}

find_submission_by_states() {
  local states="$1" out="$2" code
  FOUND_SID=''; FOUND_SUB_STATE=''
  code=$(raw_get "/v1/apps/$app_id/reviewSubmissions?include=appStoreVersionForReview&limit=50" "$out")
  require_code 200 "$code" "$out" "$NAME: list review submissions"
  FOUND_SID=$(jq -r --arg vid "$version_id" --arg states "$states" '($states|split(",")) as $s | [.data[]? | select(.attributes.state as $st | $s | index($st)) | select(.relationships.appStoreVersionForReview.data.id==$vid)] | .[0].id // empty' "$out")
  if [[ -z "$FOUND_SID" ]]; then
    local count
    count=$(jq -r --arg states "$states" '($states|split(",")) as $s | [.data[]? | select(.attributes.state as $st | $s | index($st))] | length' "$out")
    if [[ "$count" -eq 1 ]]; then
      FOUND_SID=$(jq -r --arg states "$states" '($states|split(",")) as $s | .data[]? | select(.attributes.state as $st | $s | index($st)) | .id' "$out" | head -1)
    fi
  fi
  if [[ -n "$FOUND_SID" ]]; then FOUND_SUB_STATE=$(jq -r --arg id "$FOUND_SID" '.data[]? | select(.id==$id) | .attributes.state' "$out" | head -1); fi
}

submission_contains_version() {
  local sid="$1" out="$RUNNER_TEMP/volumecalc-items-$sid.json" code
  code=$(raw_get "/v1/reviewSubmissions/$sid/items?limit=200" "$out")
  require_code 200 "$code" "$out" "$NAME: read review items"
  jq -e --arg vid "$version_id" '.data[]? | select(.relationships.appStoreVersion.data.id==$vid)' "$out" >/dev/null 2>&1
}

echo "========== $NAME: attach Build $TARGET_BUILD and resubmit =========="
f="$RUNNER_TEMP/volumecalc-app.json"; code=$(raw_get "/v1/apps?filter%5BbundleId%5D=$BUNDLE&limit=10" "$f"); require_code 200 "$code" "$f" "$NAME: find app"; app_id=$(jq -r '.data[0].id // empty' "$f"); [[ -n "$app_id" ]]
f="$RUNNER_TEMP/volumecalc-versions.json"; code=$(raw_get "/v1/apps/$app_id/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BversionString%5D=$VERSION&limit=50" "$f"); require_code 200 "$code" "$f" "$NAME: find version"; version_id=$(jq -r '.data[0].id // empty' "$f"); [[ -n "$version_id" ]]
f="$RUNNER_TEMP/volumecalc-build3.json"; code=$(raw_get "/v1/builds?filter%5Bapp%5D=$app_id&filter%5Bversion%5D=$TARGET_BUILD&sort=-uploadedDate&limit=10" "$f"); require_code 200 "$code" "$f" "$NAME: find Build 3"; target_build_id=$(jq -r '.data[]? | select(.attributes.processingState=="VALID") | .id' "$f" | head -1); [[ -n "$target_build_id" ]]
echo "TARGET_BUILD=$TARGET_BUILD:$target_build_id:VALID"

# Export compliance is write-once in App Store Connect. Set it only when still unset.
f="$RUNNER_TEMP/volumecalc-build-current.json"; code=$(raw_get "/v1/builds/$target_build_id" "$f"); require_code 200 "$code" "$f" "$NAME: read Build 3"
encryption_value=$(jq -r 'if (.data.attributes | has("usesNonExemptEncryption")) then (.data.attributes.usesNonExemptEncryption | tostring) else "UNSET" end' "$f")
if [[ "$encryption_value" == 'UNSET' || "$encryption_value" == 'null' ]]; then
  body=$(jq -nc --arg id "$target_build_id" '{data:{type:"builds",id:$id,attributes:{usesNonExemptEncryption:false}}}')
  f="$RUNNER_TEMP/volumecalc-compliance.json"; code=$(raw_patch "/v1/builds/$target_build_id" "$body" "$f"); require_code 200 "$code" "$f" "$NAME: export compliance"
fi

read_version "$RUNNER_TEMP/volumecalc-before.json"
echo "BEFORE_STATE=$CURRENT_VSTATE BEFORE_BUILD=${CURRENT_BUILD_NUMBER:-none} RELEASE_TYPE=$CURRENT_RELEASE_TYPE"
if [[ "$CURRENT_BUILD_ID" == "$target_build_id" && "$CURRENT_BUILD_NUMBER" == "$TARGET_BUILD" && ( "$CURRENT_VSTATE" == 'WAITING_FOR_REVIEW' || "$CURRENT_VSTATE" == 'IN_REVIEW' ) ]]; then
  echo "VOLUMECALC_BUILD3_REVIEW_RESULT=ALREADY_OK:$CURRENT_VSTATE"
  exit 0
fi

if [[ "$CURRENT_BUILD_ID" != "$target_build_id" && ( "$CURRENT_VSTATE" == 'WAITING_FOR_REVIEW' || "$CURRENT_VSTATE" == 'IN_REVIEW' || "$CURRENT_VSTATE" == 'WAITING_FOR_EXPORT_COMPLIANCE' ) ]]; then
  find_submission_by_states 'WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES,CANCELING' "$RUNNER_TEMP/volumecalc-active.json"
  old_sid="$FOUND_SID"
  [[ -n "$old_sid" ]] || { echo 'ERROR: active review submission missing'; exit 1; }
  body=$(jq -nc --arg id "$old_sid" '{data:{type:"reviewSubmissions",id:$id,attributes:{canceled:true}}}')
  f="$RUNNER_TEMP/volumecalc-cancel.json"; code=$(raw_patch "/v1/reviewSubmissions/$old_sid" "$body" "$f"); require_code 200 "$code" "$f" "$NAME: cancel review"
  editable='false'
  for attempt in $(seq 1 48); do
    sleep 5; read_version "$RUNNER_TEMP/volumecalc-cancel-$attempt.json"
    case "$CURRENT_VSTATE" in DEVELOPER_REJECTED|REJECTED|PREPARE_FOR_SUBMISSION|READY_FOR_REVIEW) editable='true'; break;; esac
  done
  [[ "$editable" == 'true' ]] || { echo 'ERROR: version did not become editable after cancel'; exit 1; }
fi

if [[ "$CURRENT_BUILD_ID" != "$target_build_id" ]]; then
  body=$(jq -nc --arg id "$target_build_id" '{data:{type:"builds",id:$id}}')
  f="$RUNNER_TEMP/volumecalc-attach.json"; code=$(raw_patch "/v1/appStoreVersions/$version_id/relationships/build" "$body" "$f")
  [[ "$code" == '204' || "$code" == '200' ]] || { echo "ERROR: attach Build 3 HTTP $code"; cat "$f"; exit 1; }
fi
read_version "$RUNNER_TEMP/volumecalc-after-attach.json"
[[ "$CURRENT_BUILD_NUMBER" == "$TARGET_BUILD" && "$CURRENT_BUILD_ID" == "$target_build_id" ]] || { echo 'ERROR: Build 3 not attached'; exit 1; }
echo "BUILD3_ATTACHED=YES STATE=$CURRENT_VSTATE"

sid=''
for attempt in $(seq 1 36); do
  find_submission_by_states 'READY_FOR_REVIEW' "$RUNNER_TEMP/volumecalc-ready-$attempt.json"
  if [[ -n "$FOUND_SID" ]]; then
    if submission_contains_version "$FOUND_SID"; then sid="$FOUND_SID"; break; fi
    related=$(jq -r --arg id "$FOUND_SID" '.data[]? | select(.id==$id) | .relationships.appStoreVersionForReview.data.id // empty' "$RUNNER_TEMP/volumecalc-ready-$attempt.json")
    if [[ "$related" == "$version_id" ]]; then sid="$FOUND_SID"; break; fi
  fi
  sleep 5
done

if [[ -z "$sid" ]]; then
  body=$(jq -nc --arg app "$app_id" '{data:{type:"reviewSubmissions",relationships:{app:{data:{type:"apps",id:$app}}}}}')
  f="$RUNNER_TEMP/volumecalc-create.json"; code=$(raw_post '/v1/reviewSubmissions' "$body" "$f"); require_code 201 "$code" "$f" "$NAME: create review submission"; sid=$(jq -r '.data.id' "$f")
  body=$(jq -nc --arg sid "$sid" --arg vid "$version_id" '{data:{type:"reviewSubmissionItems",relationships:{reviewSubmission:{data:{type:"reviewSubmissions",id:$sid}},appStoreVersion:{data:{type:"appStoreVersions",id:$vid}}}}}')
  f="$RUNNER_TEMP/volumecalc-add.json"; code=$(raw_post '/v1/reviewSubmissionItems' "$body" "$f"); require_code 201 "$code" "$f" "$NAME: add version to review submission"
else
  echo "REUSING_REVIEW_SUBMISSION=$sid"
fi

body=$(jq -nc --arg id "$sid" '{data:{type:"reviewSubmissions",id:$id,attributes:{submitted:true}}}')
f="$RUNNER_TEMP/volumecalc-submit.json"; code=$(raw_patch "/v1/reviewSubmissions/$sid" "$body" "$f"); require_code 200 "$code" "$f" "$NAME: submit Build 3"

ok='false'
for attempt in $(seq 1 36); do
  sleep 5; read_version "$RUNNER_TEMP/volumecalc-final-$attempt.json"
  echo "FINAL_STATE=$CURRENT_VSTATE FINAL_BUILD=$CURRENT_BUILD_NUMBER attempt=$attempt"
  if [[ "$CURRENT_BUILD_NUMBER" == "$TARGET_BUILD" && ( "$CURRENT_VSTATE" == 'WAITING_FOR_REVIEW' || "$CURRENT_VSTATE" == 'IN_REVIEW' ) ]]; then ok='true'; break; fi
done
[[ "$ok" == 'true' ]] || { echo 'ERROR: VolumeCalc did not return to review with Build 3'; exit 1; }
echo "VOLUMECALC_BUILD3_REVIEW_RESULT=BUILD3:$CURRENT_VSTATE"
echo 'VOLUMECALC_BUILD3_REVIEW_REPLACEMENT_SUCCESS=1'
