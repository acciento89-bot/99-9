#!/usr/bin/env bash
set -euo pipefail
API='https://api.appstoreconnect.apple.com'
: "${ASC_ISSUER_ID:?missing ASC_ISSUER_ID}"
: "${ASC_KEY_ID:?missing ASC_KEY_ID}"
: "${ASC_PRIVATE_KEY_B64:?missing ASC_PRIVATE_KEY_B64}"
KEY_DIR="$RUNNER_TEMP/shk-build3-audit"; mkdir -p "$KEY_DIR"
KEY_PATH="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
printf '%s' "$ASC_PRIVATE_KEY_B64" | tr -d '\r\n ' | base64 --decode > "$KEY_PATH"
chmod 600 "$KEY_PATH"; export ASC_KEY_PATH="$KEY_PATH"
trap 'rm -rf "$KEY_DIR"' EXIT
TOKEN=$(ruby <<'RUBY'
require 'openssl'; require 'base64'; require 'json'
def b(v); Base64.urlsafe_encode64(v,padding:false); end
key=OpenSSL::PKey.read(File.read(ENV.fetch('ASC_KEY_PATH'))); now=Time.now.to_i
h=b(JSON.generate({alg:'ES256',kid:ENV.fetch('ASC_KEY_ID'),typ:'JWT'})); p=b(JSON.generate({iss:ENV.fetch('ASC_ISSUER_ID'),iat:now,exp:now+900,aud:'appstoreconnect-v1'})); s="#{h}.#{p}"
seq=OpenSSL::ASN1.decode(key.sign(OpenSSL::Digest::SHA256.new,s)); raw=seq.value.map{|i|[i.value.to_i.to_s(16).rjust(64,'0')].pack('H*')}.join
puts "#{s}.#{b(raw)}"
RUBY
)
get(){ curl --globoff --fail-with-body -sS -H "Authorization: Bearer $TOKEN" "$API$1"; }
app_line(){
 case "$1" in
  kaltecalc) echo 'KälteCalc|de.kamilunav.kaltecalc' ;;
  lueftungscalc) echo 'LüftungsCalc|de.kamilunavo.luftungscalc' ;;
  heizkoerpercalc) echo 'HeizkörperCalc|de.kamilunavo.heizkorpercalc' ;;
  rohrcalc) echo 'RohrCalc|de.kamilunavo.rohrcalc' ;;
  anlagencheck) echo 'AnlagenCheck|de.kamilunavo.servicecheck' ;;
 esac
}
for key in kaltecalc lueftungscalc heizkoerpercalc rohrcalc anlagencheck; do
 IFS='|' read -r name bundle <<<"$(app_line "$key")"
 apps=$(get "/v1/apps?filter%5BbundleId%5D=$bundle&limit=10")
 app_id=$(jq -r '.data[0].id // empty' <<<"$apps")
 versions=$(get "/v1/apps/$app_id/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BversionString%5D=1.0&limit=50")
 vid=$(jq -r '.data[0].id // empty' <<<"$versions")
 ver=$(get "/v1/appStoreVersions/$vid?include=build")
 state=$(jq -r '.data.attributes.appStoreState // .data.attributes.appVersionState // "UNKNOWN"' <<<"$ver")
 release=$(jq -r '.data.attributes.releaseType // "UNKNOWN"' <<<"$ver")
 cur_num=$(jq -r '.included[]? | select(.type=="builds") | .attributes.version' <<<"$ver" | head -1)
 cur_id=$(jq -r '.included[]? | select(.type=="builds") | .id' <<<"$ver" | head -1)
 b3=$(get "/v1/builds?filter%5Bapp%5D=$app_id&filter%5Bversion%5D=3&sort=-uploadedDate&limit=10")
 b3_id=$(jq -r '.data[0].id // empty' <<<"$b3")
 b3_state=$(jq -r '.data[0].attributes.processingState // "MISSING"' <<<"$b3")
 subs=$(get "/v1/apps/$app_id/reviewSubmissions?limit=50")
 sub_states=$(jq -r '[.data[]?.attributes.state] | join(",")' <<<"$subs")
 echo "AUDIT|$key|$name|VERSION_STATE=$state|CURRENT_BUILD=${cur_num:-none}|CURRENT_BUILD_ID=${cur_id:-none}|BUILD3=$b3_state|BUILD3_ID=${b3_id:-none}|RELEASE=$release|REVIEW_SUBMISSIONS=${sub_states:-none}"
done
