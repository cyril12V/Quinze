"""Mirror of Library.migrated: runs the v3 list on a v2 library (plus user changes) to check the result.
usage: python3 -I sim_migration.py <seed v2 json> <seed v3 json>"""
import json, sys, uuid, copy

def as_library(seed):
    return [{"id": str(uuid.uuid4()), "name": p["name"], "group": p.get("group", ""),
             "songs": [{"id": str(uuid.uuid4()), "title": s["title"], "section": s.get("section", ""), "images": []}
                       for s in p["songs"]]} for p in seed]

def migrated(saved, seed):
    index = {}
    for pi, period in enumerate(saved):
        seen = {}
        for si, song in enumerate(period["songs"]):
            pair = (song["section"], song["title"]); n = seen.get(pair, 0); seen[pair] = n + 1
            index[(period["name"], song["section"], song["title"], n)] = (pi, si)
    claimed, used, result = {}, set(), []
    for sp in seed:
        names = [sp["name"]] + sp.get("was", [])
        base = next((p for nm in names for p in saved if p["name"] == nm and p["id"] not in used), None)
        period = copy.deepcopy(base) if base else {"id": str(uuid.uuid4()), "name": sp["name"], "songs": []}
        period["name"] = sp["name"]; period["group"] = sp.get("group", "")
        songs, here = [], 0
        for ss in sp["songs"]:
            f = ss.get("from")
            if f:
                place = index.get((f["period"], f["section"], f["title"], f["n"]))
                if place is None: continue
                song = dict(saved[place[0]]["songs"][place[1]])
                if song["id"] in claimed: continue
                song["title"] = ss["title"]; song["section"] = ss.get("section", "")
                claimed[song["id"]] = song["section"]; songs.append(song); here += 1
            else:
                songs.append({"id": str(uuid.uuid4()), "title": ss["title"], "section": ss.get("section", ""), "images": []})
        all_new = all("from" not in s for s in sp["songs"])
        if not (base or here or all_new): continue
        if base: used.add(base["id"])
        period["songs"] = songs; result.append(period)
    following, heads = {}, {}
    for period in saved:
        anchor = None
        for song in period["songs"]:
            if song["id"] in claimed: anchor = song; continue
            moved = dict(song)
            if anchor:
                if moved["section"] == anchor["section"]: moved["section"] = claimed[anchor["id"]]
                following.setdefault(anchor["id"], []).append(moved)
            else:
                heads.setdefault(period["id"], []).append(moved)
    for p in result:
        songs = heads.pop(p["id"], [])
        for s in p["songs"]:
            songs.append(s); songs += following.pop(s["id"], [])
        p["songs"] = songs
    for period in saved:
        if period["id"] in used: continue
        kept = dict(period); kept["songs"] = heads.pop(period["id"], [])
        if not any(s["id"] in claimed for s in period["songs"]): kept["songs"] = period["songs"]
        result.append(kept)
    return result

v2 = json.load(open(sys.argv[1])); v3 = json.load(open(sys.argv[2]))

# 1) untouched v2 library → exactly the v3 list
r = migrated(as_library(v2), v3)
assert [p["name"] for p in r] == [p["name"] for p in v3], [p["name"] for p in r]
for a, b in zip(r, v3):
    assert [(s["title"], s["section"]) for s in a["songs"]] == [(s["title"], s.get("section", "")) for s in b["songs"]], a["name"]
print("bibliothèque v2 intacte → identique à la liste v3 ✓")

# 2) user changes: photo on Marahmak, a chant added after Marahmak, a chant deleted, a period created,
#    a chant added at the top of Messe
lib = as_library(v2)
kiahk = next(p for p in lib if p["name"] == "Kiahk")
mar = next(s for s in kiahk["songs"] if s["title"] == "Marahmak"); mar["images"] = ["a.jpg", "b.jpg"]
i = kiahk["songs"].index(mar)
kiahk["songs"].insert(i + 1, {"id": "ADDED", "title": "Ya Mariam (franco)", "section": "Franco", "images": ["c.jpg"]})
kiahk["songs"] = [s for s in kiahk["songs"] if s["title"] != "Doxologie 6"]
lib.append({"id": "MINE", "name": "Mes cantiques", "songs": [{"id": "M1", "title": "Cantique perso", "section": "", "images": []}]})
messe = next(p for p in lib if p["name"] == "Messe")
messe["songs"].insert(0, {"id": "TOP", "title": "Mon chant d'entrée", "section": "", "images": []})
before = sum(len(p["songs"]) for p in lib)
r = migrated(lib, v3)
franco = next(p for p in r if p["name"] == "Franco")
print("Franco :", [(s["title"], s["section"], len(s["images"])) for s in franco["songs"]])
k = next(p for p in r if p["name"] == "Kiahk")
print("Doxologie 6 supprimée reste supprimée :", not any(s["title"] == "Doxologie 6" for s in k["songs"]))
basile = next(p for p in r if p["name"] == "Messe de saint Basile")
print("Messe de saint Basile commence par :", [s["title"] for s in basile["songs"][:3]], "| même id que Messe :", basile["id"] == messe["id"])
print("Période perso gardée :", [p["name"] for p in r][-1], [s["title"] for s in r[-1]["songs"]])
after = sum(len(p["songs"]) for p in r)
new = sum(1 for p in v3 for s in p["songs"] if "from" not in s)
print(f"chants avant {before}, après {after} (= avant + {new} nouveaux) :", after == before + new)
