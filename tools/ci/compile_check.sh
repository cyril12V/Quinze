#!/usr/bin/env bash
# Compile l'app, ses 3 extensions et les tests pour le simulateur iOS, sans signature ni secret.
# Sert à corriger les erreurs de compilation sans dépendre du compte Apple Developer.
set -uo pipefail
cd "$(dirname "$0")/../.."
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
mkdir -p build

XCODE=$(ls -d /Applications/Xcode_26*.app 2>/dev/null | sort -V | tail -1 || true)
[ -n "$XCODE" ] || XCODE=$(ls -d /Applications/Xcode_*.app | sort -V | tail -1)
sudo xcode-select -s "$XCODE"
xcodebuild -version
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

xcodebuild build-for-testing -project Quinze.xcodeproj -scheme Quinze -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/compile.log
status=${PIPESTATUS[0]}

errors=$(grep -E "^/.*: error: " build/compile.log | sed 's#^.*/Quinze/Quinze/##; s#^/Users/runner/work/[^/]*/[^/]*/##' | sort -u)
count=$(printf '%s' "$errors" | grep -c . || true)
{
  if [ "$status" -eq 0 ]; then
    echo "### Compilation réussie (app, 3 extensions et tests)"
  else
    echo "### Compilation en échec : $count erreur(s)"
    echo '```'
    printf '%s\n' "$errors" | head -n 300
    grep -E "error:" build/compile.log | grep -vE "^/.*: error: " | sort -u | head -n 30
    echo '```'
  fi
} >> "$SUMMARY"
exit "$status"
