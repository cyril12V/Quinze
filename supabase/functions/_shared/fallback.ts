// Réponses de secours construites UNIQUEMENT à partir du contenu validé (base de données),
// utilisées quand l'IA est indisponible, hors budget, ou renvoie une sortie inexploitable.
// Fonctions pures.

import type { AiBody, AiRequest, ContentContext, ErrorCategory, Example, ExerciseRow, ExplainBody, GradeBody } from "./types.ts";
import { ERROR_CATEGORIES } from "./types.ts";
import { asString, asStringArray, clip, foldAnswer, isRecord } from "./normalize.ts";

export const MSG_AI_UNAVAILABLE = "Le professeur IA est momentanément indisponible. Voici un rappel tiré de la leçon.";
export const MSG_WORD_UNKNOWN =
  "Ce mot ne fait pas (encore) partie du dictionnaire validé de Quinze : je préfère ne pas inventer d'explication. Regarde les leçons où il apparaît, ou demande-moi un autre mot.";
export const MSG_NO_CONTENT =
  "Je n'ai pas de contenu validé à te proposer pour cette question pour le moment. Reviens à la leçon et réessaie un peu plus tard.";

function toExample(v: unknown): Example | null {
  if (!isRecord(v)) return null;
  const text = asString(v.text) ?? asString(v.en);
  if (!text) return null;
  return { text, translation: asString(v.translation) ?? asString(v.fr) ?? "" };
}

function toExamples(v: unknown, max: number): Example[] {
  if (!Array.isArray(v)) return [];
  const out: Example[] = [];
  for (const e of v) {
    const ex = toExample(e);
    if (ex) out.push(ex);
    if (out.length >= max) break;
  }
  return out;
}

export function expectedAnswers(ex: ExerciseRow): string[] {
  const d = ex.data;
  const list = [...asStringArray(d.acceptedAnswers), ...ex.accepted_answers];
  const answer = asString(d.answer);
  if (answer) list.unshift(answer);
  return [...new Set(list)];
}

export function isAcceptedAnswer(ex: ExerciseRow, userAnswer: string): boolean {
  const f = foldAnswer(userAnswer);
  return f !== "" && expectedAnswers(ex).some((a) => foldAnswer(a) === f);
}

/** Retour validé associé à une erreur connue de l'exercice (errorPatterns du contenu), s'il y en a un. */
export function matchErrorPattern(ex: ExerciseRow, userAnswer: string): { category: ErrorCategory | null; feedback: string } | null {
  const f = foldAnswer(userAnswer);
  if (f === "") return null;
  const patterns = Array.isArray(ex.data.errorPatterns) ? ex.data.errorPatterns : [];
  for (const p of patterns) {
    if (!isRecord(p)) continue;
    const eq = asString(p.equals);
    const co = asString(p.contains);
    const hit = (eq !== null && foldAnswer(eq) === f) || (co !== null && f.includes(foldAnswer(co)));
    if (!hit) continue;
    const feedback = asString(p.feedback);
    if (!feedback) continue;
    const cat = asString(p.category);
    return {
      category: cat && (ERROR_CATEGORIES as readonly string[]).includes(cat) ? (cat as ErrorCategory) : null,
      feedback,
    };
  }
  return null;
}

function ruleOf(ctx: ContentContext): Record<string, unknown> | null {
  for (const u of ctx.units) {
    if (isRecord(u.data.rule)) return u.data.rule;
  }
  return null;
}

function contentSummary(ctx: ContentContext): string {
  const ex = ctx.exercise;
  if (ex) {
    const e = asString(ex.data.explanation) ?? ex.explanation;
    if (e) return e;
  }
  const rule = ruleOf(ctx);
  if (rule) return [asString(rule.summary), asString(rule.explanation)].filter(Boolean).join(" ");
  if (ctx.dictItem) return [ctx.dictItem.translation, ctx.dictItem.definition].filter(Boolean).join(" — ");
  return "";
}

function explainAnswerFallback(req: Extract<AiRequest, { action: "explain-answer" }>, ctx: ContentContext): ExplainBody {
  const ex = ctx.exercise;
  if (!ex) return { text: MSG_NO_CONTENT, examples: [] };
  const d = ex.data;
  const correct = isAcceptedAnswer(ex, req.userAnswer);
  const pat = correct ? null : matchErrorPattern(ex, req.userAnswer);
  const parts: string[] = [];
  if (correct) {
    parts.push("Bonne réponse !");
  } else {
    parts.push("Ce n'est pas tout à fait ça.");
    if (pat) parts.push(pat.feedback);
    const expected = asString(d.answer) ?? ex.accepted_answers[0];
    if (expected) parts.push(`La réponse attendue est « ${expected} ».`);
  }
  const explanation = asString(d.explanation) ?? ex.explanation;
  if (explanation) parts.push(explanation);
  const tip = asString(d.tip);
  if (tip) parts.push(`Astuce : ${tip}`);
  const examples: Example[] = [];
  const extra = toExample(d.extraExample);
  if (extra) examples.push(extra);
  return { text: clip(parts.join(" "), 1800), examples };
}

