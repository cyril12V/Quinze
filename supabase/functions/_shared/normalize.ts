// Normalisation de texte. Fonctions pures.

/** Retire les caractères de contrôle (sauf \n et \t) et les caractères de formatage invisibles. */
export function stripControl(s: string): string {
  // deno-lint-ignore no-control-regex
  return s.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏‪-‮⁦-⁩﻿]/g, "");
}

/** Forme canonique d'une réponse pour la clé de cache : NFKC, guillemets droits, espaces simples. La casse et la ponctuation sont CONSERVÉES (« i am » ≠ « I am »). */
export function normalizeAnswer(s: string): string {
  return stripControl(s)
    .normalize("NFKC")
    .replace(/[‘’‛´`]/g, "'")
    .replace(/[“”„«»]/g, '"')
    .replace(/\s+/g, " ")
    .trim();
}

/** Forme « pliée » pour comparer à des réponses acceptées : sans casse ni ponctuation. */
export function foldAnswer(s: string): string {
  return normalizeAnswer(s)
    .toLowerCase()
    .replace(/[.,!?;:"]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/** Empêche une donnée utilisateur de fermer ou d'ouvrir une balise du prompt. */
export function escapeTags(s: string): string {
  return s.replace(/</g, "‹").replace(/>/g, "›");
}

export function clip(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, Math.max(0, max - 1)).trimEnd() + "…";
}

/** Formes à chercher dans le dictionnaire pour un mot saisi (« goes » -> « go »…). */
export function wordCandidates(word: string): string[] {
  const w = normalizeAnswer(word)
    .toLowerCase()
    .replace(/^[^a-z]+|[^a-z]+$/g, "")
    .replace(/[^a-z' -]/g, "");
  if (!w) return [];
  const out = [w];
  const add = (x: string) => {
    if (x.length >= 2 && !out.includes(x)) out.push(x);
  };
  if (w.endsWith("ies")) add(w.slice(0, -3) + "y");
  if (w.endsWith("es")) add(w.slice(0, -2));
  if (w.endsWith("s")) add(w.slice(0, -1));
  if (w.endsWith("ied")) add(w.slice(0, -3) + "y");
  if (w.endsWith("ed")) {
    add(w.slice(0, -2));
    add(w.slice(0, -1));
  }
  if (w.endsWith("ing")) {
    add(w.slice(0, -3));
    add(w.slice(0, -3) + "e");
  }
  if (w.endsWith("'s")) add(w.slice(0, -2));
  return out.slice(0, 8);
}

export function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

export function asString(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v : null;
}

export function asStringArray(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string" && x.trim() !== "") : [];
}
