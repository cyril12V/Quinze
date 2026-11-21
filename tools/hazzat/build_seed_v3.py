"""Builds Hazzat/Resources/seed.json (v3) from liste-v3.txt.
Every chant of v2 must be placed exactly once (nothing lost); `+ Titre` adds a new chant.
Each chant keeps a link (`from`) to where it was in v2, so the app can move the user's own chants
(with their photos) to their new place."""
import json, sys

def parse_v2(path):
    periods, cur, section = [], None, ""
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line: continue
        if line.startswith("# "):
            cur = {"name": line[2:].strip(), "songs": []}; periods.append(cur); section = ""
        elif line.startswith("##"):
            section = line[2:].strip()
        elif line.startswith("- "):
            t = line[2:].replace("✅", "").strip()
            if " <= " in t: t = t.split(" <= ", 1)[0].strip()
            cur["songs"].append({"title": t, "section": section})
    return periods

def parse_v3(path):
    periods, cur, section = [], None, ""
    for n, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.strip()
        if not line: continue
        if line.startswith("# "):
            cur = {"name": line[2:].strip(), "group": "", "was": [], "songs": []}; periods.append(cur); section = ""
        elif line.startswith("@group "):
            cur["group"] = line[7:].strip()
        elif line.startswith("@was "):
            cur["was"].append(line[5:].strip())
        elif line.startswith("##"):
            section = line[2:].strip()
        elif line.startswith("+ "):
            cur["songs"].append({"title": line[2:].strip(), "section": section, "new": True})
        elif line.startswith("- "):
            t = line[2:].strip(); src = None; old = None
            if " @ " in t: t, src = [x.strip() for x in t.rsplit(" @ ", 1)]
            if " <= " in t: t, old = [x.strip() for x in t.split(" <= ", 1)]
            cur["songs"].append({"title": t, "section": section, "old": old or t, "src": src})
        else:
            sys.exit(f"ligne {n} inconnue : {line}")
    return periods

v2 = parse_v2(sys.argv[1]); v3 = parse_v3(sys.argv[2]); shipped = json.load(open(sys.argv[3], encoding="utf-8"))
# the v2 list must be exactly what phones have as v2
assert [p["name"] for p in v2] == [p["name"] for p in shipped]
for a, b in zip(v2, shipped):
    assert [(s["title"], s["section"]) for s in a["songs"]] == [(s["title"], s.get("section", "")) for s in b["songs"]], a["name"]

# keys of v2 songs: (period, section, title, n)
keys, used = {}, {}
for p in v2:
    seen = {}
    lst = []
    for s in p["songs"]:
        k = (s["section"], s["title"]); n = seen.get(k, 0); seen[k] = n + 1
        lst.append({"period": p["name"], "section": s["section"], "title": s["title"], "n": n})
    keys[p["name"]] = lst; used[p["name"]] = [False] * len(lst)

out = []
for p in v3:
    songs = []
    for s in p["songs"]:
        if s.get("new"):
            songs.append({"title": s["title"], "section": s["section"]}); continue
        src = s["src"] or (p["was"][0] if p["was"] else p["name"])
        if src not in keys: sys.exit(f"{p['name']} : période source inconnue {src}")
        hit = next((i for i, k in enumerate(keys[src]) if not used[src][i] and k["title"] == s["old"]), None)
        if hit is None: sys.exit(f"{p['name']} : « {s['old']} » introuvable dans {src} (v2)")
        used[src][hit] = True
        songs.append({"title": s["title"], "section": s["section"], "from": keys[src][hit]})
    entry = {"name": p["name"], "songs": songs}
    if p["group"]: entry["group"] = p["group"]
    if p["was"]: entry["was"] = p["was"]
    out.append(entry)

lost = [f"{k} / {keys[k][i]['title']}" for k in keys for i, u in enumerate(used[k]) if not u]
if lost: sys.exit("chants perdus : " + ", ".join(lost))
json.dump(out, open(sys.argv[4], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
total = sum(len(p["songs"]) for p in out); new = sum(1 for p in out for s in p["songs"] if "from" not in s)
print(f"{len(out)} périodes, {total} chants dont {new} nouveaux ; aucun chant de la v2 perdu")
