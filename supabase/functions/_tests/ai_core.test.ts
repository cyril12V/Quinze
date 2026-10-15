import test from "node:test";
import assert from "node:assert/strict";
import { handleAi } from "../_shared/ai_core.ts";
import type { AiDeps, InteractionPatch, InteractionRow } from "../_shared/ai_core.ts";
import type { ModelResult } from "../_shared/anthropic.ts";
import type { AiBody, AiRequest, ContentContext, InteractionStatus } from "../_shared/types.ts";
import { ctxFor, DICT, EXERCISE } from "./fixtures.ts";

const USER = "11111111-2222-4333-8444-555555555555";
const NOW = new Date("2026-10-14T10:00:00.000Z");

interface Interaction {
  id: string;
  userId: string;
  requestType: string;
  exerciseId: string | null;
  status: InteractionStatus;
  model: string | null;
  inputTokens?: number | null;
  outputTokens?: number | null;
  latencyMs?: number | null;
  at: number;
}

function modelOk(text: string): ModelResult {
  return { ok: true, text, model: "claude-haiku-5-5", inputTokens: 200, outputTokens: 50, stopReason: "end_turn", latencyMs: 812, attempts: 1 };
}

function setup(opts: { quota?: number; budget?: number; model?: (n: number) => ModelResult; seedUsage?: number; extraUsageAfterStart?: number } = {}) {
  const interactions: Interaction[] = [];
  const cache = new Map<string, AiBody>();
  const modelCalls: Array<{ system: string; user: string; model: string; maxTokens: number }> = [];
  const logs: Array<{ event: string; data: Record<string, unknown> }> = [];
  let seq = 0;
  for (let i = 0; i < (opts.seedUsage ?? 0); i++) {
    interactions.push({ id: `seed${i}`, userId: USER, requestType: "explain-rule", exerciseId: null, status: "ok", model: "m", at: NOW.getTime() - (i + 1) * 3600_000 });
  }
  const consuming = (i: Interaction) => (i.status === "ok" || i.status === "fallback") && i.model !== null;
  const deps: AiDeps = {
    config: { model: "claude-haiku-5-5", dailyQuota: opts.quota ?? 40, monthlyBudget: opts.budget ?? 200_000, timeoutMs: 20_000 },
    now: () => NOW,
    async loadContent(req: AiRequest) {
      const id = "exerciseId" in req ? req.exerciseId : null;
      if (id && id !== EXERCISE.id) return { ok: false as const, message: `Exercice inconnu : ${id}.` };
      let ctx: ContentContext;
      if (req.action === "explain-rule") ctx = ctxFor("rule");
      else if (req.action === "explain-word") ctx = req.word.toLowerCase() === "hello" ? ctxFor("word") : { ...ctxFor("word"), dictItem: null };
      else ctx = ctxFor("exercise");
      return { ok: true as const, ctx };
    },
    async cacheGet(key) {
      const v = cache.get(key);
      return v ? (JSON.parse(JSON.stringify(v)) as Record<string, unknown>) : null;
    },
    async cachePut(key, _t, body) {
      cache.set(key, body);
    },
    async recentQuotaUsage(userId, sinceMs) {
      const base = interactions.filter((i) => i.userId === userId && consuming(i) && i.at >= sinceMs).map((i) => i.at);
      return base;
    },
    async monthlyUsage(sinceMs) {
      return interactions.filter((i) => consuming(i) && i.at >= sinceMs).length + (opts.budget !== undefined && opts.budget <= 0 ? 1 : 0);
    },
    async startInteraction(row: InteractionRow, model) {
      const id = `i${++seq}`;
      interactions.push({ id, userId: row.userId, requestType: row.requestType, exerciseId: row.exerciseId, status: "ok", model, at: NOW.getTime() });
      for (let k = 0; k < (opts.extraUsageAfterStart ?? 0); k++) {
        interactions.push({ id: `race${k}`, userId: row.userId, requestType: row.requestType, exerciseId: null, status: "ok", model, at: NOW.getTime() });
      }
      return id;
    },
    async finishInteraction(id, patch: InteractionPatch) {
      const i = interactions.find((x) => x.id === id)!;
      Object.assign(i, { status: patch.status, model: patch.model ?? null, inputTokens: patch.inputTokens ?? null, outputTokens: patch.outputTokens ?? null, latencyMs: patch.latencyMs ?? null });
    },
    async dropInteraction(id) {
      const idx = interactions.findIndex((x) => x.id === id);
      if (idx >= 0) interactions.splice(idx, 1);
    },
    async logInteraction(row, status, latencyMs) {
      interactions.push({ id: `l${++seq}`, userId: row.userId, requestType: row.requestType, exerciseId: row.exerciseId, status, model: null, latencyMs, at: NOW.getTime() });
    },
    async callModel(call) {
      modelCalls.push(call);
      return (opts.model ?? (() => modelOk('{"text":"Explication de secours.","examples":[{"text":"She is here.","translation":"Elle est ici."}]}')))(modelCalls.length);
    },
    log: (event, data) => {
      logs.push({ event, data });
    },
  };
  return { deps, interactions, cache, modelCalls, logs };
}

