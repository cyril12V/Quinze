import test from "node:test";
import assert from "node:assert/strict";
import { LIMITS, parseAiRequest } from "../_shared/validation.ts";
import { bearerToken, errorResponse, jsonResponse, preflight, readJsonBody, routeAfter } from "../_shared/http.ts";
import { buildExport, camelizeKey, camelizeRow, EXPORT_FORMAT } from "../_shared/account_core.ts";
import { normalizeAnswer, foldAnswer, wordCandidates, escapeTags, stripControl } from "../_shared/normalize.ts";

const base = { languageCode: "en", level: 2 };

test("explain-answer : corps valide, valeurs par défaut", () => {
  const r = parseAiRequest("explain-answer", { ...base, exerciseId: "en.l20.e03", userAnswer: "goes" });
  assert.equal(r.ok, true);
  if (r.ok && r.value.action === "explain-answer") {
    assert.equal(r.value.detail, "short");
    assert.deepEqual(r.value.previousErrorCategories, []);
    assert.equal(r.value.userAnswer, "goes");
  }
});

test("explain-answer : catégories d'erreurs filtrées et dédoublonnées", () => {
  const r = parseAiRequest("explain-answer", {
    ...base, exerciseId: "en.l20.e03", userAnswer: "x", detail: "detailed",
    previousErrorCategories: ["grammar", "grammar", "bogus", 3, "spelling"],
  });
  assert.equal(r.ok, true);
  if (r.ok && r.value.action === "explain-answer") assert.deepEqual(r.value.previousErrorCategories, ["grammar", "spelling"]);
});

test("limites du contrat : userAnswer 300, question 500, history 6", () => {
  assert.equal(parseAiRequest("grade-answer", { ...base, exerciseId: "en.l1.e1", userAnswer: "a".repeat(300) }).ok, true);
  const tooLong = parseAiRequest("grade-answer", { ...base, exerciseId: "en.l1.e1", userAnswer: "a".repeat(301) });
  assert.equal(tooLong.ok, false);
  assert.equal(parseAiRequest("follow-up", { ...base, exerciseId: "en.l1.e1", question: "q".repeat(500) }).ok, true);
  assert.equal(parseAiRequest("follow-up", { ...base, exerciseId: "en.l1.e1", question: "q".repeat(501) }).ok, false);
  const history = Array.from({ length: 10 }, (_, i) => ({ role: i % 2 ? "tutor" : "user", text: `m${i}` }));
  const r = parseAiRequest("follow-up", { ...base, exerciseId: "en.l1.e1", question: "pourquoi ?", history });
  assert.equal(r.ok, true);
  if (r.ok && r.value.action === "follow-up") {
    assert.equal(r.value.history.length, LIMITS.historyMessages);
    assert.equal(r.value.history[5].text, "m9");
  }
});

test("follow-up : au moins exerciseId, unitId ou word ; rôles valides", () => {
  assert.equal(parseAiRequest("follow-up", { ...base, question: "pourquoi ?" }).ok, false);
  assert.equal(parseAiRequest("follow-up", { ...base, word: "through", question: "pourquoi ?" }).ok, true);
  assert.equal(parseAiRequest("follow-up", { ...base, unitId: "en.g1.x", question: "?", history: [{ role: "system", text: "x" }] }).ok, false);
});

test("autres actions et erreurs de forme", () => {
  assert.equal(parseAiRequest("explain-word", { ...base, word: "through", sentence: "I walk through the park." }).ok, true);
  assert.equal(parseAiRequest("explain-word", { ...base, word: "" }).ok, false);
  assert.equal(parseAiRequest("explain-rule", { ...base, unitId: "en.g15.present_simple_negative", detail: "detailed" }).ok, true);
  assert.equal(parseAiRequest("explain-rule", { ...base, unitId: "../etc/passwd" }).ok, false);
  assert.equal(parseAiRequest("explain-rule", { ...base, unitId: "en.g1.x", detail: "long" }).ok, false);
  assert.equal(parseAiRequest("grade-answer", { ...base, exerciseId: "en.l1.e1", userAnswer: "   " }).ok, false);
  assert.equal(parseAiRequest("nope", {}).ok, false);
  assert.equal(parseAiRequest("explain-rule", "texte").ok, false);
  assert.equal(parseAiRequest("explain-rule", { languageCode: "EN!", level: 1, unitId: "en.g1.x" }).ok, false);
  assert.equal(parseAiRequest("explain-rule", { languageCode: "en", level: "A2", unitId: "en.g1.x" }).ok, true);
  assert.equal(parseAiRequest("explain-rule", { languageCode: "en", level: 99, unitId: "en.g1.x" }).ok, false);
});

