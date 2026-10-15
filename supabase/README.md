# supabase/ — backend de Quinze

Backend Supabase de l'app iOS d'apprentissage de l'anglais « Quinze » : base PostgreSQL protégée par RLS, synchronisation hors ligne par RPC, contenu pédagogique versionné, Edge Functions pour le professeur IA (Claude) et les droits RGPD.

Contrat avec l'app : [`docs/contracts/backend.md`](../docs/contracts/backend.md) · base : [`docs/03-base-de-donnees.md`](../docs/03-base-de-donnees.md) · API : [`docs/04-api.md`](../docs/04-api.md) · déploiement : [`docs/06-deploiement-backend.md`](../docs/06-deploiement-backend.md).

## Contenu du dossier

| Chemin | Rôle |
|---|---|
| `config.toml` | Configuration CLI : auth (confirmation d'e-mail, redirections `quinze://auth-callback` et `quinze://reset-password`, Apple en placeholder), Storage (bucket `content` public), fonctions (`verify_jwt = false`, jeton vérifié dans la fonction), seed local |
| `migrations/` | 7 migrations SQL numérotées (extensions, contenu, utilisateur, triggers, RLS, RPC, IA/Storage) |
| `seed/content_en.sql` | Contenu généré par `tools/build_content.py` (ne pas éditer à la main) |
| `seed/seed.sql` | Documentation du chargement du contenu + vérification |
| `templates/` | Modèles d'e-mails d'authentification en français |
| `functions/ai/` | Edge Function du professeur IA : `POST /ai/<action>` |
| `functions/account/` | Edge Function RGPD : `GET /account/export`, `DELETE /account` |
| `functions/_shared/` | Logique commune : CORS, jeton, client Anthropic, prompts, cache, quotas, validation, repli |
| `functions/_tests/` | Tests TypeScript des modules purs (Node) et du magasin supabase-js (Deno) |
| `functions/.env.example` | Variables des fonctions (`ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `AI_DAILY_QUOTA`, `AI_MONTHLY_BUDGET_REQUESTS`) |
| `tests/` | Tests SQL sur un PostgreSQL 16 jetable |

## Démarrage local

```bash
supabase start                       # PostgreSQL, Auth, Storage, Studio, boîte mail locale (Docker)
supabase db reset                    # migrations + seed du contenu (content_en.sql puis seed.sql)
cp supabase/functions/.env.example supabase/functions/.env     # renseigner ANTHROPIC_API_KEY
supabase functions serve --env-file supabase/functions/.env
```

Studio : http://127.0.0.1:54323 · e-mails de test : http://127.0.0.1:54324 · API : http://127.0.0.1:54321. `supabase status` affiche les clés locales.

## Tests

```bash
# 1. SQL : cluster PostgreSQL 16 jetable (ne tourne pas en root : utilisateur système `pgtest`, créé au besoin),
#    migrations, seed réel chargé deux fois, 180 assertions (RLS, sync, anti-fraude, cascade…)
supabase/tests/run_sql_tests.sh              # KEEP=1 pour conserver le cluster ; PGBIN=… pour une autre installation

# 2. TypeScript, modules purs (prompts, clés de cache, parsing, quotas, validation, repli, client Anthropic, orchestration)
node --test "supabase/functions/_tests/*.test.ts"            # Node ≥ 22.18 (types retirés nativement)

# 3. Deno : tous les tests + magasin supabase-js avec un fetch simulé, et vérification de types
cd supabase/functions
npx -y deno test --allow-read _tests/
npx -y deno check ai/index.ts account/index.ts _tests/*.test.ts
```

## Principes de conception

- **Hors ligne d'abord, idempotent** : identifiants de sessions/tentatives générés par le client ; `sync_push` rejouable ; dernière écriture gagne sur `updated_at` (horloge client) ; curseur de `sync_pull` = `server_updated_at` (horloge serveur, posée par trigger).
- **RLS partout** : lignes propres à l'utilisateur, contenu en lecture seule pour les authentifiés, `ai_cache` réservé au service role, RPC en `SECURITY INVOKER`.
- **IA ancrée sur le contenu validé** : l'exercice, la réponse attendue, la règle et le mot sont rechargés depuis la base par identifiant ; réponses de secours tirées du contenu ; aucune donnée personnelle envoyée au fournisseur ni journalisée ; quota de 24 h glissantes par utilisateur, plafond mensuel global, cache partagé.
- **Dépendances** : uniquement des spécificateurs `npm:` (`npm:@supabase/supabase-js@2`) ; la logique pure (prompts, clés de cache, parsing, quotas, validation) n'utilise ni `Deno` ni le réseau.

## Notes

- Le déploiement pas à pas (projet, `db push`, secrets, fonctions, Sign in with Apple, SMTP, contenu, sauvegardes, supervision, coûts) est dans `docs/06-deploiement-backend.md`.
- Ne jamais committer `supabase/functions/.env` ni la clé `service_role` (couvert par `supabase/.gitignore`).
