// Test Deno uniquement (import npm:) : vérifie les requêtes PostgREST produites par ai_store.ts
// avec le VRAI supabase-js et un fetch simulé.   deno test --allow-read supabase/functions/_tests/ai_store.deno_test.ts
import { createClient } from "npm:@supabase/supabase-js@2";
import nodeAssert from "node:assert/strict";
import { makeAiDeps } from "../_shared/ai_store.ts";
import { DICT, EXERCISE, UNIT } from "./fixtures.ts";

const assert = (c: unknown, m?: string) => nodeAssert.ok(c, m);
const assertEquals = (a: unknown, b: unknown, m?: string) => nodeAssert.deepEqual(a, b, m);

interface Req {
  method: string;
  url: URL;
  headers: Headers;
  body: string;
}

function setup(routes: (r: Req) => { status?: number; json?: unknown; headers?: Record<string, string> }) {
  const seen: Req[] = [];
  const fetchImpl = async (input: Request | string | URL, init?: RequestInit): Promise<Response> => {
    const req = new Request(input, init);
    const r: Req = { method: req.method, url: new URL(req.url), headers: req.headers, body: await req.text() };
    seen.push(r);
    const out = routes(r);
    const wantsObject = (r.headers.get("accept") ?? "").includes("pgrst.object");
    let payload = out.json;
    if (wantsObject && Array.isArray(payload)) payload = payload[0];
    const hasBody = req.method !== "HEAD" && payload !== undefined;
    return new Response(hasBody ? JSON.stringify(payload) : null, {
      status: out.status ?? 200,
      headers: { "content-type": "application/json", ...(out.headers ?? {}) },
    });
  };
  const sb = createClient("http://localhost:54321", "service-key", { global: { fetch: fetchImpl as typeof fetch }, auth: { persistSession: false } });
  const deps = makeAiDeps(sb, { model: "claude-haiku-5-5", dailyQuota: 40, monthlyBudget: 1000, timeoutMs: 1000 }, "key");
  return { seen, deps };
}

Deno.test("loadContent : exercice + unités rechargés par identifiant, filtrés par langue", async () => {
  const { seen, deps } = setup((r) => {
    const p = r.url.pathname;
    if (p.endsWith("/languages")) return { json: [{ id: "en", is_available: true }] };
    if (p.endsWith("/exercises")) return { json: [EXERCISE] };
    if (p.endsWith("/learning_units")) return { json: [UNIT] };
    return { status: 404, json: { message: "?" } };
  });
  const res = await deps.loadContent({ action: "grade-answer", languageCode: "en", level: 2, exerciseId: EXERCISE.id, userAnswer: "she" });
  assert(res.ok);
  if (res.ok) {
    assertEquals(res.ctx.exercise?.id, EXERCISE.id);
    assertEquals(res.ctx.units.map((u) => u.id), [UNIT.id]);
    assertEquals(res.ctx.contentVersion, "1.0.0");
    assertEquals(res.ctx.languageId, "en");
  }
  const ex = seen.find((r) => r.url.pathname.endsWith("/exercises"))!;
  assertEquals(ex.url.searchParams.get("id"), "eq.en.l01.e01");
  assertEquals(ex.url.searchParams.get("language_id"), "eq.en");
  assertEquals(seen.find((r) => r.url.pathname.endsWith("/languages"))!.url.searchParams.get("code"), "eq.en");
  assertEquals(seen.find((r) => r.url.pathname.endsWith("/learning_units"))!.url.searchParams.get("id"), "in.(en.g01.subject_pronouns)");
});

Deno.test("loadContent : exercice ou langue inconnus -> échec propre", async () => {
  const { deps } = setup((r) => (r.url.pathname.endsWith("/languages") ? { json: [{ id: "en", is_available: true }] } : { json: [] }));
  const res = await deps.loadContent({ action: "grade-answer", languageCode: "en", level: 2, exerciseId: "en.zz.e1", userAnswer: "x" });
  assertEquals(res.ok, false);
  const none = setup(() => ({ json: [] })).deps;
  assertEquals((await none.loadContent({ action: "explain-rule", languageCode: "en", level: 2, unitId: "en.g1.x", detail: "short" })).ok, false);
});

