#!/usr/bin/env bash
set -euo pipefail

API='https://api.appstoreconnect.apple.com'
LOC_ID='b236c044-e75f-4581-97e2-d4ae71e5c1a6'

: "${ASC_ISSUER_ID:?missing ASC_ISSUER_ID}"
: "${ASC_KEY_ID:?missing ASC_KEY_ID}"
: "${ASC_PRIVATE_KEY_B64:?missing ASC_PRIVATE_KEY_B64}"

KEY_DIR="$RUNNER_TEMP/volumecalc-description"
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

DESCRIPTION=$(cat <<'EOF'
VolumeCalc berechnet den Wasserinhalt von Heizungsanlagen anhand der tatsächlich verbauten Komponenten. Statt pauschaler Schätzwerte erfasst du Rohrleitungen, Heizflächen und wasserführende Geräte und erhältst daraus einen nachvollziehbaren Anlageninhalt.

Unterstützt werden Kupfer, Mehrschichtverbund, PE-X, Stahl-Gewinderohr schwarz und verzinkt, Siederohr, Edelstahl-Press und PP-R. Fußboden-, Wand- und Deckenheizungen lassen sich ebenso erfassen wie Flachheizkörper sowie alte Stahl- und Guss-Gliederheizkörper. Herstellerwerte können jederzeit direkt eingetragen werden.

Auch Puffer und Speicher, Wärmeerzeuger, hydraulische Weichen, Verteiler und Sammler, Wärmetauscher sowie beliebige weitere bekannte Wasserinhalte können ergänzt werden. Die App zeigt den berechneten Anlageninhalt und eine separat einstellbare Planungsreserve. Mehrere Projekte werden lokal auf dem Gerät gespeichert und Ergebnisse können über die iOS-Teilen-Funktion weitergegeben werden.

VolumeCalc benötigt kein Benutzerkonto. Die Kernberechnung funktioniert vollständig offline.

Fachlicher Hinweis: Referenzwerte dienen als Arbeitshilfe. Für exakte Auslegung und sicherheitsrelevante Entscheidungen haben Herstellerangaben, geltende Normen und reale Messwerte Vorrang.

End User License Agreement (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
EOF
)

BODY=$(jq -nc --arg id "$LOC_ID" --arg description "$DESCRIPTION" '{data:{type:"appStoreVersionLocalizations",id:$id,attributes:{description:$description}}}')
OUT="$RUNNER_TEMP/volumecalc-description-patch.json"
CODE=$(/usr/bin/curl --globoff --silent --show-error --output "$OUT" --write-out '%{http_code}' -X PATCH \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$BODY" \
  "$API/v1/appStoreVersionLocalizations/$LOC_ID")
if [[ "$CODE" != '200' ]]; then
  echo "Description update failed: HTTP $CODE"
  jq '.' "$OUT" 2>/dev/null || cat "$OUT" || true
  exit 1
fi

VERIFY="$RUNNER_TEMP/volumecalc-description-verify.json"
VCODE=$(/usr/bin/curl --globoff --silent --show-error --output "$VERIFY" --write-out '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" "$API/v1/appStoreVersionLocalizations/$LOC_ID")
[[ "$VCODE" == '200' ]]
ACTUAL=$(jq -r '.data.attributes.description' "$VERIFY")
[[ "$ACTUAL" == "$DESCRIPTION" ]]
if grep -Fq '\\n' <<<"$ACTUAL"; then
  echo 'Literal \\n sequence found in App Store description.'
  exit 1
fi
grep -Fq 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/' <<<"$ACTUAL"
echo "DESCRIPTION_RESULT=UPDATED_AND_VERIFIED"
echo "DESCRIPTION_LENGTH=${#ACTUAL}"
