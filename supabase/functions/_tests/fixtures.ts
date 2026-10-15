// Jeux de données de test : lignes de contenu telles qu'elles sont dans la base
// (même transformation que `build_seed` de tools/build_content.py).

import { existsSync, readFileSync } from "node:fs";
import type { ContentContext, DictRow, ExerciseRow, UnitRow } from "../_shared/types.ts";

export const EXERCISE: ExerciseRow = {
  id: "en.l01.e01",
  language_id: "en",
  lesson_id: "en.l01",
  learning_unit_id: "en.g01.subject_pronouns",
  unit_ids: ["en.g01.subject_pronouns"],
  exercise_type: "mcq",
  question: "Comment dit-on « elle » en anglais, pour parler d'une femme ?",
  accepted_answers: ["she"],
  explanation: "She veut dire « elle » quand on parle d'une femme ou d'une fille. He, c'est « il » pour un homme.",
  difficulty: 1,
  content_version: "1.0.0",
  data: {
    id: "en.l01.e01",
    unitIds: ["en.g01.subject_pronouns"],
    type: "mcq",
    instruction: "Choisis le bon pronom.",
    prompt: "Comment dit-on « elle » en anglais, pour parler d'une femme ?",
    options: ["she", "he", "it", "we"],
    answer: "she",
    acceptedAnswers: ["she"],
    hint: "C'est le pronom de he, avec une lettre en plus devant.",
    explanation: "She veut dire « elle » quand on parle d'une femme ou d'une fille. He, c'est « il » pour un homme.",
    tip: "Retiens la paire : he = il (un homme), she = elle (une femme).",
    extraExample: { text: "Anna? She is in London.", translation: "Anna ? Elle est à Londres." },
    errorPatterns: [
      { equals: "he", category: "vocabulary", feedback: "He veut dire « il », pour un homme. Pour une femme, on dit she." },
      { equals: "it", category: "word_confusion", feedback: "It s'utilise pour une chose ou un animal. Pour une femme, on dit she." },
    ],
  },
};

export const UNIT: UnitRow = {
  id: "en.g01.subject_pronouns",
  language_id: "en",
  kind: "grammar",
  category: "grammar",
  title: "Les pronoms personnels sujets",
  difficulty: 1,
  content_version: "1.0.0",
  data: {
    functionWords: ["I", "you", "he", "she", "it", "we", "they"],
    rule: {
      summary: "Les pronoms sujets (I, you, he, she, it, we, they) remplacent la personne ou la chose dont on parle.",
      explanation: "L'anglais a sept pronoms sujets : I (je), you (tu ou vous), he (il), she (elle), it (chose), we (nous), they (ils/elles).",
      pattern: "Pronom sujet + verbe : I am…, she is…",
      examples: [
        { text: "Hello! I am Emma.", translation: "Bonjour ! Je suis Emma." },
        { text: "They are in London.", translation: "Ils sont à Londres." },
      ],
      commonErrors: [{ wrong: "Hello! i am Tom.", right: "Hello! I am Tom.", why: "I s'écrit toujours avec une majuscule." }],
      tip: "I prend toujours une majuscule.",
    },
  },
};

export const DICT: DictRow = {
  id: "en.d.hello",
  language_id: "en",
  word: "hello",
  translation: "bonjour",
  definition: "On dit hello pour saluer quelqu'un, à n'importe quel moment de la journée.",
  examples: [{ text: "Hello, Anna!", translation: "Bonjour, Anna !" }],
  pronunciation: "/həˈləʊ/",
  content_version: "1.0.0",
  data: {
    id: "en.d.hello",
    word: "hello",
    translation: "bonjour",
    otherTranslations: ["salut"],
    partOfSpeech: "interjection",
    ipa: "/həˈləʊ/",
    confusions: [{ word: "hi", note: "version plus familière de hello : salut." }],
  },
};

export function ctxFor(kind: "exercise" | "rule" | "word"): ContentContext {
  if (kind === "exercise") return { languageId: "en", contentVersion: "1.0.0", exercise: EXERCISE, units: [UNIT], dictItem: null };
  if (kind === "rule") return { languageId: "en", contentVersion: "1.0.0", exercise: null, units: [UNIT], dictItem: null };
  return { languageId: "en", contentVersion: "1.0.0", exercise: null, units: [], dictItem: DICT };
}

// --- Contenu réel (Content/build/en.json), si présent -----------------------------------------

const BUNDLE_URL = new URL("../../../Content/build/en.json", import.meta.url);

export function realBundleAvailable(): boolean {
  return existsSync(BUNDLE_URL);
}

// deno-lint-ignore no-explicit-any
type Json = any;

export function loadRealRows(): { exercises: ExerciseRow[]; units: UnitRow[]; dict: DictRow[] } {
  const b: Json = JSON.parse(readFileSync(BUNDLE_URL, "utf8"));
  const v = b.contentVersion as string;
  const pick = (u: Json) => {
    const data: Record<string, unknown> = {};
    for (const k of ["rule", "functionWords", "translation", "partOfSpeech", "lessonId", "dictionaryItemId"]) {
      if (u[k] !== undefined && u[k] !== null) data[k] = u[k];
    }
    return data;
  };
  const exercises: ExerciseRow[] = [...b.exercises, ...b.diagnostic, ...b.assessment].map((e: Json) => ({
    id: e.id,
    language_id: "en",
    lesson_id: e.lessonId ?? null,
    learning_unit_id: e.unitIds[0],
    unit_ids: e.unitIds,
    exercise_type: e.type,
    question: e.prompt,
    accepted_answers: e.acceptedAnswers,
    explanation: e.explanation,
    difficulty: e.difficulty,
    data: e,
    content_version: v,
  }));
  const units: UnitRow[] = b.units.map((u: Json) => ({
    id: u.id,
    language_id: "en",
    kind: u.kind,
    category: u.category,
    title: u.title,
    difficulty: u.difficulty,
    data: pick(u),
    content_version: v,
  }));
  const dict: DictRow[] = b.dictionary.map((d: Json) => ({
    id: d.id,
    language_id: "en",
    word: d.word,
    translation: d.translation,
    definition: d.explanation ?? null,
    examples: d.examples ?? [],
    pronunciation: d.ipa ?? null,
    data: d,
    content_version: v,
  }));
  return { exercises, units, dict };
}