Deno.test("loadContent : mot -> candidats ilike et choix de la forme exacte", async () => {
  const { seen, deps } = setup((r) => {
    if (r.url.pathname.endsWith("/languages")) return { json: [{ id: "en", is_available: true }] };
    if (r.url.pathname.endsWith("/dictionary_items")) return { json: [{ ...DICT, word: "go" }, { ...DICT, id: "x", word: "goes" }] };
    return { json: [] };
  });
  const res = await deps.loadContent({ action: "explain-word", languageCode: "en", level: 1, word: "Goes", sentence: null, detail: "short" });
  assert(res.ok && res.ctx.dictItem?.word === "goes");
  const or = seen.find((r) => r.url.pathname.endsWith("/dictionary_items"))!.url.searchParams.get("or")!;
  assertEquals(or, '(word.ilike."goes",word.ilike."go",word.ilike."goe")');
});

Deno.test("quota : requêtes de comptage (utilisateur, global) et réservation sans texte d'élève", async () => {
  const { seen, deps } = setup((r) => {
    if (r.method === "HEAD") return { headers: { "content-range": "*/7" } };
    if (r.method === "GET") return { json: [{ created_at: "2026-10-14T09:00:00.000Z" }, { created_at: "2026-10-14T09:30:00+00:00" }] };
    if (r.method === "POST") return { status: 201, json: [{ id: "abc" }] };
    return { json: [] };
  });
  const since = Date.parse("2026-10-13T10:00:00Z");
  const usage = await deps.recentQuotaUsage("user-1", since);
  assertEquals(usage, [Date.parse("2026-10-14T09:00:00Z"), Date.parse("2026-10-14T09:30:00Z")]);
  const q = seen.at(-1)!.url.searchParams;
  assertEquals(q.get("user_id"), "eq.user-1");
  assertEquals(q.get("response_status"), "in.(ok,fallback)");
  assertEquals(q.get("model"), "not.is.null");
  assertEquals(q.get("created_at"), "gte.2026-10-13T10:00:00.000Z");

  assertEquals(await deps.monthlyUsage(Date.parse("2026-10-01T00:00:00Z")), 7);
  assertEquals(seen.at(-1)!.method, "HEAD");

  const id = await deps.startInteraction({ userId: "user-1", requestType: "explain-answer", exerciseId: EXERCISE.id }, "claude-haiku-5-5");
  assertEquals(id, "abc");
  const ins = JSON.parse(seen.find((r) => r.method === "POST" && r.url.pathname.endsWith("/ai_interactions"))!.body);
  assertEquals(Object.keys(ins).sort(), ["exercise_id", "model", "request_type", "response_status", "user_id"]);
});

Deno.test("cache : lecture par RPC ai_cache_get, écriture en upsert ignore-duplicates", async () => {
  const { seen, deps } = setup((r) => {
    if (r.url.pathname.endsWith("/rpc/ai_cache_get")) return { json: { text: "t", examples: [] } };
    return { status: 201 };
  });
  const key = "a".repeat(64);
  assertEquals(await deps.cacheGet(key), { text: "t", examples: [] });
  assertEquals(JSON.parse(seen[0].body), { p_cache_key: key });
  await deps.cachePut(key, "explain-rule", { text: "t", examples: [] }, "m");
  const put = seen.at(-1)!;
  assertEquals(put.url.pathname.endsWith("/ai_cache"), true);
  assert((put.headers.get("prefer") ?? "").includes("resolution=ignore-duplicates"));
  assertEquals(put.url.searchParams.get("on_conflict"), "cache_key");
  const miss = setup(() => ({ json: null })).deps;
  assertEquals(await miss.cacheGet(key), null);
  const broken = setup(() => ({ status: 500, json: { message: "boom" } })).deps;
  assertEquals(await broken.cacheGet(key), null, "une panne du cache n'est pas fatale");
});
