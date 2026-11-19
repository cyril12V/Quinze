"""Builds Hazzat/Resources/seed.json (v2) from liste-v2.txt, and links every chant to its v1 entry
so the app can reorder an existing library without losing anything."""
import json, sys

def parse(path):
    periods, cur, section = [], None, ""
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n").strip()
        if not line:
            continue
        if line.startswith("# "):
            cur = {"name": line[2:].strip(), "songs": []}
            periods.append(cur)
            section = ""
        elif line.startswith("##"):
            section = line[2:].strip()
        elif line.startswith("- "):
            t = line[2:].strip()
            done = t.endswith("✅")
            t = t.replace("✅", "").strip()
            old = None
            if " <= " in t:
                t, old = [x.strip() for x in t.split(" <= ", 1)]
            cur["songs"].append({"title": t, "section": section, "old": old or t, "done": done})
        else:
            sys.exit(f"ligne inconnue: {line}")
    return periods

v1 = parse(sys.argv[1])
v2 = parse(sys.argv[2])
current = json.load(open(sys.argv[3], encoding="utf-8"))

# The v1 parse must be exactly what the phones were seeded with.
assert [p["name"] for p in v1] == [p["name"] for p in current]
for a, b in zip(v1, current):
    assert [(s["title"], s["section"]) for s in a["songs"]] == [(s["title"], s.get("section", "")) for s in b["songs"]], a["name"]

assert [p["name"] for p in v1] == [p["name"] for p in v2], "périodes différentes"
out = []
for p1, p2 in zip(v1, v2):
    # key of each v1 song: section, title, occurrence of that pair in the period
    seen, keys = {}, []
    for s in p1["songs"]:
        k = (s["section"], s["title"])
        n = seen.get(k, 0); seen[k] = n + 1
        keys.append({"section": s["section"], "title": s["title"], "n": n})
    used = [False] * len(keys)
    songs = []
    for s in p2["songs"]:
        hit = next((i for i, k in enumerate(keys) if not used[i] and k["title"] == s["old"]), None)
        if hit is None:
            sys.exit(f"{p2['name']} : « {s['old']} » introuvable dans la v1")
        used[hit] = True
        songs.append({"title": s["title"], "section": s["section"], "from": keys[hit]})
    missing = [keys[i]["title"] for i, u in enumerate(used) if not u]
    if missing:
        sys.exit(f"{p1['name']} : chants perdus {missing}")
    out.append({"name": p2["name"], "songs": songs})

json.dump(out, open(sys.argv[4], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
total = sum(len(p["songs"]) for p in out)
moved = sum(1 for p1, p in zip(v1, out) for i, s in enumerate(p["songs"]) if (s["title"], s["section"]) != (p1["songs"][i]["title"], p1["songs"][i]["section"]))
print(f"{len(out)} périodes, {total} chants, {moved} places changées")
