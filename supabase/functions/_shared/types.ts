// Types partagés des Edge Functions. Aucun accès à Deno ni au réseau ici.

export const AI_ACTIONS = ["explain-answer", "explain-word", "explain-rule", "follow-up", "grade-answer"] as const;
export type AiAction = (typeof AI_ACTIONS)[number];

export const ERROR_CATEGORIES = [
  "vocabulary",
  "grammar",
  "conjugation",
  "verb_tense",
  "word_order",
  "spelling",
  "preposition",
  "word_confusion",
  "instruction",
] as const;
export type ErrorCategory = (typeof ERROR_CATEGORIES)[number];

export const VERDICTS = ["correct", "partial", "incorrect", "uncertain"] as const;
export type Verdict = (typeof VERDICTS)[number];

export type Detail = "short" | "detailed";
/** Niveau estimé de l'élève : entier (1 = grand débutant) ou niveau CECRL (A1…C2). */
export type Level = number | string;

export interface ExplainAnswerRequest {
  action: "explain-answer";
  languageCode: string;
  level: Level;
  exerciseId: string;
  userAnswer: string;
  detail: Detail;
  previousErrorCategories: ErrorCategory[];
}
export interface ExplainWordRequest {
  action: "explain-word";
  languageCode: string;
  level: Level;
  word: string;
  sentence: string | null;
  detail: Detail;
}
export interface ExplainRuleRequest {
  action: "explain-rule";
  languageCode: string;
  level: Level;
  unitId: string;
  detail: Detail;
}
export interface HistoryMessage {
  role: "user" | "tutor";
  text: string;
}
export interface FollowUpRequest {
  action: "follow-up";
  languageCode: string;
  level: Level;
  exerciseId: string | null;
  unitId: string | null;
  word: string | null;
  userAnswer: string | null;
  previousExplanation: string;
  history: HistoryMessage[];
  question: string;
}
export interface GradeAnswerRequest {
  action: "grade-answer";
  languageCode: string;
  level: Level;
  exerciseId: string;
  userAnswer: string;
}
export type AiRequest =
  | ExplainAnswerRequest
  | ExplainWordRequest
  | ExplainRuleRequest
  | FollowUpRequest
  | GradeAnswerRequest;

// --- Contenu validé chargé depuis la base (lignes telles que dans les tables) -------------

export interface ExerciseRow {
  id: string;
  language_id: string;
  lesson_id: string | null;
  learning_unit_id: string;
  unit_ids: string[];
  exercise_type: string;
  question: string;
  accepted_answers: string[];
  explanation: string;
  difficulty: number;
  data: Record<string, unknown>;
  content_version: string;
}
export interface UnitRow {
  id: string;
  language_id: string;
  kind: string;
  category: string;
  title: string;
  difficulty: number;
  data: Record<string, unknown>;
  content_version: string;
}
export interface DictRow {
  id: string;
  language_id: string;
  word: string;
  translation: string;
  definition: string | null;
  examples: unknown;
  pronunciation: string | null;
  data: Record<string, unknown>;
  content_version: string;
}
export interface ContentContext {
  languageId: string;
  contentVersion: string;
  exercise: ExerciseRow | null;
  units: UnitRow[];
  dictItem: DictRow | null;
}

// --- Corps de réponse -------------------------------------------------------------------

export interface Example {
  text: string;
  translation: string;
}
export interface ExplainBody {
  text: string;
  examples: Example[];
}
export interface GradeBody {
  verdict: Verdict;
  errorCategory: ErrorCategory | null;
  explanation: string;
  correctedAnswer: string | null;
}
export type AiBody = ExplainBody | GradeBody;
export type Source = "ai" | "cache" | "fallback";
export type InteractionStatus = "ok" | "cached" | "fallback" | "rate_limited" | "error";
