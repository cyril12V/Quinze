// Validation des corps de requête de la fonction `ai`. Fonctions pures.
// Limites (contrat) : history <= 6 messages, question <= 500 caractères, userAnswer <= 300.

import { AI_ACTIONS, ERROR_CATEGORIES } from "./types.ts";
import type { AiAction, AiRequest, Detail, ErrorCategory, HistoryMessage, Level } from "./types.ts";
import { isRecord, stripControl } from "./normalize.ts";

export const LIMITS = {
  bodyChars: 16_000,
  id: 100,
  userAnswer: 300,
  question: 500,
  historyMessages: 6,
  historyText: 600,
  previousExplanation: 2000,
  word: 60,
  sentence: 300,
  previousErrorCategories: 10,
} as const;

export type ParseResult<T> = { ok: true; value: T } | { ok: false; message: string };

const fail = (message: string): { ok: false; message: string } => ({ ok: false, message });

export function isAiAction(s: string): s is AiAction {
  return (AI_ACTIONS as readonly string[]).includes(s);
}

const ID_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]*$/;
const LANG_RE = /^[a-z]{2,8}(-[A-Za-z0-9]{2,8})*$/;
const CEFR_RE = /^(A1|A2|B1|B2|C1|C2)$/i;

function reqString(body: Record<string, unknown>, key: string, max: number, opts: { allowEmpty?: boolean } = {}): ParseResult<string> {
  const v = body[key];
  if (typeof v !== "string") return fail(`Champ « ${key} » manquant ou invalide (texte attendu).`);
  const s = stripControl(v).trim();
  if (!opts.allowEmpty && s === "") return fail(`Champ « ${key} » vide.`);
  if (s.length > max) return fail(`Champ « ${key} » trop long (${max} caractères maximum).`);
  return { ok: true, value: s };
}

function optString(body: Record<string, unknown>, key: string, max: number): ParseResult<string | null> {
  const v = body[key];
  if (v === undefined || v === null) return { ok: true, value: null };
  const r = reqString(body, key, max, { allowEmpty: true });
  if (!r.ok) return r;
  return { ok: true, value: r.value === "" ? null : r.value };
}

function idField(body: Record<string, unknown>, key: string, required: boolean): ParseResult<string | null> {
  const v = body[key];
  if (v === undefined || v === null || v === "") {
    return required ? fail(`Champ « ${key} » manquant.`) : { ok: true, value: null };
  }
  if (typeof v !== "string" || v.length > LIMITS.id || !ID_RE.test(v)) return fail(`Champ « ${key} » invalide.`);
  return { ok: true, value: v };
}

function levelField(body: Record<string, unknown>): ParseResult<Level> {
  const v = body.level;
  if (typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= 20) return { ok: true, value: v };
  if (typeof v === "string" && CEFR_RE.test(v.trim())) return { ok: true, value: v.trim().toUpperCase() };
  return fail("Champ « level » invalide (nombre de 0 à 20 ou niveau A1…C2).");
}

function detailField(body: Record<string, unknown>): ParseResult<Detail> {
  const v = body.detail;
  if (v === undefined || v === null) return { ok: true, value: "short" };
  if (v === "short" || v === "detailed") return { ok: true, value: v };
  return fail("Champ « detail » invalide (« short » ou « detailed »).");
}

function languageField(body: Record<string, unknown>): ParseResult<string> {
  const v = body.languageCode;
  if (typeof v !== "string" || !LANG_RE.test(v)) return fail("Champ « languageCode » invalide.");
  return { ok: true, value: v };
}

function errorCategories(body: Record<string, unknown>): ErrorCategory[] {
  const v = body.previousErrorCategories;
  if (!Array.isArray(v)) return [];
  const out: ErrorCategory[] = [];
  for (const x of v) {
    if (typeof x === "string" && (ERROR_CATEGORIES as readonly string[]).includes(x) && !out.includes(x as ErrorCategory)) {
      out.push(x as ErrorCategory);
    }
    if (out.length >= LIMITS.previousErrorCategories) break;
  }
  return out;
}

