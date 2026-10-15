"""Generate one compact brief per module (Content/en/briefs/mNN.md) from curriculum.json,
so content writers do not need to read the whole curriculum."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIAG_LEVEL = {1: 0, 2: 1, 3: 2, 4: 3, 5: 3, 6: 1, 7: 4, 8: 4}


def slug(text):
    s = text.lower().replace("'", "").replace("’", "")
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


cur = json.loads((ROOT / "Content/en/curriculum.json").read_text())
vocab = {v["id"]: v for v in cur["vocabularyUnits"]}
gram = {g["id"]: g for g in cur["grammarUnits"]}
out_dir = ROOT / "Content/en/briefs"
out_dir.mkdir(parents=True, exist_ok=True)

for m in cur["modules"]:
    mid = m["id"]
    lessons = [l for l in cur["lessons"] if l["module"] == mid]
    first_seq = lessons[0]["sequence"]
    prev_lessons = [l for l in cur["lessons"] if l["sequence"] < first_seq]
    prev_vocab = [vocab[u]["title"] for l in prev_lessons for u in l["introduces"] if u in vocab]
    prev_gram = [gram[l["grammarUnitId"]]["title"] for l in prev_lessons if l["introducesGrammar"]]
    gunits = [g for g in cur["grammarUnits"] if g["module"] == mid]
    lines = [f"# Module {mid} — {m['title']}", "", m["description"], ""]
    lines += [f"Leçons en.l{lessons[0]['sequence']:02d} à en.l{lessons[-1]['sequence']:02d}. "
              f"Niveau du diagnostic : {DIAG_LEVEL[mid]}. Dossier : Content/en/source/m{mid:02d}/", ""]
    lines += ["## Notions de grammaire du module (units.json : une règle par notion)", ""]
    for g in gunits:
        pre = ", ".join(g["prerequisites"]) or "aucun"
        fw = ", ".join(g["functionWords"]) or "—"
        lines.append(f"- `{g['id']}` — {g['title']} (catégorie {g['category']}, difficulté {g['difficulty']}) ; prérequis : {pre} ; mots-outils : {fw}")
    lines += ["", "## Leçons", ""]
    for l in lessons:
        kind = "INTRODUIT la notion" if l["introducesGrammar"] else "PRATIQUE de la notion (déjà introduite)"
        lines.append(f"### en.l{l['sequence']:02d} — {l['title']}")
        lines.append(f"{l['description']} Notion principale : `{l['grammarUnitId']}` ({kind}). Difficulté {l['difficulty']}.")
        lines.append("Vocabulaire introduit (unitId → fiche dictionnaire) :")
        for u in l["introduces"]:
            if u in vocab:
                v = vocab[u]
                lines.append(f"- `{u}` « {v['title']} » = {v['translation']} ({v['partOfSpeech']}) → `{v['dictionaryItemId']}`")
        lines.append("")
    lines += ["## Fiches dictionnaire attendues (dictionary.json)", ""]
    ids = [vocab[u]["dictionaryItemId"] for l in lessons for u in l["introduces"] if u in vocab]
    fws = [(fw, f"en.d.{slug(fw)}") for g in gunits for fw in g["functionWords"]]
    lines.append(f"Vocabulaire ({len(ids)}) : " + ", ".join(f"`{i}`" for i in ids))
    lines.append("")
    lines.append(f"Mots-outils ({len(fws)}, `unitId: null`) : " + ", ".join(f"{w} → `{i}`" for w, i in fws))
    lines += ["", "## Déjà connu de l'apprenant avant ce module", ""]
    lines.append("Notions : " + ("; ".join(prev_gram) if prev_gram else "aucune (premier module)"))
    lines.append("")
    lines.append(f"Vocabulaire ({len(prev_vocab)} mots) : " + (", ".join(prev_vocab) if prev_vocab else "aucun"))
    (out_dir / f"m{mid:02d}.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"m{mid:02d}: {len(lessons)} lessons, {len(ids)} vocab, {len(fws)} function words")
