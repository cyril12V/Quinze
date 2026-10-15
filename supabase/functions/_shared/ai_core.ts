// Orchestration d'une requête `ai` : validation -> contenu validé -> cache -> quotas ->
// fournisseur -> analyse -> repli. Toutes les dépendances (base, fournisseur, horloge) sont
// injectées : ce module n'utilise ni Deno ni le réseau et se teste avec des faux.

import type { ModelResult } from "./anthropic.ts";
import { cacheKey, isCacheable } from "./cache_key.ts";
import { buildFallback, emptyContext, MSG_AI_UNAVAILABLE } from "./fallback.ts";
import { normalizeAnswer } from "./normalize.ts";
import { parseExplanation, parseGrade } from "./parsing.ts";
import { buildUserPrompt, detailOf, maxTokensFor, SYSTEM_PROMPT } from "./prompts.ts";
import { DAY_MS, evaluateQuota, monthStartUtc } from "./quota.ts";
import type { AiAction, AiBody, AiRequest, ContentContext, InteractionStatus, Source } from "./types.ts";
import { VERDICTS } from "./types.ts";
import { parseAiRequest } from "./validation.ts";

export interface AiConfig {
  model: string;
  dailyQuota: number;
  monthlyBudget: number;
  timeoutMs: number;
}

export interface InteractionRow {
  userId: string;
  requestType: AiAction;
  exerciseId: string | null;
}

export interface InteractionPatch {
  status: InteractionStatus;
  model?: string | null;
  inputTokens?: number | null;
  outputTokens?: number | null;
  latencyMs?: number | null;
}

export interface AiDeps {
  config: AiConfig;
  now(): Date;
  /** Recharge exercice / unités / mot depuis la base à partir des identifiants de la requête. */
  loadContent(req: AiRequest): Promise<{ ok: true; ctx: ContentContext } | { ok: false; message: string }>;
  cacheGet(key: string): Promise<Record<string, unknown> | null>;
  cachePut(key: string, requestType: AiAction, body: AiBody, model: string): Promise<void>;
  /** Instants (ms) des interactions de l'utilisateur comptées au quota depuis sinceMs. */
  recentQuotaUsage(userId: string, sinceMs: number): Promise<number[]>;
  /** Nombre global d'interactions comptées au quota depuis sinceMs (plafond mensuel). */
  monthlyUsage(sinceMs: number): Promise<number>;
  /** Réserve une ligne ai_interactions (comptée au quota tout de suite). */
  startInteraction(row: InteractionRow, model: string): Promise<string | null>;
  finishInteraction(id: string | null, patch: InteractionPatch): Promise<void>;
  dropInteraction(id: string | null): Promise<void>;
  /** Ligne de journal unique (cache, quota atteint, repli sans appel…). */
  logInteraction(row: InteractionRow, status: InteractionStatus, latencyMs: number | null): Promise<void>;
  callModel(call: { model: string; system: string; user: string; maxTokens: number; timeoutMs: number }): Promise<ModelResult>;
  /** Journal technique SANS texte d'élève ni donnée personnelle. */
  log(event: string, data: Record<string, unknown>): void;
}

export interface AiResult {
  status: number;
  body: Record<string, unknown>;
}

function exerciseIdOf(req: AiRequest): string | null {
  return "exerciseId" in req ? req.exerciseId : null;
}

function withMeta(body: AiBody, source: Source, remainingQuota: number): Record<string, unknown> {
  return { ...body, source, remainingQuota };
}

function isValidBody(action: AiAction, v: Record<string, unknown>): v is Record<string, unknown> & AiBody {
  if (action === "grade-answer") {
    return typeof v.verdict === "string" && (VERDICTS as readonly string[]).includes(v.verdict) && typeof v.explanation === "string";
  }
  return typeof v.text === "string" && v.text !== "" && Array.isArray(v.examples);
}

function cacheParts(req: AiRequest, ctx: ContentContext) {
  const ids: string[] = [];
  let answer = "";
  const extra: string[] = [];
  switch (req.action) {
    case "explain-answer":
      ids.push(req.exerciseId);
      answer = req.userAnswer;
      extra.push(...req.previousErrorCategories);
      break;
    case "grade-answer":
      ids.push(req.exerciseId);
      answer = req.userAnswer;
      break;
    case "explain-rule":
      ids.push(req.unitId);
      break;
    case "explain-word":
      ids.push(ctx.dictItem?.id ?? req.word.toLowerCase());
      answer = req.sentence ?? "";
      break;
    default:
      break;
  }
  return {
    action: req.action,
    ids,
    answer: normalizeAnswer(answer),
    detail: detailOf(req),
    level: req.level,
    contentVersion: ctx.contentVersion,
    extra,
  };
}