function historyField(body: Record<string, unknown>): ParseResult<HistoryMessage[]> {
  const v = body.history;
  if (v === undefined || v === null) return { ok: true, value: [] };
  if (!Array.isArray(v)) return fail("Champ « history » invalide (tableau attendu).");
  const out: HistoryMessage[] = [];
  for (const m of v.slice(-LIMITS.historyMessages)) {
    if (!isRecord(m) || (m.role !== "user" && m.role !== "tutor") || typeof m.text !== "string") {
      return fail("Champ « history » invalide (chaque message : { role: « user » | « tutor », text }).");
    }
    const text = stripControl(m.text).trim();
    if (text.length > LIMITS.historyText) return fail(`Un message de « history » est trop long (${LIMITS.historyText} caractères maximum).`);
    if (text !== "") out.push({ role: m.role, text });
  }
  return { ok: true, value: out };
}

/** Valide le corps de `POST /ai/<action>`. */
export function parseAiRequest(action: string, raw: unknown): ParseResult<AiRequest> {
  if (!isAiAction(action)) return fail(`Action inconnue : « ${action} ».`);
  if (!isRecord(raw)) return fail("Le corps doit être un objet JSON.");

  const lang = languageField(raw);
  if (!lang.ok) return lang;
  const level = levelField(raw);
  if (!level.ok) return level;
  const base = { languageCode: lang.value, level: level.value };

  switch (action) {
    case "explain-answer": {
      const exerciseId = idField(raw, "exerciseId", true);
      if (!exerciseId.ok) return exerciseId;
      const userAnswer = reqString(raw, "userAnswer", LIMITS.userAnswer, { allowEmpty: true });
      if (!userAnswer.ok) return userAnswer;
      const detail = detailField(raw);
      if (!detail.ok) return detail;
      return {
        ok: true,
        value: {
          action,
          ...base,
          exerciseId: exerciseId.value as string,
          userAnswer: userAnswer.value,
          detail: detail.value,
          previousErrorCategories: errorCategories(raw),
        },
      };
    }
    case "explain-word": {
      const word = reqString(raw, "word", LIMITS.word);
      if (!word.ok) return word;
      const sentence = optString(raw, "sentence", LIMITS.sentence);
      if (!sentence.ok) return sentence;
      const detail = detailField(raw);
      if (!detail.ok) return detail;
      return { ok: true, value: { action, ...base, word: word.value, sentence: sentence.value, detail: detail.value } };
    }
    case "explain-rule": {
      const unitId = idField(raw, "unitId", true);
      if (!unitId.ok) return unitId;
      const detail = detailField(raw);
      if (!detail.ok) return detail;
      return { ok: true, value: { action, ...base, unitId: unitId.value as string, detail: detail.value } };
    }
    case "follow-up": {
      const exerciseId = idField(raw, "exerciseId", false);
      if (!exerciseId.ok) return exerciseId;
      const unitId = idField(raw, "unitId", false);
      if (!unitId.ok) return unitId;
      const word = optString(raw, "word", LIMITS.word);
      if (!word.ok) return word;
      if (!exerciseId.value && !unitId.value && !word.value) {
        return fail("Il faut au moins un de ces champs : « exerciseId », « unitId », « word ».");
      }
      const userAnswer = optString(raw, "userAnswer", LIMITS.userAnswer);
      if (!userAnswer.ok) return userAnswer;
      const previousExplanation = optString(raw, "previousExplanation", LIMITS.previousExplanation);
      if (!previousExplanation.ok) return previousExplanation;
      const history = historyField(raw);
      if (!history.ok) return history;
      const question = reqString(raw, "question", LIMITS.question);
      if (!question.ok) return question;
      return {
        ok: true,
        value: {
          action,
          ...base,
          exerciseId: exerciseId.value,
          unitId: unitId.value,
          word: word.value,
          userAnswer: userAnswer.value,
          previousExplanation: previousExplanation.value ?? "",
          history: history.value,
          question: question.value,
        },
      };
    }
    case "grade-answer": {
      const exerciseId = idField(raw, "exerciseId", true);
      if (!exerciseId.ok) return exerciseId;
      const userAnswer = reqString(raw, "userAnswer", LIMITS.userAnswer);
      if (!userAnswer.ok) return userAnswer;
      return { ok: true, value: { action, ...base, exerciseId: exerciseId.value as string, userAnswer: userAnswer.value } };
    }
  }
}