const explainBody = { languageCode: "en", level: 2, exerciseId: EXERCISE.id, userAnswer: "he", detail: "short", previousErrorCategories: [] };

test("400 : corps invalide ou exercice inconnu, aucun appel au fournisseur", async () => {
  const s = setup();
  const bad = await handleAi(USER, "explain-answer", { languageCode: "en" }, s.deps);
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, "bad_request");
  assert.equal(typeof bad.body.message, "string");
  const unknown = await handleAi(USER, "explain-answer", { ...explainBody, exerciseId: "en.zz.e99" }, s.deps);
  assert.equal(unknown.status, 400);
  assert.equal((await handleAi(USER, "nope", explainBody, s.deps)).status, 400);
  assert.equal(s.modelCalls.length, 0);
  assert.equal(s.interactions.length, 0);
});

test("explain-answer : appel IA, réponse au format du contrat, quota décompté, journal sans texte", async () => {
  const s = setup();
  const r = await handleAi(USER, "explain-answer", explainBody, s.deps);
  assert.equal(r.status, 200);
  assert.deepEqual(Object.keys(r.body).sort(), ["examples", "remainingQuota", "source", "text"]);
  assert.equal(r.body.source, "ai");
  assert.equal(r.body.remainingQuota, 39);
  assert.deepEqual(r.body.examples, [{ text: "She is here.", translation: "Elle est ici." }]);

  assert.equal(s.modelCalls.length, 1);
  const c = s.modelCalls[0];
  assert.equal(c.model, "claude-haiku-5-5");
  assert.match(c.system, /UNIQUEMENT sur le contenu validé/);
  assert.ok(c.user.includes("<contenu_valide>") && c.user.includes("Réponse attendue : she"), "le contenu validé vient de la base");
  assert.ok(c.user.includes("<reponse_eleve>he</reponse_eleve>"));
  assert.ok(!c.user.includes(USER) && !c.user.includes("@"), "aucun identifiant ni e-mail envoyé au fournisseur");

  assert.equal(s.interactions.length, 1);
  const log = s.interactions[0];
  assert.deepEqual({ status: log.status, model: log.model, in: log.inputTokens, out: log.outputTokens, lat: log.latencyMs, ex: log.exerciseId, type: log.requestType },
    { status: "ok", model: "claude-haiku-5-5", in: 200, out: 50, lat: 812, ex: EXERCISE.id, type: "explain-answer" });
  assert.ok(!JSON.stringify([...s.interactions, ...s.logs]).includes("\"he\""), "ni réponse ni texte d'élève dans les journaux");
  assert.equal(s.cache.size, 1);
});

test("cache : la même demande est servie gratuitement, sans appel ni quota", async () => {
  const s = setup();
  await handleAi(USER, "explain-answer", explainBody, s.deps);
  const again = await handleAi(USER, "explain-answer", explainBody, s.deps);
  assert.equal(again.status, 200);
  assert.equal(again.body.source, "cache");
  assert.equal(again.body.remainingQuota, 39, "le cache ne consomme pas de quota");
  assert.equal(s.modelCalls.length, 1);
  assert.deepEqual(s.interactions.map((i) => i.status), ["ok", "cached"]);
  const other = await handleAi(USER, "explain-answer", { ...explainBody, userAnswer: "it" }, s.deps);
  assert.equal(other.body.source, "ai");
  const detailed = await handleAi(USER, "explain-answer", { ...explainBody, detail: "detailed" }, s.deps);
  assert.equal(detailed.body.source, "ai", "detail dans la clé");
  assert.equal(s.modelCalls.length, 3);
});

test("follow-up : jamais mis en cache", async () => {
  const s = setup();
  const body = { languageCode: "en", level: 2, exerciseId: EXERCISE.id, previousExplanation: "She = elle.", history: [], question: "et pour un homme ?" };
  assert.equal((await handleAi(USER, "follow-up", body, s.deps)).body.source, "ai");
  assert.equal((await handleAi(USER, "follow-up", body, s.deps)).body.source, "ai");
  assert.equal(s.modelCalls.length, 2);
  assert.equal(s.cache.size, 0);
  assert.ok(s.modelCalls[0].user.includes("<question_eleve>et pour un homme ?</question_eleve>"));
});

