#!/usr/bin/env bash
# Déballe le zip de Quinze envoyé dans le dépôt depuis l'iPhone, puis enregistre le code dans le dépôt.
# Lancé depuis le zip déballé : bash <zip déballé>/tools/ci/unpack.sh <nom du zip>, dossier courant = le dépôt.
# Les fichiers de .github/workflows ne sont jamais touchés (GitHub interdit au robot de les modifier).
set -euo pipefail
ZIP="$1"
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$(pwd)"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# Config/perso.env : une valeur déjà remplie dans le dépôt n'est jamais effacée par un zip qui la laisse vide.
if [ -f "$DEST/Config/perso.env" ] && [ -f "$SRC/Config/perso.env" ]; then
  python3 - "$SRC/Config/perso.env" "$DEST/Config/perso.env" <<'PY'
import sys
src_path, dest_path = sys.argv[1], sys.argv[2]
def parse(path):
    values = {}
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\r\n")
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values
old = parse(dest_path)
lines, seen = [], set()
for line in open(src_path, encoding="utf-8"):
    line = line.rstrip("\r\n")
    if "=" in line and not line.lstrip().startswith("#"):
        key, value = (part.strip() for part in line.split("=", 1))
        seen.add(key)
        if not value and old.get(key):
            line = f"{key}={old[key]}"
    lines.append(line)
lines += [f"{k}={v}" for k, v in old.items() if k not in seen and v]
open(src_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
fi

# Les fichiers du dépôt absents du zip sont supprimés, puis le zip est copié par-dessus.
rm -rf "$SRC/.git" "$SRC/.github/workflows"
git ls-files -z | while IFS= read -r -d '' file; do
  case "$file" in .github/workflows/*|*.zip) continue ;; esac
  if [ ! -e "$SRC/$file" ]; then git rm -q --cached -- "$file"; rm -f -- "$file"; fi
done
cp -a "$SRC/." "$DEST/"
git rm -q --cached --ignore-unmatch -- *.zip
rm -f -- *.zip
git add -A
if git diff --cached --quiet; then
  echo "Rien de nouveau dans $ZIP."
else
  git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
      commit -q -m "Quinze : code déballé depuis $ZIP"
  git push -q origin "HEAD:${GITHUB_REF_NAME:-main}"
fi
echo "### Code de Quinze en place ($ZIP déballé, $(git ls-files | wc -l | tr -d ' ') fichiers)" >> "$SUMMARY"
