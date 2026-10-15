#!/usr/bin/env bash
# Compile Quinze pour TON iPhone (signature de développement) et crée un lien d'installation Diawi.
# Appelé par .github/workflows/iphone.yml. Toute la logique est ici, pour que le workflow reste court.
set -euo pipefail
cd "$(dirname "$0")/../.."
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
mkdir -p build

fail() {
  {
    echo "### Échec : $1"
    if ls build/*.log >/dev/null 2>&1; then
      echo '```'
      grep -hE "error:|\*\* (ARCHIVE|EXPORT) FAILED|Provisioning|No profiles|Family Controls|entitlement|certificate" build/*.log 2>/dev/null | sort -u | head -n 60 || true
      echo '```'
    fi
  } >> "$SUMMARY"
  echo "::error::$1"
  # Les 15 premières erreurs s'affichent aussi en haut de la page du run (lisible sur iPhone).
  grep -hE "error:" build/*.log 2>/dev/null | sed 's#^.*/quinze/##; s#^.*/work/[^/]*/[^/]*/##' | sort -u | head -n 15 \
    | while IFS= read -r line; do echo "::error::$line"; done || true
  exit 1
}
trap 'fail "étape interrompue (voir le journal ci-dessus)"' ERR

# 1. Identifiants : secret GitHub du même nom, sinon ligne de Config/perso.env.
#    Le workflow passe tous les secrets d'un coup (SECRETS_JSON) : rien à changer dans le YAML pour en ajouter un.
secret() {
  [ -n "${SECRETS_JSON:-}" ] || return 0
  printf '%s' "$SECRETS_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1"
}
for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 DIAWI_TOKEN DEVELOPMENT_TEAM BUNDLE_ID_PREFIX IPHONE_UDID IPHONE_NAME SUPABASE_URL SUPABASE_ANON_KEY; do
  value="$(secret "$name")"
  [ -n "$value" ] || value="${!name:-}"
  if [ -z "$value" ] && [ -f Config/perso.env ]; then
    value=$(grep -E "^$name=" Config/perso.env | head -1 | cut -d= -f2- | tr -d '\r' | sed 's/^ *//; s/ *$//' || true)
  fi
  export "$name=$value"
done
missing=""
for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 DEVELOPMENT_TEAM IPHONE_UDID; do
  [ -n "${!name:-}" ] || missing="$missing $name"
done

# Mode --check (job Linux, gratuit) : dit seulement si tout est prêt pour lancer la compilation sur Mac.
if [ "${1:-}" = "--check" ]; then
  trap - ERR
  if [ -z "$missing" ]; then
    echo "build=yes" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "Tout est prêt : compilation lancée." >> "$SUMMARY"
  else
    echo "build=no" >> "${GITHUB_OUTPUT:-/dev/null}"
    {
      echo "Pas encore de compilation. Il manque :"
      for name in $missing; do
        case "$name" in
          ASC_KEY_P8) echo "- **ASC_KEY_P8** : secret GitHub (Settings > Secrets and variables > Actions), contenu du fichier .p8" ;;
          *) echo "- **$name** : ligne \`$name=\` dans Config/perso.env (ou secret GitHub du même nom)" ;;
        esac
      done
    } >> "$SUMMARY"
  fi
  [ -n "$DIAWI_TOKEN" ] || echo "- facultatif : **DIAWI_TOKEN** (secret) pour recevoir un lien d'installation" >> "$SUMMARY"
  exit 0
fi
[ -z "$missing" ] || { trap - ERR; fail "il manque :$missing (secret GitHub, ou ligne dans Config/perso.env)"; }

# 2. Xcode 26 (le plus récent du runner) et XcodeGen.
XCODE=$(ls -d /Applications/Xcode_26*.app 2>/dev/null | sort -V | tail -1 || true)
[ -n "$XCODE" ] || XCODE=$(ls -d /Applications/Xcode_*.app | sort -V | tail -1)
echo "Xcode utilisé : $XCODE"
sudo xcode-select -s "$XCODE"
xcodebuild -version
command -v xcodegen >/dev/null || brew install xcodegen