test("grade-answer : verdict structuré, catégorie, mis en cache", async () => {
  const s = setup({ model: () => modelOk('{"verdict":"incorrect","errorCategory":"word_confusion","explanation":"It sert pour une chose.","correctedAnswer":"she"}') });
  const body = { languageCode: "en", level: 2, exerciseId: EXERCISE.id, userAnswer: "it" };
  const r = await handleAi(USER, "grade-answer", body, s.deps);
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { verdict: "incorrect", errorCategory: "word_confusion", explanation: "It sert pour une chose.", correctedAnswer: "she", source: "ai", remainingQuota: 39 });
  const again = await handleAi(USER, "grade-answer", body, s.deps);
  assert.equal(again.body.source, "cache");
  assert.equal(again.body.verdict, "incorrect");
});

test("grade-answer : sortie inexploitable -> repli déterministe (compté au quota), pas de cache", async () => {
  const s = setup({ model: () => modelOk("Je pense que c'est faux, mais je ne sais pas.") });
  const r = await handleAi(USER, "grade-answer", { languageCode: "en", level: 2, exerciseId: EXERCISE.id, userAnswer: "it" }, s.deps);
  assert.equal(r.status, 200);
  assert.equal(r.body.source, "fallback");
  assert.equal(r.body.verdict, "incorrect");
  assert.equal(r.body.errorCategory, "word_confusion");
  assert.equal(r.body.correctedAnswer, "she");
  assert.equal(s.cache.size, 0);
  assert.equal(s.interactions[0].status, "fallback");
  assert.equal(s.interactions[0].model, "claude-haiku-5-5");
});

test("quota de 24 h glissantes : 429 avec resetAt, le cache reste servi", async () => {
  const s = setup({ quota: 3 });
  await handleAi(USER, "explain-answer", explainBody, s.deps);
  s.interactions.push(
    { id: "a", userId: USER, requestType: "explain-rule", exerciseId: null, status: "ok", model: "m", at: NOW.getTime() - 20 * 3600_000 },
    { id: "b", userId: USER, requestType: "explain-rule", exerciseId: null, status: "ok", model: "m", at: NOW.getTime() - 2 * 3600_000 },
  );
  const blocked = await handleAi(USER, "explain-answer", { ...explainBody, userAnswer: "it" }, s.deps);
  assert.equal(blocked.status, 429);
  assert.equal(blocked.body.error, "rate_limited");
  assert.equal(typeof blocked.body.message, "string");
  assert.equal(blocked.body.resetAt, new Date(NOW.getTime() - 20 * 3600_000 + 24 * 3600_000).toISOString());
  assert.equal(s.modelCalls.length, 1);
  assert.equal(s.interactions.at(-1)?.status, "rate_limited");
  const cached = await handleAi(USER, "explain-answer", explainBody, s.deps);
  assert.equal(cached.status, 200);
  assert.equal(cached.body.source, "cache");
  assert.equal(cached.body.remainingQuota, 0);
  // Les interactions de plus de 24 h ne comptent plus.
  const s2 = setup({ quota: 2 });
  s2.interactions.push({ id: "old", userId: USER, requestType: "explain-rule", exerciseId: null, status: "ok", model: "m", at: NOW.getTime() - 25 * 3600_000 });
  assert.equal((await handleAi(USER, "explain-answer", explainBody, s2.deps)).status, 200);
});

test("quota : dernière requête simultanée écartée (réservation puis recomptage)", async () => {
  const s = setup({ quota: 1, extraUsageAfterStart: 1 });
  const r = await handleAi(USER, "explain-answer", explainBody, s.deps);
  assert.equal(r.status, 429);
  assert.equal(s.modelCalls.length, 0, "aucun appel payant après dépassement");
  assert.ok(!s.interactions.some((i) => i.id === "i1"), "la réservation est retirée");
});

