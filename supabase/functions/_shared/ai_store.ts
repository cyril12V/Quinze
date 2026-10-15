// Implémentation des dépendances d'ai_core avec supabase-js (client service role) et fetch.
// Aucune donnée de l'élève (texte de réponse, question…) n'est écrite ici : seulement des
// métadonnées techniques dans ai_interactions.

import { callAnthropic } from "./anthropic.ts";
import type { AiConfig, AiDeps, InteractionPatch, InteractionRow } from "./ai_core.ts";
import { wordCandidates } from "./normalize.ts";
import type { SupabaseClient } from "./supabase.ts";
import type { AiBody, AiRequest, ContentContext, DictRow, ExerciseRow, UnitRow } from "./types.ts";

const EXERCISE_COLS =
  "id, language_id, lesson_id, learning_unit_id, unit_ids, exercise_type, question, accepted_answers, explanation, difficulty, data, content_version";
const UNIT_COLS = "id, language_id, kind, category, title, difficulty, data, content_version";
const DICT_COLS = "id, language_id, word, translation, definition, examples, pronunciation, data, content_version";
const QUOTA_STATUSES = ["ok", "fallback"];

function fail(message: string): { ok: false; message: string } {
  return { ok: false, message };
}

// deno-lint-ignore no-explicit-any
type Row = any;