function explainRuleFallback(ctx: ContentContext): ExplainBody {
  const rule = ruleOf(ctx);
  if (!rule) return { text: MSG_NO_CONTENT, examples: [] };
  const parts = [asString(rule.summary), asString(rule.explanation)].filter((x): x is string => x !== null);
  const pattern = asString(rule.pattern);
  if (pattern) parts.push(`Schéma : ${pattern}`);
  const tip = asString(rule.tip);
  if (tip) parts.push(`Astuce : ${tip}`);
  return { text: clip(parts.join(" "), 1800), examples: toExamples(rule.examples, 2) };
}

function explainWordFallback(ctx: ContentContext): ExplainBody {
  const it = ctx.dictItem;
  if (!it) return { text: MSG_WORD_UNKNOWN, examples: [] };
  const parts = [`« ${it.word} » signifie « ${it.translation} ».`];
  if (it.pronunciation) parts.push(`Prononciation : ${it.pronunciation}.`);
  const definition = it.definition ?? asString(it.data.explanation);
  if (definition) parts.push(definition);
  const conf = Array.isArray(it.data.confusions) ? it.data.confusions.filter(isRecord) : [];
  for (const c of conf.slice(0, 2)) {
    const w = asString(c.word);
    const n = asString(c.note);
    if (w && n) parts.push(`Ne confonds pas avec « ${w} » : ${n}`);
  }
  const examples = toExamples(Array.isArray(it.examples) && it.examples.length > 0 ? it.examples : it.data.examples, 2);
  return { text: clip(parts.join(" "), 1800), examples };
}

function followUpFallback(req: Extract<AiRequest, { action: "follow-up" }>, ctx: ContentContext): ExplainBody {
  const recall = req.previousExplanation.trim() !== "" ? clip(req.previousExplanation.trim(), 700) : clip(contentSummary(ctx), 700);
  const text = recall
    ? `Je ne peux pas répondre à ta question pour le moment (le professeur IA est indisponible). Voici un rappel : ${recall} Réessaie un peu plus tard.`
    : MSG_NO_CONTENT;
  return { text, examples: [] };
}

function gradeFallback(req: Extract<AiRequest, { action: "grade-answer" }>, ctx: ContentContext): GradeBody {
  const ex = ctx.exercise;
  if (!ex) return { verdict: "uncertain", errorCategory: null, explanation: MSG_NO_CONTENT, correctedAnswer: null };
  if (isAcceptedAnswer(ex, req.userAnswer)) {
    return { verdict: "correct", errorCategory: null, explanation: "Bonne réponse !", correctedAnswer: null };
  }
  const expected = asString(ex.data.answer) ?? ex.accepted_answers[0] ?? null;
  const pat = matchErrorPattern(ex, req.userAnswer);
  if (pat) {
    return { verdict: "incorrect", errorCategory: pat.category, explanation: clip(pat.feedback, 700), correctedAnswer: expected };
  }
  return {
    verdict: "uncertain",
    errorCategory: null,
    explanation: expected
      ? `Je n'ai pas pu corriger ta réponse automatiquement. La réponse attendue est « ${expected} ».`
      : "Je n'ai pas pu corriger ta réponse automatiquement.",
    correctedAnswer: expected,
  };
}

/** Réponse de secours pour la requête, sans appel au fournisseur. */
export function buildFallback(req: AiRequest, ctx: ContentContext): AiBody {
  switch (req.action) {
    case "explain-answer":
      return explainAnswerFallback(req, ctx);
    case "explain-rule":
      return explainRuleFallback(ctx);
    case "explain-word":
      return explainWordFallback(ctx);
    case "follow-up":
      return followUpFallback(req, ctx);
    case "grade-answer":
      return gradeFallback(req, ctx);
  }
}

/** Contexte vide (quand même le chargement du contenu a échoué). */
export function emptyContext(languageId = ""): ContentContext {
  return { languageId, contentVersion: "", exercise: null, units: [], dictItem: null };
}
