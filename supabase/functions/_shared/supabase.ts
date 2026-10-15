// Accès à l'environnement Deno et à Supabase (clients, authentification de l'appelant).
// Seul module de _shared (avec ai_store.ts) qui dépend de Deno / de supabase-js.

import { createClient } from "npm:@supabase/supabase-js@2";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { bearerToken } from "./http.ts";
import type { AuthUserInfo } from "./account_core.ts";

export type { SupabaseClient };

export function env(name: string): string | undefined {
  const v = Deno.env.get(name);
  return v === undefined || v === "" ? undefined : v;
}

function requireEnv(name: string): string {
  const v = env(name);
  if (!v) throw new Error(`Variable d'environnement manquante : ${name}`);
  return v;
}

/** Client service role : contourne la RLS. À n'utiliser qu'après avoir authentifié l'appelant. */
export function serviceClient(): SupabaseClient {
  return createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

export interface AuthedUser extends AuthUserInfo {
  id: string;
}

/**
 * Vérifie le jeton de l'appelant auprès de Supabase Auth (supabase-js `auth.getUser(jwt)`).
 * Renvoie null si l'en-tête est absent, le jeton invalide/expiré, ou s'il s'agit d'un jeton
 * sans utilisateur (clé anon seule).
 */
export async function authenticate(req: Request): Promise<AuthedUser | null> {
  const token = bearerToken(req);
  if (!token) return null;
  try {
    const client = createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const { data, error } = await client.auth.getUser(token);
    if (error || !data?.user?.id) return null;
    const u = data.user;
    return {
      id: u.id,
      email: u.email ?? null,
      created_at: u.created_at ?? null,
      last_sign_in_at: u.last_sign_in_at ?? null,
      app_metadata: u.app_metadata ?? null,
    };
  } catch {
    return null;
  }
}