export async function handleAi(userId: string, action: string, rawBody: unknown, deps: AiDeps): Promise<AiResult> {
  const parsed = parseAiRequest(action, rawBody);
  if (!parsed.ok) return { status: 400, body: { error: "bad_request", message: parsed.message } };
  const req = parsed.value;
  const row: InteractionRow = { userId, requestType: req.action, exerciseId: exerciseIdOf(req) };
  const { config } = deps;
  let ctx: ContentContext = emptyContext();
  let remaining = config.dailyQuota;

  try {
    const loaded = await deps.loadContent(req);
    if (!loaded.ok) return { status: 400, body: { error: "bad_request", message: loaded.message } };
    ctx = loaded.ctx;

    const nowMs = deps.now().getTime();
    const sinceMs = nowMs - DAY_MS;
    const unavailable = (message: string): AiResult => ({
      status: 503,
      body: { error: "unavailable", message, fallback: withMeta(buildFallback(req, ctx), "fallback", remaining) },
    });

    // Mot absent du dictionnaire validé : on ne laisse pas l'IA improviser (ni appel, ni quota).
    if (req.action === "explain-word" && ctx.dictItem === null) {
      const q = evaluateQuota({ limit: config.dailyQuota, timestampsMs: await deps.recentQuotaUsage(userId, sinceMs), nowMs });
      await deps.logInteraction(row, "fallback", null);
      return { status: 200, body: withMeta(buildFallback(req, ctx), "fallback", q.remaining) };
    }

    // 1. Cache (gratuit pour l'utilisateur).
    let key: string | null = null;
    if (isCacheable(req.action)) {
      key = await cacheKey(cacheParts(req, ctx));
      const hit = await deps.cacheGet(key);
      if (hit && isValidBody(req.action, hit)) {
        const q = evaluateQuota({ limit: config.dailyQuota, timestampsMs: await deps.recentQuotaUsage(userId, sinceMs), nowMs });
        await deps.logInteraction(row, "cached", 0);
        const { source: _s, remainingQuota: _r, ...cleaned } = hit as Record<string, unknown>;
        return { status: 200, body: { ...cleaned, source: "cache", remainingQuota: q.remaining } };
      }
    }

    // 2. Quota glissant de 24 h par utilisateur.
    const before = evaluateQuota({ limit: config.dailyQuota, timestampsMs: await deps.recentQuotaUsage(userId, sinceMs), nowMs });
    remaining = before.remaining;
    if (!before.allowed) {
      await deps.logInteraction(row, "rate_limited", null);
      return {
        status: 429,
        body: {
          error: "rate_limited",
          message: "Tu as atteint ta limite de demandes au professeur IA pour le moment. Réessaie plus tard.",
          resetAt: new Date(before.resetAtMs ?? nowMs + DAY_MS).toISOString(),
        },
      };
    }

    // 3. Plafond mensuel global (maîtrise des coûts).
    const monthStartMs = monthStartUtc(deps.now()).getTime();
    if ((await deps.monthlyUsage(monthStartMs)) >= config.monthlyBudget) {
      await deps.logInteraction(row, "rate_limited", null);
      deps.log("ai_monthly_budget_reached", { budget: config.monthlyBudget });
      return unavailable("Le professeur IA est en pause jusqu'à la fin du mois. Voici un rappel tiré de la leçon.");
    }

    // 4. Réservation (comptée au quota), puis contrôle anti-concurrence : si des requêtes
    //    simultanées ont dépassé la limite, la dernière arrivée se retire.
    const interactionId = await deps.startInteraction(row, config.model);
    const after = evaluateQuota({ limit: config.dailyQuota, timestampsMs: await deps.recentQuotaUsage(userId, sinceMs), nowMs: deps.now().getTime() });
    if (after.used > config.dailyQuota) {
      await deps.dropInteraction(interactionId);
      await deps.logInteraction(row, "rate_limited", null);
      const others = evaluateQuota({ limit: config.dailyQuota, timestampsMs: await deps.recentQuotaUsage(userId, sinceMs), nowMs });
      return {
        status: 429,
        body: {
          error: "rate_limited",
          message: "Tu as atteint ta limite de demandes au professeur IA pour le moment. Réessaie plus tard.",
          resetAt: new Date(others.resetAtMs ?? nowMs + DAY_MS).toISOString(),
        },
      };
    }
    remaining = Math.max(0, config.dailyQuota - after.used);

    // 5. Fournisseur.
    const result = await deps.callModel({
      model: config.model,
      system: SYSTEM_PROMPT,
      user: buildUserPrompt(req, ctx),
      maxTokens: maxTokensFor(req.action, detailOf(req)),
      timeoutMs: config.timeoutMs,
    });

    if (!result.ok) {
      await deps.finishInteraction(interactionId, { status: "error", model: null, latencyMs: result.latencyMs });
      deps.log("ai_provider_error", { action: req.action, kind: result.kind, status: result.status ?? null, attempts: result.attempts });
      return unavailable(MSG_AI_UNAVAILABLE);
    }

    // 6. Analyse de la sortie ; repli sur le contenu validé si elle est inexploitable.
    const body: AiBody | null = req.action === "grade-answer" ? parseGrade(result.text) : parseExplanation(result.text);
    const patch = { model: result.model, inputTokens: result.inputTokens, outputTokens: result.outputTokens, latencyMs: result.latencyMs };
    if (!body) {
      await deps.finishInteraction(interactionId, { status: "fallback", ...patch });
      deps.log("ai_unparsable_output", { action: req.action, stopReason: result.stopReason });
      return { status: 200, body: withMeta(buildFallback(req, ctx), "fallback", remaining) };
    }

    await deps.finishInteraction(interactionId, { status: "ok", ...patch });
    if (key !== null) {
      try {
        await deps.cachePut(key, req.action, body, result.model);
      } catch (e) {
        deps.log("ai_cache_write_failed", { message: e instanceof Error ? e.message.slice(0, 200) : "unknown" });
      }
    }
    return { status: 200, body: withMeta(body, "ai", remaining) };
  } catch (e) {
    deps.log("ai_unexpected_error", { action: req.action, name: e instanceof Error ? e.name : "unknown", message: e instanceof Error ? e.message.slice(0, 200) : "unknown" });
    return {
      status: 503,
      body: { error: "unavailable", message: MSG_AI_UNAVAILABLE, fallback: withMeta(buildFallback(req, ctx), "fallback", remaining) },
    };
  }
}
