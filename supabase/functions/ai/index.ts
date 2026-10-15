// Edge Function `ai` — professeur IA de Quinze (Claude).
//   POST /functions/v1/ai/<action>   action ∈ explain-answer | explain-word | explain-rule | follow-up | grade-answer
// Authorization: Bearer <JWT utilisateur> (vérifié ici). Corps et réponses en JSON camelCase.

import { DEFAULT_MODEL } from "../_shared/anthropic.ts";
import { handleAi } from "../_shared/ai_core.ts";
import { makeAiDeps } from "../_shared/ai_store.ts";
import { errorResponse, jsonResponse, preflight, readJsonBody, routeAfter } from "../_shared/http.ts";
import { DEFAULT_DAILY_QUOTA, DEFAULT_MONTHLY_BUDGET, parsePositiveInt } from "../_shared/quota.ts";
import { authenticate, env, serviceClient } from "../_shared/supabase.ts";
import { isAiAction, LIMITS } from "../_shared/validation.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  const pre = preflight(req);
  if (pre) return pre;

  try {
    if (req.method !== "POST") return errorResponse(405, "method_not_allowed", "Utiliser POST.");

    const user = await authenticate(req);
    if (!user) return errorResponse(401, "unauthorized");

    const action = routeAfter(new URL(req.url).pathname, "ai")[0] ?? "";
    if (!isAiAction(action)) return errorResponse(404, "not_found", `Action inconnue : « ${action} ».`);

    const body = await readJsonBody(req, LIMITS.bodyChars);
    if (!body.ok) return errorResponse(400, "bad_request", body.message);

    const deps = makeAiDeps(
      serviceClient(),
      {
        model: env("ANTHROPIC_MODEL") ?? DEFAULT_MODEL,
        dailyQuota: parsePositiveInt(env("AI_DAILY_QUOTA"), DEFAULT_DAILY_QUOTA),
        monthlyBudget: parsePositiveInt(env("AI_MONTHLY_BUDGET_REQUESTS"), DEFAULT_MONTHLY_BUDGET),
        timeoutMs: parsePositiveInt(env("ANTHROPIC_TIMEOUT_MS"), 20_000),
      },
      env("ANTHROPIC_API_KEY"),
    );

    const result = await handleAi(user.id, action, body.value, deps);
    const headers: Record<string, string> = {};
    if (result.status === 429 && typeof result.body.resetAt === "string") {
      const secs = Math.max(1, Math.ceil((Date.parse(result.body.resetAt) - Date.now()) / 1000));
      headers["Retry-After"] = String(secs);
    }
    return jsonResponse(result.status, result.body, headers);
  } catch (e) {
    console.error(JSON.stringify({ event: "ai_function_error", name: e instanceof Error ? e.name : "unknown", message: e instanceof Error ? e.message.slice(0, 200) : "unknown" }));
    return errorResponse(500, "internal_error", "Erreur interne.");
  }
});
