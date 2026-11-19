# Mirror of Library.reordered, run on the v1 seed (+ a chant the user added) to check the result.
import json, sys
v1 = json.load(open(sys.argv[1])); v2 = json.load(open(sys.argv[2]))
def reordered(saved, seed):
    out = []
    for period in saved:
        sp = next((p for p in seed if p['name'] == period['name']), None)
        if sp is None: out.append(period); continue
        songs = period['songs']; idx = {}; seen = {}
        for i, s in enumerate(songs):
            pair = (s.get('section',''), s['title']); n = seen.get(pair, 0); seen[pair] = n + 1
            idx[(pair[0], pair[1], n)] = i
        placed, renamed = [], {}
        for ss in sp['songs']:
            f = ss.get('from'); 
            if not f: continue
            i = idx.get((f['section'], f['title'], f['n']))
            if i is None or i in renamed: continue
            placed.append(i); renamed[i] = (ss['title'], ss.get('section',''))
        if not placed: out.append(period); continue
        following, head, anchor = {}, [], None
        for i in range(len(songs)):
            if i in renamed: anchor = i; continue
            (following.setdefault(anchor, []) if anchor is not None else head).append(i)
        res = []
        def own(i, a):
            s = dict(songs[i])
            if a is not None and s.get('section','') == songs[a].get('section','') and a in renamed: s['section'] = renamed[a][1]
            res.append(s)
        for i in head: own(i, None)
        for i in placed:
            s = dict(songs[i]); s['title'], s['section'] = renamed[i]; res.append(s)
            for j in following.get(i, []): own(j, i)
        out.append({**period, 'songs': res})
    return out
# 1) plain v1 → must equal v2 exactly
r = reordered(v1, v2)
for a, b in zip(r, v2):
    assert [(s['title'], s['section']) for s in a['songs']] == [(s['title'], s['section']) for s in b['songs']], a['name']
print("v1 → v2 : identique à la nouvelle liste ✓")
# 2) user added a chant after « Doxologie 6 » (Messe part) and attached a photo to Hiten
k = next(p for p in v1 if p['name'] == 'Kiahk')
i = next(i for i, s in enumerate(k['songs']) if s['title'] == 'Doxologie 6')
k['songs'].insert(i + 1, {'title': 'Doxologie de Mar Girgis', 'section': 'Messe', 'id': 'NEW'})
next(s for s in k['songs'] if s['title'] == 'Hiten ✅' or s['title'] == 'Hiten')['images'] = ['abc.jpg']
r = reordered(v1, v2)
kk = next(p for p in r if p['name'] == 'Kiahk')['songs']
j = next(i for i, s in enumerate(kk) if s.get('id') == 'NEW')
print("ajouté :", kk[j-1]['title'], '→', kk[j]['title'], '| partie :', kk[j]['section'])
print("photo gardée :", [s['title'] for s in kk if s.get('images')])
print("total chants :", sum(len(p['songs']) for p in r), "(attendu 424)")