test("plafond mensuel global : 503 avec réponse de secours, aucun appel", async () => {
  const s = setup({ budget: 2 });
  for (let i = 0; i < 2; i++) s.interactions.push({ id: `m${i}`, userId: "other", requestType: "explain-rule", exerciseId: null, status: "ok", model: "m", at: new Date("2026-10-03T00:00:00Z").getTime() });
  s.interactions.push({ id: "prev", userId: "other", requestType: "explain-rule", exerciseId: null, status: "ok", model: "m", at: new Date("2026-09-30T23:00:00Z").getTime() });
  const r = await handleAi(USER, "explain-answer", { ...explainBody, userAnswer: "it" }, s.deps);
  assert.equal(r.status, 503);
  assert.equal(r.body.error, "unavailable");
  const fb = r.body.fallback as Record<string, unknown>;
  assert.equal(fb.source, "fallback");
  assert.ok(String(fb.text).includes("La réponse attendue est « she »"));
  assert.equal(s.modelCalls.length, 0);
});

test("fournisseur en panne : 503 unavailable + fallback issu du contenu, non compté au quota", async () => {
  const s = setup({ model: () => ({ ok: false, kind: "http", status: 529, latencyMs: 20000, attempts: 2 }) });
  const r = await handleAi(USER, "explain-answer", explainBody, s.deps);
  assert.equal(r.status, 503);
  assert.equal(r.body.error, "unavailable");
  assert.equal(typeof r.body.message, "string");
  const fb = r.body.fallback as { source: string; text: string; examples: unknown[]; remainingQuota: number };
  assert.equal(fb.source, "fallback");
  assert.ok(fb.text.includes("He veut dire « il »"), "retour validé de l'erreur connue");
  assert.equal(fb.remainingQuota, 39);
  assert.equal(s.interactions[0].status, "error");
  assert.equal(s.cache.size, 0);
  assert.equal(s.logs[0].event, "ai_provider_error");
  // Un nouvel essai n'a pas consommé de quota.
  const q = await handleAi(USER, "explain-answer", explainBody, { ...s.deps, callModel: async () => modelOk('{"text":"ok","examples":[]}') });
  assert.equal(q.body.remainingQuota, 39);
});

test("clé API absente : 503 avec repli (aucune exception)", async () => {
  const s = setup({ model: () => ({ ok: false, kind: "no_key", latencyMs: 0, attempts: 0 }) });
  const r = await handleAi(USER, "explain-rule", { languageCode: "en", level: 1, unitId: "en.g01.subject_pronouns", detail: "short" }, s.deps);
  assert.equal(r.status, 503);
  assert.ok(String((r.body.fallback as { text: string }).text).includes("Les pronoms sujets"));
});

test("explain-word : mot du dictionnaire via l'IA ; mot inconnu = repli sans appel ni quota", async () => {
  const s = setup();
  const known = await handleAi(USER, "explain-word", { languageCode: "en", level: 1, word: "hello", sentence: "Hello, Anna!", detail: "short" }, s.deps);
  assert.equal(known.body.source, "ai");
  assert.ok(s.modelCalls[0].user.includes(DICT.translation) && s.modelCalls[0].user.includes("<phrase_eleve>Hello, Anna!</phrase_eleve>"));
  const unknown = await handleAi(USER, "explain-word", { languageCode: "en", level: 1, word: "zzyzx", detail: "short" }, s.deps);
  assert.equal(unknown.status, 200);
  assert.equal(unknown.body.source, "fallback");
  assert.ok(String(unknown.body.text).includes("dictionnaire validé"));
  assert.equal(unknown.body.remainingQuota, 39);
  assert.equal(s.modelCalls.length, 1);
  assert.equal(s.interactions.at(-1)?.model, null);
});

test("erreur inattendue (base indisponible) : 503 avec repli, jamais de 500", async () => {
  const s = setup();
  const deps: AiDeps = { ...s.deps, recentQuotaUsage: async () => { throw new Error("connection refused"); } };
  const r = await handleAi(USER, "explain-answer", explainBody, deps);
  assert.equal(r.status, 503);
  assert.equal(r.body.error, "unavailable");
  assert.ok((r.body.fallback as { text: string }).text.length > 10);
  assert.equal(s.modelCalls.length, 0);
});

test("explain-rule : texte brut du modèle accepté, prompt ancré sur la règle de l'unité", async () => {
  const s = setup({ model: () => modelOk("Les pronoms sujets remplacent la personne dont on parle, au début de la phrase.") });
  const r = await handleAi(USER, "explain-rule", { languageCode: "en", level: 3, unitId: "en.g01.subject_pronouns", detail: "detailed" }, s.deps);
  assert.equal(r.body.source, "ai");
  assert.deepEqual(r.body.examples, []);
  assert.ok(s.modelCalls[0].user.includes("Règle (résumé)"));
  assert.equal(s.modelCalls[0].maxTokens, 1000);
});
