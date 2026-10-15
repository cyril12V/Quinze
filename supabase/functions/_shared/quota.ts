// Quotas IA : fenêtre glissante de 24 h par utilisateur, plafond mensuel global. Fonctions pures.
//
// Une interaction compte au quota si un appel au fournisseur a eu lieu :
//   response_status in ('ok', 'fallback') ET model non nul.
// Sont gratuits : 'cached' (cache), 'rate_limited', 'error' (fournisseur injoignable), et les
// 'fallback' servis sans appel (model nul : mot inconnu du dictionnaire…).

import type { InteractionStatus } from "./types.ts";

export const DAY_MS = 24 * 60 * 60 * 1000;
export const DEFAULT_DAILY_QUOTA = 40;
export const DEFAULT_MONTHLY_BUDGET = 200_000;

export interface QuotaState {
  allowed: boolean;
  used: number;
  remaining: number;
  /** Instant (ms) où un créneau se libère, quand le quota est atteint ; null sinon. */
  resetAtMs: number | null;
}

export function evaluateQuota(opts: { limit: number; timestampsMs: number[]; nowMs: number }): QuotaState {
  const windowStart = opts.nowMs - DAY_MS;
  const inWindow = opts.timestampsMs.filter((t) => Number.isFinite(t) && t > windowStart).sort((a, b) => a - b);
  const used = inWindow.length;
  const limit = Math.max(0, Math.floor(opts.limit));
  const remaining = Math.max(0, limit - used);
  const allowed = used < limit;
  let resetAtMs: number | null = null;
  if (!allowed) {
    // La (used - limit + 1)-ième interaction la plus ancienne doit sortir de la fenêtre.
    const idx = used - limit;
    resetAtMs = limit === 0 || idx < 0 || idx >= inWindow.length ? opts.nowMs + DAY_MS : inWindow[idx] + DAY_MS;
  }
  return { allowed, used, remaining, resetAtMs };
}

/** Début (UTC) du mois civil courant : borne du plafond mensuel global. */
export function monthStartUtc(now: Date): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
}

export function consumesQuota(status: InteractionStatus, model: string | null): boolean {
  return (status === "ok" || status === "fallback") && model !== null && model !== "";
}

/** Entier strictement positif lu dans une variable d'environnement, sinon la valeur par défaut. */
export function parsePositiveInt(raw: string | undefined | null, fallback: number): number {
  if (raw === undefined || raw === null) return fallback;
  const n = Number.parseInt(String(raw).trim(), 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}