export function makeAiDeps(sb: SupabaseClient, config: AiConfig, apiKey: string | undefined): AiDeps {
  const log = (event: string, data: Record<string, unknown>) => console.log(JSON.stringify({ event, ...data }));

  async function findDictionaryItem(languageId: string, word: string): Promise<DictRow | null> {
    const candidates = wordCandidates(word);
    if (candidates.length === 0) return null;
    // Candidats nettoyés ([a-z' -] uniquement) : sans risque dans un filtre PostgREST entre guillemets.
    const filter = candidates.map((c) => `word.ilike."${c}"`).join(",");
    const { data, error } = await sb.from("dictionary_items").select(DICT_COLS).eq("language_id", languageId).or(filter).limit(10);
    if (error) throw new Error(`dictionary lookup failed: ${error.message}`);
    const rows = (data ?? []) as DictRow[];
    for (const c of candidates) {
      const hit = rows.find((r) => r.word.toLowerCase() === c);
      if (hit) return hit;
    }
    return rows[0] ?? null;
  }

  return {
    config,
    now: () => new Date(),

    async loadContent(req: AiRequest) {
      const { data: lang, error: langErr } = await sb
        .from("languages")
        .select("id, is_available")
        .eq("code", req.languageCode)
        .maybeSingle();
      if (langErr) throw new Error(`language lookup failed: ${langErr.message}`);
      if (!lang || !(lang as Row).is_available) return fail(`Langue inconnue ou indisponible : ${req.languageCode}.`);
      const languageId = (lang as Row).id as string;

      let exercise: ExerciseRow | null = null;
      const exerciseId = "exerciseId" in req ? req.exerciseId : null;
      if (exerciseId) {
        const { data, error } = await sb.from("exercises").select(EXERCISE_COLS).eq("id", exerciseId).eq("language_id", languageId).maybeSingle();
        if (error) throw new Error(`exercise lookup failed: ${error.message}`);
        if (!data) return fail(`Exercice inconnu : ${exerciseId}.`);
        exercise = data as ExerciseRow;
      }

      const unitIds: string[] = [];
      if ("unitId" in req && req.unitId) unitIds.push(req.unitId);
      if (exercise) unitIds.push(...exercise.unit_ids.slice(0, 4));
      let units: UnitRow[] = [];
      if (unitIds.length > 0) {
        const wanted = [...new Set(unitIds)];
        const { data, error } = await sb.from("learning_units").select(UNIT_COLS).in("id", wanted).eq("language_id", languageId);
        if (error) throw new Error(`unit lookup failed: ${error.message}`);
        const byId = new Map(((data ?? []) as UnitRow[]).map((u) => [u.id, u]));
        units = wanted.map((id) => byId.get(id)).filter((u): u is UnitRow => u !== undefined);
        if ("unitId" in req && req.unitId && !byId.has(req.unitId)) return fail(`Unité inconnue : ${req.unitId}.`);
      }

      let dictItem: DictRow | null = null;
      const word = "word" in req ? req.word : null;
      if (word) dictItem = await findDictionaryItem(languageId, word);

      const versions = [...new Set([exercise?.content_version, ...units.map((u) => u.content_version), dictItem?.content_version].filter((v): v is string => !!v))].sort();
      const ctx: ContentContext = { languageId, contentVersion: versions.join("+"), exercise, units, dictItem };
      return { ok: true, ctx };
    },

    async cacheGet(key: string) {
      const { data, error } = await sb.rpc("ai_cache_get", { p_cache_key: key });
      if (error) {
        log("ai_cache_read_failed", { message: String(error.message).slice(0, 200) });
        return null;
      }
      return data && typeof data === "object" && !Array.isArray(data) ? (data as Record<string, unknown>) : null;
    },

    async cachePut(key: string, requestType, body: AiBody, model: string) {
      const { error } = await sb
        .from("ai_cache")
        .upsert({ cache_key: key, request_type: requestType, response: body, model }, { onConflict: "cache_key", ignoreDuplicates: true });
      if (error) throw new Error(`cache write failed: ${error.message}`);
    },

    async recentQuotaUsage(userId: string, sinceMs: number) {
      const { data, error } = await sb
        .from("ai_interactions")
        .select("created_at")
        .eq("user_id", userId)
        .in("response_status", QUOTA_STATUSES)
        .not("model", "is", null)
        .gte("created_at", new Date(sinceMs).toISOString())
        .order("created_at", { ascending: true })
        .limit(1000);
      if (error) throw new Error(`quota lookup failed: ${error.message}`);
      return ((data ?? []) as Row[]).map((r) => Date.parse(r.created_at)).filter((t) => Number.isFinite(t));
    },

    async monthlyUsage(sinceMs: number) {
      const { count, error } = await sb
        .from("ai_interactions")
        .select("id", { count: "exact", head: true })
        .in("response_status", QUOTA_STATUSES)
        .not("model", "is", null)
        .gte("created_at", new Date(sinceMs).toISOString());
      if (error) throw new Error(`budget lookup failed: ${error.message}`);
      return count ?? 0;
    },

    async startInteraction(row: InteractionRow, model: string) {
      const { data, error } = await sb
        .from("ai_interactions")
        .insert({ user_id: row.userId, exercise_id: row.exerciseId, request_type: row.requestType, response_status: "ok", model })
        .select("id")
        .single();
      if (error) throw new Error(`interaction insert failed: ${error.message}`);
      return (data as Row).id as string;
    },

    async finishInteraction(id: string | null, patch: InteractionPatch) {
      if (!id) return;
      const { error } = await sb
        .from("ai_interactions")
        .update({
          response_status: patch.status,
          model: patch.model ?? null,
          input_tokens: patch.inputTokens ?? null,
          output_tokens: patch.outputTokens ?? null,
          latency_ms: patch.latencyMs ?? null,
        })
        .eq("id", id);
      if (error) log("ai_interaction_update_failed", { message: String(error.message).slice(0, 200) });
    },

    async dropInteraction(id: string | null) {
      if (!id) return;
      const { error } = await sb.from("ai_interactions").delete().eq("id", id);
      if (error) log("ai_interaction_delete_failed", { message: String(error.message).slice(0, 200) });
    },

    async logInteraction(row: InteractionRow, status, latencyMs: number | null) {
      const { error } = await sb
        .from("ai_interactions")
        .insert({ user_id: row.userId, exercise_id: row.exerciseId, request_type: row.requestType, response_status: status, model: null, latency_ms: latencyMs });
      if (error) log("ai_interaction_insert_failed", { message: String(error.message).slice(0, 200) });
    },

    callModel(call) {
      return callAnthropic({ apiKey, ...call });
    },

    log,
  };
}
