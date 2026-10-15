#!/usr/bin/env python3
"""Validate and build the content bundle of a language.

Usage:
  python3 tools/build_content.py --lang en --module m03     # validate one module's sources only
  python3 tools/build_content.py --lang en                  # validate everything and build
  python3 tools/build_content.py --lang en --allow-missing  # build even if some modules are missing

Outputs (full build):
  Content/build/<lang>.json                 bundle read by the Swift engine (ContentBundle)
  App/Resources/Content/<lang>.json         copy embedded in the iOS app (offline)
  supabase/seed/content_<lang>.sql          seed for the content tables
  Content/build/<lang>.report.txt           statistics and warnings

Exit code 1 on any validation error. See Content/SCHEMA.md for the format.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FORMAT_VERSION = 1

EXERCISE_TYPES = {"mcq", "fill_blank", "translation", "reorder", "match", "free_answer"}
LESSON_DISTRIBUTION = {"mcq": 2, "fill_blank": 2, "translation": 2, "reorder": 1, "match": 1, "free_answer": 2}
ERROR_CATEGORIES = {"vocabulary", "grammar", "conjugation", "verb_tense", "word_order", "spelling",
                    "preposition", "word_confusion", "instruction"}
POS = {"noun", "verb", "phrasal_verb", "adjective", "adverb", "pronoun", "article", "determiner", "preposition",
       "conjunction", "auxiliary", "modal", "interjection", "expression", "number"}
DIAG_TOPICS = {"vocabulary", "pronouns", "verbs", "present", "past", "future", "comprehension", "construction"}
DIAG_LEVEL = {1: 0, 2: 1, 3: 2, 4: 3, 5: 3, 6: 1, 7: 4, 8: 4}
SKILL = {"mcq": "recognition", "match": "recognition", "fill_blank": "recall", "reorder": "recall",
         "translation": "production", "free_answer": "production"}
VERB_FORMS = {"thirdPerson", "past", "pastParticiple", "ing"}
ALLOWED_FORMS = VERB_FORMS | {"plural", "comparative", "superlative"}


def slug(text: str) -> str:
    s = text.lower().replace("'", "").replace("’", "")
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


def words(sentence: str) -> list[str]:
    s = sentence.strip()
    s = re.sub(r"[.!?]+$", "", s)
    return [w for w in s.split() if w]


class Report:
    def __init__(self):
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def err(self, where: str, msg: str):
        self.errors.append(f"ERROR  {where}: {msg}")

    def warn(self, where: str, msg: str):
        self.warnings.append(f"WARN   {where}: {msg}")


def load_json(path: Path, rep: Report):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        rep.err(str(path.relative_to(ROOT)), "missing file")
    except json.JSONDecodeError as e:
        rep.err(str(path.relative_to(ROOT)), f"invalid JSON: {e}")
    return None


def nonempty(v) -> bool:
    return isinstance(v, str) and v.strip() != ""


def check_example(ex, where, rep, field="example"):
    if not (isinstance(ex, dict) and nonempty(ex.get("text")) and nonempty(ex.get("translation"))):
        rep.err(where, f"{field} must be {{text, translation}}")


def check_exercise(ex: dict, where: str, rep: Report, known_units: set[str], module: int, pool: str):
    t = ex.get("type")
    if t not in EXERCISE_TYPES:
        rep.err(where, f"unknown type {t!r}")
        return
    for f in ("instruction", "prompt", "explanation"):
        if not nonempty(ex.get(f)):
            rep.err(where, f"'{f}' required")
    if t != "match" and not nonempty(ex.get("tip")):
        rep.err(where, "'tip' required")
    if ex.get("promptLanguage") not in ("en", "fr"):
        rep.err(where, "promptLanguage must be 'en' or 'fr'")
    d = ex.get("difficulty")
    if not (isinstance(d, int) and 1 <= d <= 5):
        rep.err(where, "difficulty must be an int 1..5")
    units = ex.get("unitIds")
    if not (isinstance(units, list) and units):
        rep.err(where, "unitIds must be a non-empty list")
    else:
        for u in units:
            if u not in known_units:
                rep.err(where, f"unknown unit {u!r}")
    if t != "match":
        if ex.get("extraExample") is None:
            rep.err(where, "'extraExample' required")
        else:
            check_example(ex["extraExample"], where, rep, "extraExample")
    answer = ex.get("answer")
    accepted = ex.get("acceptedAnswers")
    if not isinstance(accepted, list) or not all(isinstance(a, str) for a in accepted):
        rep.err(where, "acceptedAnswers must be a list of strings")
        accepted = []
    if t != "match":
        if not nonempty(answer):
            rep.err(where, "'answer' required")
        elif answer not in accepted:
            rep.err(where, "acceptedAnswers must include answer")
    if len(set(a.strip().lower() for a in accepted)) != len(accepted):
        rep.warn(where, "duplicate acceptedAnswers")
    opts = ex.get("options")
    if t == "mcq":
        if not (isinstance(opts, list) and 3 <= len(opts) <= 4):
            rep.err(where, "mcq needs 3-4 options")
        elif answer not in opts:
            rep.err(where, "mcq answer must be one of the options")
        elif len(set(o.lower() for o in opts)) != len(opts):
            rep.err(where, "duplicate options")
    if t == "fill_blank":
        if ex.get("prompt", "").count("___") != 1:
            rep.err(where, "fill_blank prompt must contain exactly one '___'")
        if opts is not None:
            if not (isinstance(opts, list) and 3 <= len(opts) <= 4 and answer in opts):
                rep.err(where, "fill_blank options must be 3-4 and include the answer")
    if t == "reorder":
        tokens = ex.get("tokens")
        if not (isinstance(tokens, list) and len(tokens) >= 3):
            rep.err(where, "reorder needs >= 3 tokens")
        else:
            bag = collections.Counter(w.lower() for w in tokens)
            for a in accepted:
                if collections.Counter(w.lower() for w in words(a)) != bag:
                    rep.err(where, f"accepted answer {a!r} does not use exactly the tokens")
            if [w.lower() for w in tokens] == [w.lower() for w in words(answer or "")]:
                rep.warn(where, "tokens are already in the correct order")
    if t == "match":
        pairs = ex.get("pairs")
        if not (isinstance(pairs, list) and 3 <= len(pairs) <= 5):
            rep.err(where, "match needs 3-5 pairs")
        else:
            lefts = [p.get("left", "").lower() for p in pairs]
            rights = [p.get("right", "").lower() for p in pairs]
            if len(set(lefts)) != len(lefts) or len(set(rights)) != len(rights):
                rep.err(where, "match pairs must be unique on both sides")
            if not all(nonempty(p.get("left")) and nonempty(p.get("right")) for p in pairs):
                rep.err(where, "match pair needs left and right")
    if t == "free_answer":
        req = ex.get("requirements")
        if req is not None:
            if module < 3:
                rep.err(where, "open free_answer (requirements) only from module 3")
            mi = req.get("mustInclude")
            if mi is not None and not (isinstance(mi, list) and all(isinstance(x, list) and x for x in mi)):
                rep.err(where, "requirements.mustInclude must be a list of non-empty lists")
        if not accepted:
            rep.err(where, "free_answer needs acceptedAnswers")
    for i, p in enumerate(ex.get("errorPatterns") or []):
        pw = f"{where} errorPatterns[{i}]"
        if not (nonempty(p.get("equals")) or nonempty(p.get("contains"))):
            rep.err(pw, "needs 'equals' or 'contains'")
        if p.get("category") not in ERROR_CATEGORIES:
            rep.err(pw, f"invalid category {p.get('category')!r}")
        if not nonempty(p.get("feedback")):
            rep.err(pw, "feedback required")
        if nonempty(p.get("equals")) and any(p["equals"].strip().lower() == a.strip().lower() for a in accepted):
            rep.err(pw, "error pattern equals an accepted answer")
    if pool == "diagnostic":
        if ex.get("topic") not in DIAG_TOPICS:
            rep.err(where, f"diagnostic topic must be one of {sorted(DIAG_TOPICS)}")
        if ex.get("level") != DIAG_LEVEL[module]:
            rep.err(where, f"diagnostic level must be {DIAG_LEVEL[module]} for module {module}")
        if t not in ("mcq", "fill_blank", "reorder", "translation"):
            rep.err(where, "diagnostic types: mcq, fill_blank, reorder, translation")
        if t == "fill_blank" and not opts:
            rep.err(where, "diagnostic fill_blank needs options")


def finalize_exercise(ex: dict, pool: str, lesson_id: str | None) -> dict:
    out = dict(ex)
    out["pool"] = pool
    out["lessonId"] = lesson_id
    out["skill"] = SKILL[ex["type"]]
    out.setdefault("acceptedAnswers", [])
    if ex["type"] == "match" and not nonempty(out.get("answer")):
        out["answer"] = " ; ".join(f"{p['left']} = {p['right']}" for p in ex.get("pairs", []))
    return out


def validate_module(lang: str, cur: dict, mnum: int, rep: Report, known_units: set[str]):
    mdir = ROOT / "Content" / lang / "source" / f"m{mnum:02d}"
    tag = f"m{mnum:02d}"
    gunits = [u for u in cur["grammarUnits"] if u["module"] == mnum]
    vunits = [u for u in cur["vocabularyUnits"] if u["module"] == mnum]
    lessons = [l for l in cur["lessons"] if l["module"] == mnum]
    result = {"rules": {}, "dictionary": [], "exercises": [], "diagnostic": [], "assessment": []}

    # units.json
    data = load_json(mdir / "units.json", rep)
    if data is not None:
        by_id = {u.get("id"): u for u in data if isinstance(u, dict)}
        for g in gunits:
            w = f"{tag}/units.json {g['id']}"
            entry = by_id.get(g["id"])
            if not entry:
                rep.err(w, "missing rule")
                continue
            r = entry.get("rule") or {}
            for f in ("summary", "explanation"):
                if not nonempty(r.get(f)):
                    rep.err(w, f"rule.{f} required")
            ex = r.get("examples") or []
            if not 3 <= len(ex) <= 4:
                rep.err(w, "rule.examples: 3-4 expected")
            for e in ex:
                check_example(e, w, rep)
            ce = r.get("commonErrors") or []
            if not 2 <= len(ce) <= 3:
                rep.err(w, "rule.commonErrors: 2-3 expected")
            for c in ce:
                if not all(nonempty(c.get(k)) for k in ("wrong", "right", "why")):
                    rep.err(w, "commonError needs wrong/right/why")
            result["rules"][g["id"]] = r
        extra = set(by_id) - {g["id"] for g in gunits}
        for x in extra:
            rep.err(f"{tag}/units.json", f"unit {x!r} is not a grammar unit of this module")

    # dictionary.json
    data = load_json(mdir / "dictionary.json", rep)
    if data is not None:
        expected = {}
        for v in vunits:
            expected[v["dictionaryItemId"]] = v
        for g in gunits:
            for fw in g.get("functionWords", []):
                expected.setdefault(f"en.d.{slug(fw)}", {"title": fw, "id": None})
        seen = set()
        for i, item in enumerate(data):
            iid = item.get("id")
            w = f"{tag}/dictionary.json {iid or i}"
            if iid in seen:
                rep.err(w, "duplicate id")
            seen.add(iid)
            if iid not in expected:
                rep.warn(w, "entry not expected for this module (kept)")
            for f in ("word", "translation", "explanation", "partOfSpeech"):
                if not nonempty(item.get(f)):
                    rep.err(w, f"'{f}' required")
            if item.get("partOfSpeech") not in POS:
                rep.err(w, f"invalid partOfSpeech {item.get('partOfSpeech')!r}")
            exs = item.get("examples") or []
            if len(exs) < 2:
                rep.err(w, "2 examples expected")
            for e in exs:
                check_example(e, w, rep)
            ipa = item.get("ipa")
            if ipa is not None and not (isinstance(ipa, str) and ipa.startswith("/") and ipa.endswith("/")):
                rep.err(w, "ipa must be written between slashes")
            forms = item.get("forms") or {}
            if set(forms) - ALLOWED_FORMS:
                rep.err(w, f"unknown forms {sorted(set(forms) - ALLOWED_FORMS)}")
            exp = expected.get(iid)
            if exp and exp.get("id"):
                if item.get("unitId") != exp["id"]:
                    rep.err(w, f"unitId must be {exp['id']}")
                if exp.get("partOfSpeech") == "verb" and not VERB_FORMS <= set(forms):
                    rep.err(w, "verb needs forms thirdPerson, past, pastParticiple, ing")
            elif item.get("unitId") not in (None, ""):
                if item.get("unitId") not in known_units:
                    rep.err(w, "unknown unitId")
            for c in item.get("confusions") or []:
                if not (nonempty(c.get("word")) and nonempty(c.get("note"))):
                    rep.err(w, "confusion needs word and note")
        for iid in expected:
            if iid not in seen:
                rep.err(f"{tag}/dictionary.json", f"missing entry {iid}")
        result["dictionary"] = data

    # lessons
    for les in lessons:
        num = les["sequence"]
        path = mdir / "lessons" / f"l{num:02d}.json"
        w0 = f"{tag}/lessons/l{num:02d}.json"
        data = load_json(path, rep)
        if data is None:
            continue
        if data.get("lessonId") != les["id"]:
            rep.err(w0, f"lessonId must be {les['id']}")
        exs = data.get("exercises") or []
        if len(exs) != 10:
            rep.err(w0, f"exactly 10 exercises expected, found {len(exs)}")
        dist = collections.Counter(e.get("type") for e in exs)
        if dict(dist) != LESSON_DISTRIBUTION:
            rep.err(w0, f"type distribution {dict(dist)} != {LESSON_DISTRIBUTION}")
        ids = [e.get("id") for e in exs]
        exp_ids = [f"{les['id']}.e{i:02d}" for i in range(1, len(exs) + 1)]
        if sorted(i for i in ids if i) != sorted(exp_ids):
            rep.err(w0, f"exercise ids must be {exp_ids[0]}..{exp_ids[-1]}")
        primary_g = sum(1 for e in exs if (e.get("unitIds") or [None])[0] == les["grammarUnitId"])
        if primary_g < 6:
            rep.err(w0, f"grammar unit {les['grammarUnitId']} is primary in only {primary_g} exercises (>= 6)")
        all_units = {u for e in exs for u in (e.get("unitIds") or [])}
        for v in les["introduces"]:
            if v.startswith("en.v.") and v not in all_units:
                rep.err(w0, f"vocabulary {v} not used by any exercise")
        en_fr = sum(1 for e in exs if e.get("type") == "translation" and e.get("promptLanguage") == "en")
        if en_fr > 1:
            rep.err(w0, "at most one en->fr translation per lesson")
        open_free = sum(1 for e in exs if e.get("type") == "free_answer" and e.get("requirements"))
        if open_free > 1:
            rep.err(w0, "at most one open free_answer per lesson")
        prompts = [e.get("prompt", "").strip().lower() for e in exs]
        if len(set(prompts)) != len(prompts):
            rep.err(w0, "duplicate prompts in lesson")
        for e in exs:
            check_exercise(e, f"{w0} {e.get('id')}", rep, known_units, mnum, "lesson")
            if e.get("type") in EXERCISE_TYPES:
                result["exercises"].append(finalize_exercise(e, "lesson", les["id"]))

    for pool, fname in (("diagnostic", "diagnostic.json"), ("assessment", "assessment.json")):
        data = load_json(mdir / fname, rep)
        if data is None:
            continue
        w0 = f"{tag}/{fname}"
        if len(data) != 5:
            rep.err(w0, f"5 items expected, found {len(data)}")
        prefix = "en.diag" if pool == "diagnostic" else "en.assess"
        exp_ids = [f"{prefix}.m{mnum:02d}.{i:02d}" for i in range(1, len(data) + 1)]
        if sorted(e.get("id") or "" for e in data) != exp_ids:
            rep.err(w0, f"ids must be {exp_ids[0]}..{exp_ids[-1]}")
        if pool == "diagnostic":
            if sum(1 for e in data if e.get("type") == "translation") > 1:
                rep.err(w0, "at most one translation in diagnostic")
        else:
            recall = sum(1 for e in data if e.get("type") in ("translation", "free_answer")
                         or (e.get("type") == "fill_blank" and not e.get("options")))
            if recall < 3:
                rep.err(w0, "assessment needs >= 3 recall items without options")
        for e in data:
            check_exercise(e, f"{w0} {e.get('id')}", rep, known_units, mnum, pool)
            if e.get("type") in EXERCISE_TYPES:
                result[pool].append(finalize_exercise(e, pool, None))
    return result


def sql_str(v) -> str:
    if v is None:
        return "null"
    return "'" + str(v).replace("'", "''") + "'"


def sql_arr(values) -> str:
    if not values:
        return "'{}'::text[]"
    return "array[" + ",".join(sql_str(v) for v in values) + "]::text[]"


def sql_json(v) -> str:
    return sql_str(json.dumps(v, ensure_ascii=False)) + "::jsonb"


def build_seed(bundle: dict, lang: str, sha: str) -> str:
    v = bundle["contentVersion"]
    L = bundle["language"]
    out = [
        "-- Generated by tools/build_content.py. Do not edit by hand.",
        f"-- Content {lang} {v}",
        "begin;",
        "insert into public.languages (id, code, name, native_name, writing_direction, tts_locale, is_available) values "
        f"({sql_str(L['code'])}, {sql_str(L['code'])}, {sql_str(L['name'])}, {sql_str(L['nativeName'])}, "
        f"{sql_str(L['writingDirection'])}, {sql_str(L['ttsLocale'])}, true) "
        "on conflict (id) do update set name = excluded.name, native_name = excluded.native_name, "
        "writing_direction = excluded.writing_direction, tts_locale = excluded.tts_locale, is_available = excluded.is_available;",
    ]
    for u in bundle["units"]:
        data = {k: u[k] for k in ("rule", "functionWords", "translation", "partOfSpeech", "lessonId", "dictionaryItemId") if u.get(k) is not None}
        out.append(
            "insert into public.learning_units (id, language_id, kind, category, title, difficulty, prerequisites, module, data, content_version, deprecated) values "
            f"({sql_str(u['id'])}, {sql_str(lang)}, {sql_str(u['kind'])}, {sql_str(u['category'])}, {sql_str(u['title'])}, "
            f"{u['difficulty']}, {sql_arr(u['prerequisites'])}, {u['module']}, {sql_json(data)}, {sql_str(v)}, false) "
            "on conflict (id) do update set kind = excluded.kind, category = excluded.category, title = excluded.title, "
            "difficulty = excluded.difficulty, prerequisites = excluded.prerequisites, module = excluded.module, "
            "data = excluded.data, content_version = excluded.content_version, deprecated = excluded.deprecated;")
    for l in bundle["lessons"]:
        out.append(
            "insert into public.lessons (id, language_id, module, title, description, difficulty, sequence_order, grammar_unit_id, introduces, reviews, content_version, deprecated) values "
            f"({sql_str(l['id'])}, {sql_str(lang)}, {l['module']}, {sql_str(l['title'])}, {sql_str(l['description'])}, "
            f"{l['difficulty']}, {l['sequence']}, {sql_str(l['grammarUnitId'])}, {sql_arr(l['introduces'])}, {sql_arr(l['reviews'])}, {sql_str(v)}, false) "
            "on conflict (id) do update set module = excluded.module, title = excluded.title, description = excluded.description, "
            "difficulty = excluded.difficulty, sequence_order = excluded.sequence_order, grammar_unit_id = excluded.grammar_unit_id, "
            "introduces = excluded.introduces, reviews = excluded.reviews, content_version = excluded.content_version, deprecated = excluded.deprecated;")
    for e in bundle["exercises"] + bundle["diagnostic"] + bundle["assessment"]:
        out.append(
            "insert into public.exercises (id, language_id, lesson_id, learning_unit_id, unit_ids, exercise_type, pool, question, accepted_answers, explanation, difficulty, data, content_version, deprecated) values "
            f"({sql_str(e['id'])}, {sql_str(lang)}, {sql_str(e.get('lessonId'))}, {sql_str(e['unitIds'][0])}, {sql_arr(e['unitIds'])}, "
            f"{sql_str(e['type'])}, {sql_str(e['pool'])}, {sql_str(e['prompt'])}, {sql_arr(e['acceptedAnswers'])}, "
            f"{sql_str(e['explanation'])}, {e['difficulty']}, {sql_json(e)}, {sql_str(v)}, false) "
            "on conflict (id) do update set lesson_id = excluded.lesson_id, learning_unit_id = excluded.learning_unit_id, "
            "unit_ids = excluded.unit_ids, exercise_type = excluded.exercise_type, pool = excluded.pool, question = excluded.question, "
            "accepted_answers = excluded.accepted_answers, explanation = excluded.explanation, difficulty = excluded.difficulty, "
            "data = excluded.data, content_version = excluded.content_version, deprecated = excluded.deprecated;")
    for d in bundle["dictionary"]:
        out.append(
            "insert into public.dictionary_items (id, language_id, word, translation, definition, examples, pronunciation, data, content_version) values "
            f"({sql_str(d['id'])}, {sql_str(lang)}, {sql_str(d['word'])}, {sql_str(d['translation'])}, {sql_str(d['explanation'])}, "
            f"{sql_json(d.get('examples', []))}, {sql_str(d.get('ipa'))}, {sql_json(d)}, {sql_str(v)}) "
            "on conflict (id) do update set word = excluded.word, translation = excluded.translation, definition = excluded.definition, "
            "examples = excluded.examples, pronunciation = excluded.pronunciation, data = excluded.data, content_version = excluded.content_version;")
    out.append(f"update public.content_versions set is_current = false where language_id = {sql_str(lang)};")
    out.append(
        "insert into public.content_versions (language_id, version, bundle_path, sha256, is_current) values "
        f"({sql_str(lang)}, {sql_str(v)}, {sql_str(f'{lang}/{v}.json')}, {sql_str(sha)}, true);")
    out.append("commit;")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", default="en")
    ap.add_argument("--module", help="validate a single module, e.g. m03")
    ap.add_argument("--allow-missing", action="store_true", help="skip modules whose source folder is missing")
    args = ap.parse_args()

    lang = args.lang
    rep = Report()
    cur_path = ROOT / "Content" / lang / "curriculum.json"
    cur = json.loads(cur_path.read_text(encoding="utf-8"))
    known_units = {u["id"] for u in cur["grammarUnits"]} | {u["id"] for u in cur["vocabularyUnits"]}

    modules = [m["id"] for m in cur["modules"]]
    if args.module:
        modules = [int(args.module.lstrip("m"))]

    results = {}
    for m in modules:
        if args.allow_missing and not (ROOT / "Content" / lang / "source" / f"m{m:02d}").exists():
            rep.warn(f"m{m:02d}", "module missing (skipped)")
            continue
        results[m] = validate_module(lang, cur, m, rep, known_units)

    # Cross-module checks
    all_ex = [e for r in results.values() for e in r["exercises"] + r["diagnostic"] + r["assessment"]]
    ids = collections.Counter(e["id"] for e in all_ex)
    for i, n in ids.items():
        if n > 1:
            rep.err("bundle", f"duplicate exercise id {i}")
    prompts = collections.defaultdict(list)
    for e in all_ex:
        prompts[(e["type"], e["prompt"].strip().lower())].append(e["id"])
    for (_, p), lst in prompts.items():
        if len(lst) > 1:
            rep.warn("bundle", f"same prompt in {lst}: {p[:60]!r}")
    dict_ids = collections.Counter(d.get("id") for r in results.values() for d in r["dictionary"])
    for i, n in dict_ids.items():
        if n > 1:
            rep.err("bundle", f"duplicate dictionary id {i}")

    for w in rep.warnings:
        print(w)
    for e in rep.errors:
        print(e)
    n_ex = sum(len(r["exercises"]) for r in results.values())
    n_dict = sum(len(r["dictionary"]) for r in results.values())
    n_diag = sum(len(r["diagnostic"]) for r in results.values())
    n_ass = sum(len(r["assessment"]) for r in results.values())
    print(f"\nmodules={sorted(results)} exercises={n_ex} dictionary={n_dict} diagnostic={n_diag} "
          f"assessment={n_ass} errors={len(rep.errors)} warnings={len(rep.warnings)}")
    if rep.errors:
        sys.exit(1)
    if args.module:
        print("Module OK.")
        return

    rules = {k: v for r in results.values() for k, v in r["rules"].items()}
    units = []
    for g in cur["grammarUnits"]:
        u = {k: g[k] for k in ("id", "kind", "category", "title", "difficulty", "prerequisites", "module", "functionWords")}
        u["rule"] = rules.get(g["id"])
        units.append(u)
    for v in cur["vocabularyUnits"]:
        units.append({k: v[k] for k in ("id", "kind", "category", "title", "difficulty", "prerequisites", "module",
                                        "translation", "partOfSpeech", "lessonId", "dictionaryItemId")})
    built_modules = set(results)
    bundle = {
        "formatVersion": FORMAT_VERSION,
        "contentVersion": cur["contentVersion"],
        "language": cur["language"],
        "modules": cur["modules"],
        "units": units,
        "lessons": [l for l in cur["lessons"] if l["module"] in built_modules],
        "exercises": [e for m in sorted(results) for e in results[m]["exercises"]],
        "diagnostic": [e for m in sorted(results) for e in results[m]["diagnostic"]],
        "assessment": [e for m in sorted(results) for e in results[m]["assessment"]],
        "dictionary": [d for m in sorted(results) for d in results[m]["dictionary"]],
    }
    raw = json.dumps(bundle, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    sha = hashlib.sha256(raw).hexdigest()
    build_dir = ROOT / "Content" / "build"
    build_dir.mkdir(parents=True, exist_ok=True)
    (build_dir / f"{lang}.json").write_bytes(raw)
    app_dir = ROOT / "App" / "Resources" / "Content"
    app_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(build_dir / f"{lang}.json", app_dir / f"{lang}.json")
    seed_dir = ROOT / "supabase" / "seed"
    seed_dir.mkdir(parents=True, exist_ok=True)
    (seed_dir / f"content_{lang}.sql").write_text(build_seed(bundle, lang, sha), encoding="utf-8")

    by_type = collections.Counter(e["type"] for e in bundle["exercises"])
    report = [
        f"Content {lang} {bundle['contentVersion']} sha256={sha}",
        f"lessons={len(bundle['lessons'])} units={len(units)} (grammar={len(cur['grammarUnits'])}, vocabulary={len(cur['vocabularyUnits'])})",
        f"exercises={len(bundle['exercises'])} by type={dict(by_type)}",
        f"diagnostic={len(bundle['diagnostic'])} assessment={len(bundle['assessment'])} dictionary={len(bundle['dictionary'])}",
        f"accepted answers (total)={sum(len(e['acceptedAnswers']) for e in bundle['exercises'])}",
        f"error patterns (total)={sum(len(e.get('errorPatterns') or []) for e in bundle['exercises'])}",
        "", *rep.warnings,
    ]
    (build_dir / f"{lang}.report.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report[:6]))
    print(f"-> {build_dir / (lang + '.json')} ({len(raw) // 1024} KB), app copy, supabase/seed/content_{lang}.sql")


if __name__ == "__main__":
    main()
