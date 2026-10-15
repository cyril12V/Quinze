// Clé du cache IA : sha256(action, ids, réponse normalisée, detail, niveau, version du contenu).
// Le cache ne contient aucune donnée personnelle (pas d'identifiant d'utilisateur dans la clé).

import { normalizeAnswer } from "./normalize.ts";
import type { AiAction, Detail, Level } from "./types.ts";

export const CACHEABLE_ACTIONS: readonly AiAction[] = ["explain-answer", "explain-word", "explain-rule", "grade-answer"];

export function isCacheable(action: AiAction): boolean {
  return CACHEABLE_ACTIONS.includes(action);
}

export interface CacheKeyParts {
  action: AiAction;
  /** Identifiants du contenu (exercice, unité, mot du dictionnaire…). */
  ids: string[];
  /** Réponse (ou phrase de contexte) de l'élève : normalisée ici. */
  answer: string;
  detail: Detail | null;
  level: Level;
  contentVersion: string;
  /** Éléments qui changent le contenu de la réponse (ex. catégories d'erreurs récurrentes). */
  extra?: string[];
}

export async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const digest = await globalThis.crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function canonicalKeyMaterial(p: CacheKeyParts): string {
  return JSON.stringify([
    "quinze-ai-cache-v1",
    p.action,
    [...p.ids].sort(),
    normalizeAnswer(p.answer),
    p.detail ?? "",
    String(p.level),
    p.contentVersion,
    [...(p.extra ?? [])].sort(),
  ]);
}

export function cacheKey(p: CacheKeyParts): Promise<string> {
  return sha256Hex(canonicalKeyMaterial(p));
}
