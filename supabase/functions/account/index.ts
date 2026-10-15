// Edge Function `account` — droits RGPD.
//   GET    /functions/v1/account/export  -> JSON complet des données de l'utilisateur (accès / portabilité)
//   DELETE /functions/v1/account         -> supprime l'utilisateur Auth ; la cascade SQL supprime toutes ses données
// Authorization: Bearer <JWT utilisateur> (vérifié ici).

import { buildExport, EXPORT_TABLES } from "../_shared/account_core.ts";
import { corsHeaders, errorResponse, jsonResponse, preflight, routeAfter } from "../_shared/http.ts";
import { authenticate, serviceClient } from "../_shared/supabase.ts";
import type { SupabaseClient } from "../_shared/supabase.ts";

const PAGE = 1000;
const MAX_PAGES = 500; // garde-fou : 500 000 lignes par table

async function readAll(sb: SupabaseClient, table: string, userColumn: string, order: string, userId: string) {
  const rows: Array<Record<string, unknown>> = [];
  for (let page = 0; page < MAX_PAGES; page++) {
    const { data, error } = await sb
      .from(table)
      .select("*")
      .eq(userColumn, userId)
      .order(order, { ascending: true })
      .order("id", { ascending: true })
      .range(page * PAGE, page * PAGE + PAGE - 1);
    if (error) throw new Error(`export ${table}: ${error.message}`);
    const batch = (data ?? []) as Array<Record<string, unknown>>;
    rows.push(...batch);
    if (batch.length < PAGE) break;
  }
  return rows;
}

Deno.serve(async (req: Request): Promise<Response> => {
  const pre = preflight(req);
  if (pre) return pre;

  try {
    const segments = routeAfter(new URL(req.url).pathname, "account");
    const isExport = req.method === "GET" && segments.length === 1 && segments[0] === "export";
    const isDelete = req.method === "DELETE" && segments.length === 0;
    if (!isExport && !isDelete) {
      return segments.length <= 1 && ["GET", "DELETE"].includes(req.method)
        ? errorResponse(404, "not_found")
        : errorResponse(405, "method_not_allowed", "GET /account/export ou DELETE /account.");
    }

    const user = await authenticate(req);
    if (!user) return errorResponse(401, "unauthorized");
    const sb = serviceClient();

    if (isExport) {
      const tables: Record<string, Array<Record<string, unknown>>> = {};
      for (const t of EXPORT_TABLES) tables[t.table] = await readAll(sb, t.table, t.userColumn, t.order, user.id);
      const payload = buildExport(user, tables, new Date());
      const day = new Date().toISOString().slice(0, 10);
      return new Response(JSON.stringify(payload), {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json; charset=utf-8",
          "Content-Disposition": `attachment; filename="quinze-export-${day}.json"`,
          "Cache-Control": "no-store",
        },
      });
    }

    // DELETE : suppression définitive (auth.users -> cascade sur toutes les tables utilisateur).
    const { error } = await sb.auth.admin.deleteUser(user.id);
    if (error) {
      console.error(JSON.stringify({ event: "account_delete_failed", message: String(error.message).slice(0, 200) }));
      return errorResponse(500, "internal_error", "La suppression du compte a échoué. Réessaie plus tard.");
    }
    return jsonResponse(200, { deleted: true });
  } catch (e) {
    console.error(JSON.stringify({ event: "account_function_error", name: e instanceof Error ? e.name : "unknown", message: e instanceof Error ? e.message.slice(0, 200) : "unknown" }));
    return errorResponse(500, "internal_error", "Erreur interne.");
  }
});