# 3. Réglages de compilation (Supabase facultatif : vide = mode local).
{
  echo "DEVELOPMENT_TEAM = $DEVELOPMENT_TEAM"
  [ -z "${BUNDLE_ID_PREFIX:-}" ] || echo "BUNDLE_ID_PREFIX = $BUNDLE_ID_PREFIX"
  if [ -n "${SUPABASE_URL:-}" ]; then
    echo "SUPABASE_URL = $(printf '%s' "$SUPABASE_URL" | sed 's#//#/$()/#')"
    echo "SUPABASE_ANON_KEY = ${SUPABASE_ANON_KEY:-}"
  fi
  echo "CURRENT_PROJECT_VERSION = ${GITHUB_RUN_NUMBER:-1}"
} > Config/Secrets.xcconfig

# 4. Clé App Store Connect (fichier .p8 collé tel quel, ou en base64).
mkdir -p "$HOME/.appstoreconnect/private_keys"
export ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
# Tolère un texte collé avec des lignes en trop autour, ou des retours à la ligne perdus.
printf '%s' "$ASC_KEY_P8" | python3 -c '
import base64, re, sys, textwrap
raw = sys.stdin.read()
match = re.search(r"-----BEGIN PRIVATE KEY-----(.*?)-----END PRIVATE KEY-----", raw, re.S)
body = re.sub(r"\s+", "", match.group(1) if match else raw)
if not match:
    decoded = base64.b64decode(body).decode()
    inner = re.search(r"-----BEGIN PRIVATE KEY-----(.*?)-----END PRIVATE KEY-----", decoded, re.S)
    body = re.sub(r"\s+", "", inner.group(1) if inner else decoded)
print("-----BEGIN PRIVATE KEY-----\n" + "\n".join(textwrap.wrap(body, 64)) + "\n-----END PRIVATE KEY-----")
' > "$ASC_KEY_PATH"
chmod 600 "$ASC_KEY_PATH"
cleanup() { rm -f "$ASC_KEY_PATH"; }
trap cleanup EXIT

# 5. Enregistre l'iPhone dans le compte (sans effet s'il l'est déjà).
bundle exec fastlane register_iphone 2>&1 | tee build/register.log

# 6. Projet, archive, export « développement ».
xcodegen generate
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
xcodebuild archive -project Quinze.xcodeproj -scheme Quinze -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Quinze.xcarchive -derivedDataPath build/DerivedData \
  "${AUTH[@]}" 2>&1 | tee build/archive.log
cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>debugging</string>
  <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath build/Quinze.xcarchive -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist "${AUTH[@]}" 2>&1 | tee build/export.log
IPA=$(ls build/export/*.ipa | head -1)

# 7. Lien d'installation Diawi (si le jeton existe).
LINK=""
if [ -n "${DIAWI_TOKEN:-}" ]; then
  JOB=$(curl -sS https://upload.diawi.com/ -F "token=$DIAWI_TOKEN" -F "file=@$IPA" -F "find_by_udid=0" -F "wall_of_apps=0" \
        | python3 -c 'import sys,json; print(json.load(sys.stdin).get("job",""))')
  [ -n "$JOB" ] || fail "envoi Diawi refusé (jeton DIAWI_TOKEN invalide ?)"
  for _ in $(seq 1 36); do
    sleep 5
    STATUS=$(curl -sS "https://upload.diawi.com/status?token=$DIAWI_TOKEN&job=$JOB")
    CODE=$(printf '%s' "$STATUS" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))')
    if [ "$CODE" = "2000" ]; then
      LINK=$(printf '%s' "$STATUS" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("link",""))')
      break
    fi
    [ "$CODE" = "2001" ] || fail "Diawi : $STATUS"
  done
fi

trap - ERR
{
  echo "### Quinze est prêt pour ton iPhone"
  echo ""
  if [ -n "$LINK" ]; then
    echo "**Ouvre ce lien dans Safari sur ton iPhone, puis touche Installer :** $LINK"
  else
    echo "Pas de lien Diawi (secret DIAWI_TOKEN absent) : l'IPA est dans l'artefact **quinze-iphone** en bas de cette page."
  fi
  echo ""
  echo "Première installation : active **Réglages > Confidentialité et sécurité > Mode développeur**, puis redémarre l'iPhone."
} >> "$SUMMARY"
echo "Terminé. ${LINK:+Lien : $LINK}"
