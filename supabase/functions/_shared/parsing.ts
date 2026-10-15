// Lecture robuste des sorties du modèle. Fonctions pures.
// Le modèle doit répondre en JSON strict ; on tolère les balises de code, un texte autour,
// un JSON tronqué (texte récupérable) ; sinon l'appelant bascule sur la réponse de secours.

import { ERROR_CATEGORIES, VERDICTS } from "./types.ts";
import type { ErrorCategory, Example, ExplainBody, GradeBody, Verdict } from "./types.ts";
import { clip, isRecord, stripControl } from "./normalize.ts";

export const MAX_TEXT = 2000;
export const MAX_EXAMPLES = 3;

/** Premier objet JSON équilibré trouvé dans `raw` (balises ```json tolérées), ou null. */
export function extractJsonObject(raw: string): Record<string, unknown> | null {
  if (typeof raw !== "string") return null;
  let s = raw.trim();
  const fence = /```(?:json)?\s*([\s\S]*?)```/i.exec(s);
  if (fence) s = fence[1].trim();
  const direct = tryParse(s);
  if (direct) return direct;
  const start = s.indexOf("{");
  if (start === -1) return null;
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < s.length; i++) {
    const c = s[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === "{") depth++;
    else if (c === "}") {
      depth--;
      if (depth === 0) return tryParse(s.slice(start, i + 1));
    }
  }
  return null;
}

function tryParse(s: string): Record<string, unknown> | null {
  try {
    const v = JSON.parse(s);
    return isRecord(v) ? v : null;
  } catch {
    return null;
  }
}

function cleanText(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const s = stripControl(v).trim();
  return s === "" ? null : clip(s, max);
}

function parseExamples(v: unknown): Example[] {
  if (!Array.isArray(v)) return [];
  const out: Example[] = [];
  for (const e of v) {
    if (!isRecord(e)) continue;
    const text = cleanText(e.text ?? e.en, 240);
    if (!text) continue;
    out.push({ text, translation: cleanText(e.translation ?? e.fr, 240) ?? "" });
    if (out.length >= MAX_EXAMPLES) break;
  }
  return out;
}

/** Récupère le champ "text" d'un JSON tronqué (ex. coupé par max_tokens). */
function rescueText(raw: string): string | null {
  const m = /"text"\s*:\s*"((?:[^"\\]|\\.)*)/.exec(raw);
  if (!m) return null;
  try {
    return cleanText(JSON.parse(`"${m[1].replace(/\\$/, "")}"`), MAX_TEXT);
  } catch {
    return cleanText(m[1], MAX_TEXT);
  }
}

/** Réponse d'explication : { text, examples } ; null si inexploitable. */
export function parseExplanation(raw: string): ExplainBody | null {
  const obj = extractJsonObject(raw);
  if (obj) {
    const text = cleanText(obj.text ?? obj.explanation, MAX_TEXT);
    if (text) return { text, examples: parseExamples(obj.examples) };
    return null;
  }
  const rescued = rescueText(raw);
  if (rescued) return { text: rescued, examples: [] };
  // Texte brut sans JSON : acceptable s'il ressemble à une vraie réponse (pas à du JSON cassé).
  const plain = cleanText(raw, MAX_TEXT);
  if (plain && !plain.startsWith("{") && !plain.startsWith("[") && plain.length >= 15) return { text: plain, examples: [] };
  return null;
}

/** Note : { verdict, errorCategory, explanation, correctedAnswer } ; null si le verdict est absent/invalide. */
export function parseGrade(raw: string): GradeBody | null {
  const obj = extractJsonObject(raw);
  if (!obj) return null;
  const verdictRaw = typeof obj.verdict === "string" ? obj.verdict.trim().toLowerCase() : "";
  if (!(VERDICTS as readonly string[]).includes(verdictRaw)) return null;
  const verdict = verdictRaw as Verdict;

  const catRaw = obj.errorCategory ?? obj.error_category;
  let errorCategory: ErrorCategory | null = null;
  if (typeof catRaw === "string") {
    const c = catRaw.trim().toLowerCase().replace(/[\s-]+/g, "_");
    if ((ERROR_CATEGORIES as readonly string[]).includes(c)) errorCategory = c as ErrorCategory;
  }
  if (verdict === "correct") errorCategory = null;

  const explanation =
    cleanText(obj.explanation, 700) ?? (verdict === "correct" ? "Bonne réponse !" : null);
  if (!explanation) return null;

  const correctedRaw = obj.correctedAnswer ?? obj.corrected_answer;
  const correctedAnswer = cleanText(correctedRaw, 300);

  return { verdict, errorCategory, explanation, correctedAnswer };
}
