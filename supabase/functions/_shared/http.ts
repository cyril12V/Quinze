// CORS, réponses JSON, routage par chemin, lecture bornée du corps.
// Standard web uniquement (Request / Response) : testable sous Node comme sous Deno.

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

export function jsonResponse(status: number, body: unknown, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}

export function errorResponse(
  status: number,
  error: string,
  message?: string,
  extra: Record<string, unknown> = {},
): Response {
  return jsonResponse(status, message === undefined ? { error, ...extra } : { error, message, ...extra });
}

/** Réponse à la requête CORS préliminaire, ou null si ce n'est pas un OPTIONS. */
export function preflight(req: Request): Response | null {
  if (req.method !== "OPTIONS") return null;
  return new Response(null, { status: 204, headers: corsHeaders });
}

/**
 * Segments du chemin situés après le nom de la fonction.
 *   /functions/v1/ai/explain-answer -> ["explain-answer"]
 *   /ai/explain-answer              -> ["explain-answer"]   (chemin vu par la fonction)
 *   /account                        -> []
 *   /account/export                 -> ["export"]
 */
export function routeAfter(pathname: string, fnName: string): string[] {
  const parts = pathname.split("/").filter((p) => p.length > 0);
  const idx = parts.lastIndexOf(fnName);
  return idx === -1 ? parts : parts.slice(idx + 1);
}

export type BodyResult = { ok: true; value: unknown } | { ok: false; message: string };

export async function readJsonBody(req: Request, maxChars: number): Promise<BodyResult> {
  let text: string;
  try {
    text = await req.text();
  } catch {
    return { ok: false, message: "Corps de requête illisible." };
  }
  if (text.length > maxChars) return { ok: false, message: "Corps de requête trop volumineux." };
  if (text.trim() === "") return { ok: false, message: "Corps de requête vide (JSON attendu)." };
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, message: "Corps de requête invalide (JSON attendu)." };
  }
}

/** Extrait le jeton d'un en-tête « Authorization: Bearer … ». */
export function bearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? req.headers.get("authorization") ?? "";
  const m = /^Bearer\s+(\S+)\s*$/i.exec(header);
  return m ? m[1] : null;
}