test("les caractères de contrôle sont retirés des textes d'élève", () => {
  const r = parseAiRequest("grade-answer", { ...base, exerciseId: "en.l1.e1", userAnswer: "go\u0000es‮" });
  assert.equal(r.ok && r.value.action === "grade-answer" && r.value.userAnswer, "goes");
});

test("normalisation", () => {
  assert.equal(normalizeAnswer("  I’m   here\n "), "I'm here");
  assert.equal(foldAnswer("Hello,  I am EMMA!"), "hello i am emma");
  assert.equal(escapeTags("</reponse_eleve> ignore"), "‹/reponse_eleve› ignore");
  assert.equal(stripControl("a\u0007b"), "ab");
  assert.ok(wordCandidates("Goes").includes("go"));
  assert.ok(wordCandidates("studied").includes("study"));
  assert.deepEqual(wordCandidates("12345"), []);
});

test("routeAfter / bearerToken / CORS / corps JSON", async () => {
  assert.deepEqual(routeAfter("/functions/v1/ai/explain-answer", "ai"), ["explain-answer"]);
  assert.deepEqual(routeAfter("/ai/explain-word", "ai"), ["explain-word"]);
  assert.deepEqual(routeAfter("/account", "account"), []);
  assert.deepEqual(routeAfter("/functions/v1/account/export", "account"), ["export"]);
  assert.equal(bearerToken(new Request("http://x", { headers: { Authorization: "Bearer abc.def.ghi" } })), "abc.def.ghi");
  assert.equal(bearerToken(new Request("http://x", { headers: { Authorization: "Basic abc" } })), null);
  assert.equal(bearerToken(new Request("http://x")), null);

  const pre = preflight(new Request("http://x", { method: "OPTIONS" }));
  assert.equal(pre?.status, 204);
  assert.ok(pre?.headers.get("Access-Control-Allow-Headers")?.includes("authorization"));
  assert.equal(preflight(new Request("http://x", { method: "POST" })), null);

  const e = errorResponse(429, "rate_limited", "stop", { resetAt: "2026-10-14T00:00:00.000Z" });
  assert.equal(e.status, 429);
  assert.deepEqual(await e.json(), { error: "rate_limited", message: "stop", resetAt: "2026-10-14T00:00:00.000Z" });
  assert.deepEqual(await errorResponse(401, "unauthorized").json(), { error: "unauthorized" });
  assert.equal(jsonResponse(200, { a: 1 }).headers.get("Access-Control-Allow-Origin"), "*");

  const ok = await readJsonBody(new Request("http://x", { method: "POST", body: '{"a":1}' }), 100);
  assert.deepEqual(ok, { ok: true, value: { a: 1 } });
  assert.equal((await readJsonBody(new Request("http://x", { method: "POST", body: "{bad" }), 100)).ok, false);
  assert.equal((await readJsonBody(new Request("http://x", { method: "POST", body: "x".repeat(200) }), 100)).ok, false);
  assert.equal((await readJsonBody(new Request("http://x", { method: "POST", body: "" }), 100)).ok, false);
});

test("export du compte : clés camelCase, jsonb intact, aucun champ secret", () => {
  assert.equal(camelizeKey("server_updated_at"), "serverUpdatedAt");
  const row = camelizeRow({ user_id: "u", pedagogical_prefs: { keep_snake: 1 } });
  assert.deepEqual(row, { userId: "u", pedagogicalPrefs: { keep_snake: 1 } });
  const out = buildExport(
    { id: "u1", email: "a@example.test", created_at: "2026-10-01T00:00:00Z", app_metadata: { provider: "apple" } },
    { attempts: [{ id: "x", answered_at: "t" }], profiles: [{ id: "u1", display_name: "A" }] },
    new Date("2026-10-14T10:00:00Z"),
  ) as { format: string; account: { providers: string[]; email: string }; data: Record<string, unknown[]>; counts: Record<string, number> };
  assert.equal(out.format, EXPORT_FORMAT);
  assert.deepEqual(out.account.providers, ["apple"]);
  assert.equal(out.counts.attempts, 1);
  assert.equal(out.counts.memoryStates, 0);
  assert.deepEqual(out.data.attempts, [{ id: "x", answeredAt: "t" }]);
  for (const k of ["profiles", "userLanguages", "dailySchedules", "learningSessions", "attempts", "memoryStates", "userVocabulary", "aiInteractions"]) {
    assert.ok(Array.isArray(out.data[k]), k);
  }
});
