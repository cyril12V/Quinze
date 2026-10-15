// Export RGPD du compte : assemblage pur (la lecture des tables est faite par la fonction `account`).

/** « server_updated_at » -> « serverUpdatedAt ». Ne touche QUE les noms de colonnes (le contenu des colonnes jsonb est laissé tel quel). */
export function camelizeKey(key: string): string {
  return key.replace(/_([a-z0-9])/g, (_m, c: string) => c.toUpperCase());
}

export function camelizeRow(row: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) out[camelizeKey(k)] = v;
  return out;
}

export const EXPORT_FORMAT = "quinze-export-v1";

/** Tables exportées (toutes filtrées par utilisateur) et colonne de filtre. */
export const EXPORT_TABLES: ReadonlyArray<{ table: string; userColumn: string; order: string }> = [
  { table: "profiles", userColumn: "id", order: "created_at" },
  { table: "user_languages", userColumn: "user_id", order: "started_at" },
  { table: "daily_schedules", userColumn: "user_id", order: "updated_at" },
  { table: "learning_sessions", userColumn: "user_id", order: "local_date" },
  { table: "attempts", userColumn: "user_id", order: "answered_at" },
  { table: "memory_states", userColumn: "user_id", order: "first_seen_at" },
  { table: "user_vocabulary", userColumn: "user_id", order: "added_at" },
  { table: "ai_interactions", userColumn: "user_id", order: "created_at" },
];

export interface AuthUserInfo {
  id: string;
  email?: string | null;
  created_at?: string | null;
  last_sign_in_at?: string | null;
  app_metadata?: { provider?: string; providers?: string[] } | null;
}

export function buildExport(
  user: AuthUserInfo,
  tables: Record<string, Array<Record<string, unknown>>>,
  exportedAt: Date,
): Record<string, unknown> {
  const data: Record<string, unknown> = {};
  for (const { table } of EXPORT_TABLES) {
    data[camelizeKey(table)] = (tables[table] ?? []).map(camelizeRow);
  }
  return {
    format: EXPORT_FORMAT,
    exportedAt: exportedAt.toISOString(),
    account: {
      id: user.id,
      email: user.email ?? null,
      createdAt: user.created_at ?? null,
      lastSignInAt: user.last_sign_in_at ?? null,
      providers: user.app_metadata?.providers ?? (user.app_metadata?.provider ? [user.app_metadata.provider] : []),
    },
    data,
    counts: Object.fromEntries(EXPORT_TABLES.map(({ table }) => [camelizeKey(table), (tables[table] ?? []).length])),
  };
}
