#!/usr/bin/env bash
# Envoie un IPA sur Diawi et écrit le lien d'installation dans le résumé du run.
# Usage : DIAWI_TOKEN=... tools/ci/diawi_upload.sh chemin/vers/Quinze.ipa
# Code de sortie 0 avec le lien, 1 si Diawi refuse (le message de Diawi est affiché).
set -uo pipefail
IPA="$1"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

if [ -z "${DIAWI_TOKEN:-}" ]; then
  echo "Pas de lien Diawi (secret DIAWI_TOKEN absent) : l'IPA est dans l'artefact **quinze-iphone** en bas de cette page." >> "$SUMMARY"
  exit 1
fi

json_field() { python3 -c 'import sys,json
try: print(json.load(sys.stdin).get(sys.argv[1]) or "")
except Exception: print("")' "$1"; }

# Le jeton ne doit jamais apparaître dans les messages.
clean() { sed "s/${DIAWI_TOKEN}/***/g" | head -c 600; }

RESP=$(curl -sS https://upload.diawi.com/ -F "token=$DIAWI_TOKEN" -F "file=@$IPA" \
       -F "find_by_udid=0" -F "wall_of_apps=0" 2>&1)
JOB=$(printf '%s' "$RESP" | json_field job)
if [ -z "$JOB" ]; then
  MSG=$(printf '%s' "$RESP" | clean)
  echo "::error::Diawi a refusé l'envoi : $MSG"
  echo "### Diawi a refusé l'envoi : \`$MSG\`" >> "$SUMMARY"
  exit 1
fi

for _ in $(seq 1 60); do
  sleep 5
  STATUS=$(curl -sS "https://upload.diawi.com/status?token=$DIAWI_TOKEN&job=$JOB" 2>&1)
  CODE=$(printf '%s' "$STATUS" | json_field status)
  case "$CODE" in
    2000)
      LINK=$(printf '%s' "$STATUS" | json_field link)
      echo "LINK=$LINK"
      {
        echo "### Quinze est prêt pour ton iPhone"
        echo ""
        echo "**Ouvre ce lien dans Safari sur ton iPhone, puis touche Installer :** $LINK"
        echo ""
        echo "Première installation : active **Réglages > Confidentialité et sécurité > Mode développeur**, puis redémarre l'iPhone."
      } >> "$SUMMARY"
      exit 0 ;;
    2001) ;;
    *)
      MSG=$(printf '%s' "$STATUS" | clean)
      echo "::error::Diawi : $MSG"
      echo "### Diawi a refusé l'IPA : \`$MSG\`" >> "$SUMMARY"
      exit 1 ;;
  esac
done
echo "::error::Diawi n'a pas fini de traiter l'IPA après 5 minutes."
exit 1
