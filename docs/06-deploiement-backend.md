# 06 — Déploiement du backend (Supabase)

Procédure complète pour mettre en ligne le backend de Quinze : projet Supabase, migrations, authentification (e-mail + Sign in with Apple), Edge Functions, contenu, sauvegardes, supervision et coûts. Les fichiers sources sont dans `supabase/` (voir `supabase/README.md`) ; l'API est décrite dans `docs/04-api.md`, la base dans `docs/03-base-de-donnees.md`.

> Les noms de menus et les offres Supabase / Apple / Anthropic évoluent : ce document donne la démarche et les commandes ; **vérifier les prix et les limites sur les pages officielles** avant de s'engager.

## 1. Prérequis

| Outil | Usage |
|---|---|
| Compte Supabase (organisation) | héberger le projet |
| [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) ≥ 2.x (`brew install supabase/tap/supabase` ou `npx supabase`) | migrations, secrets, fonctions |
| `psql` (PostgreSQL ≥ 15) | charger le seed du contenu |
| Compte Anthropic + clé API | professeur IA |
| Compte Apple Developer (programme payant) | Sign in with Apple |
| Docker (facultatif) | `supabase start` en local |
| Un domaine d'expédition d'e-mails (ex. `monquinze.fr`) | SMTP de production |

Variables utilisées dans la suite :

```bash
export PROJECT_REF=<ref du projet>        # 20 caractères, visible dans l'URL du tableau de bord
export URL="https://$PROJECT_REF.supabase.co"
export ANON=<clé anon / publishable>      # Project Settings > API
export SERVICE_ROLE_KEY=<clé service_role> # secrète : jamais dans l'app ni dans git
export SUPABASE_DB_URL="postgresql://postgres.$PROJECT_REF:<mot de passe>@<hôte du pooler>:5432/postgres"  # Settings > Database
```

## 2. Créer le projet

1. Tableau de bord Supabase > **New project** (ou `supabase projects create quinze --org-id <org> --region eu-west-3 --db-password '<fort>'`).
2. **Région dans l'UE** (Paris `eu-west-3`, Francfort `eu-central-1` ou Irlande `eu-west-1`) : les utilisateurs sont francophones et soumis au RGPD ; garder la même région pour Edge Functions et base.
3. Mot de passe de base de données fort, conservé dans un gestionnaire de secrets.
4. Après création : noter la **Project ref**, la clé **anon/publishable** (dans l'app) et la clé **service_role** (secrète).
5. Recommandé pour la production : plan **Pro** (sauvegardes quotidiennes, pas de mise en pause), puis *Settings > Database > Network restrictions* si l'accès direct à la base doit être limité.

## 3. Lier le dépôt et appliquer les migrations

```bash
cd /chemin/vers/quinze
supabase login
supabase link --project-ref "$PROJECT_REF"      # demande le mot de passe de la base
supabase db push --dry-run                       # liste les migrations qui seront appliquées
supabase db push                                 # applique supabase/migrations/*.sql dans l'ordre
```

Les 7 migrations créent : extensions, tables de contenu et utilisateur, index, contraintes, triggers (`updated_at`, `server_updated_at`, anti-fraude, profil à l'inscription), RLS, RPC `sync_push` / `sync_pull` / `content_manifest`, fonctions d'appui IA et bucket Storage `content`. Elles sont conçues pour être appliquées **une fois, dans l'ordre**. Pour une évolution du schéma : créer une nouvelle migration (`supabase migration new <nom>`), la tester (`supabase/tests/run_sql_tests.sh`), puis `supabase db push`.

Contrôle (SQL Editor) :

```sql
select count(*) filter (where not relrowsecurity) as tables_sans_rls
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r';          -- doit valoir 0
select id, public from storage.buckets where id = 'content';  -- content | true
```

## 4. Authentification : e-mail, redirections, modèles, SMTP

La configuration est portée par `supabase/config.toml` (sections `[auth]`, `[auth.email]`, `[auth.email.template.*]`, `[auth.external.apple]`). Pour l'appliquer au projet hébergé :

```bash
supabase config push        # pousse la configuration (auth, API, storage…) vers le projet lié
```

> Vérifier ensuite dans le tableau de bord (*Authentication*) que les valeurs ci-dessous sont bien en place ; ce sont elles qui comptent en production.

### 4.1 Redirections (liens des e-mails → app)

*Authentication > URL Configuration* :

| Réglage | Valeur |
|---|---|
| Site URL | `quinze://auth-callback` |
| Redirect URLs | `quinze://auth-callback`, `quinze://reset-password` |

Les liens des e-mails (confirmation, réinitialisation) passent par `https://<ref>.supabase.co/auth/v1/verify?…` puis redirigent vers ces URL avec les jetons dans le fragment (`#access_token=…`). L'app doit déclarer le schéma d'URL `quinze` (Info.plist > URL Types) et traiter l'URL reçue (`supabase.auth.session(from:)`). Le client passe `redirect_to=quinze://auth-callback` à l'inscription et `redirect_to=quinze://reset-password` à `recover`. Alternative plus robuste à terme : **Universal Links** (un schéma personnalisé peut être revendiqué par une autre app) ; il suffira alors d'ajouter l'URL `https://…` dans *Redirect URLs*.

### 4.2 Confirmation d'e-mail et mots de passe

*Authentication > Sign In / Providers > Email* : **Confirm email = activé** (déjà `enable_confirmations = true`), *Secure email change*, mot de passe ≥ 8 caractères avec lettres et chiffres, délai de 60 s entre deux e-mails. *Sign In / Providers* : **Allow anonymous sign-ins = désactivé**.

### 4.3 Modèles d'e-mail (français)

*Authentication > Email Templates* : coller le contenu de `supabase/templates/confirmation.html` (« Confirm signup »), `recovery.html` (« Reset password »), `email_change.html` (« Change email address »), `reauthentication.html` (« Reauthentication »), avec les objets définis dans `config.toml`. (`supabase config push` les envoie aussi.) Variables utilisées : `{{ .ConfirmationURL }}`, `{{ .Token }}`, `{{ .NewEmail }}`.

### 4.4 SMTP personnalisé (obligatoire en production)

Le SMTP intégré de Supabase est limité à quelques e-mails par heure et réservé aux tests. *Authentication > SMTP Settings* : activer un SMTP personnalisé (Resend, Postmark, Brevo… hébergement UE de préférence), expéditeur `no-reply@<votre domaine>`, avec **SPF, DKIM et DMARC** configurés sur le domaine. Ajuster ensuite *Authentication > Rate Limits* (e-mails par heure) à la volumétrie attendue. Optionnel contre les inscriptions automatisées : activer un CAPTCHA (hCaptcha / Turnstile) dans *Authentication > Attack Protection*.

## 5. Sign in with Apple

Quinze propose e-mail + Apple. Pour une app iOS **native**, Supabase vérifie le jeton d'identité fourni par l'app (`signInWithIdToken`) : seul l'identifiant du bundle est nécessaire (pas de clé secrète).

1. **Apple Developer > Certificates, Identifiers & Profiles > Identifiers** : l'App ID de l'app (bundle id, ex. `fr.monquinze.Quinze`) doit avoir la capability **Sign in with Apple** activée.
2. **Xcode** : target > *Signing & Capabilities* > **+ Capability > Sign in with Apple**.
3. **Supabase > Authentication > Sign In / Providers > Apple** : *Enable*, champ **Client IDs** = le bundle id (plusieurs possibles, séparés par des virgules). Laisser le secret vide si seul le flux natif est utilisé. (En local / `config push` : passer `[auth.external.apple] enabled = true`, définir `SUPABASE_AUTH_EXTERNAL_APPLE_CLIENT_ID` ; `skip_nonce_check` doit rester `false`.)
4. **Dans l'app** : générer un `nonce` aléatoire, envoyer son SHA-256 à Apple (`request.nonce`), puis appeler `auth.signInWithIdToken(provider: .apple, idToken:, nonce: <nonce brut>)` (voir `docs/04-api.md` § 2.3).
5. **Nom et e-mail** : Apple ne fournit le nom qu'à la première autorisation ; l'app le recopie dans `profiles.display_name`. L'e-mail peut être un relais privé (`…@privaterelay.appleid.com`) ; pour que des e-mails transactionnels lui parviennent, enregistrer le domaine d'expédition dans *Apple Developer > Services > Sign in with Apple for Email Communication*.
6. **Flux web / OAuth (si un jour utilisé)** : créer un *Services ID* et une clé (`.p8`), générer le « client secret » (JWT signé, **valable 6 mois au maximum** : planifier le renouvellement), renseigner *Client ID* (Services ID), *Secret*, et l'URL de rappel `https://<ref>.supabase.co/auth/v1/callback` côté Apple.
7. **Suppression de compte** : l'App Store impose la suppression in-app (réalisée par `DELETE /functions/v1/account`). Pour un compte créé avec Apple, Apple recommande en plus de **révoquer le jeton Apple** (endpoint `appleid.apple.com/auth/revoke`) ; Supabase ne le fait pas automatiquement — à prévoir côté app ou dans la fonction `account` avant publication.

## 6. Secrets et Edge Functions

### 6.1 Secrets

```bash
cp supabase/functions/.env.example supabase/functions/.env     # fichier ignoré par git
$EDITOR supabase/functions/.env                                 # ANTHROPIC_API_KEY, quotas…
supabase secrets set --env-file supabase/functions/.env
supabase secrets list
```

| Variable | Rôle | Défaut |
|---|---|---|
| `ANTHROPIC_API_KEY` | clé API Anthropic (sans elle : réponses de secours uniquement) | — |
| `ANTHROPIC_MODEL` | modèle utilisé | `claude-haiku-5-5` |
| `AI_DAILY_QUOTA` | demandes par utilisateur sur 24 h glissantes | `40` |
| `AI_MONTHLY_BUDGET_REQUESTS` | plafond mensuel global d'appels au fournisseur | `200000` |
| `ANTHROPIC_TIMEOUT_MS` | délai par tentative | `20000` |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` sont **injectées automatiquement** : ne pas les définir. Recommandé : fixer en plus une **limite de dépense mensuelle** dans la console Anthropic (filet de sécurité indépendant du plafond applicatif).

### 6.2 Déploiement

```bash
supabase functions deploy ai
supabase functions deploy account
supabase functions list
```

`config.toml` fixe `verify_jwt = false` pour les deux fonctions : l'authentification est vérifiée **dans** la fonction (`auth.getUser` avec le jeton de l'appelant, `401 {"error":"unauthorized"}` sinon) ; cela évite aussi les refus de la passerelle pour la requête CORS `OPTIONS` et avec les clés de signature asymétriques. (Équivalent en ligne de commande : `--no-verify-jwt`.)

Test local avant déploiement : `supabase start`, puis `supabase functions serve --env-file supabase/functions/.env`.

## 7. Publier le contenu pédagogique

Deux opérations indissociables : **(a)** le bundle JSON dans Storage, **(b)** les lignes de contenu en base.

```bash
# 0. (Re)générer si le contenu a changé
python3 tools/build_content.py            # -> Content/build/en.json + supabase/seed/content_en.sql
VERSION=$(python3 -c "import json;print(json.load(open('Content/build/en.json'))['contentVersion'])")   # ex. 1.0.0

# (a) Bundle dans le bucket public `content`, chemin <langue>/<version>.json
curl -X POST "$URL/storage/v1/object/content/en/$VERSION.json" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" -H "x-upsert: true" --data-binary @Content/build/en.json
#   ou tableau de bord : Storage > content > créer le dossier `en` > Upload (renommer le fichier en 1.0.0.json)

# (b) Lignes de contenu + version courante (idempotent, une transaction)
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/content_en.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/seed.sql      # vérification + résumé
```

Vérifier la cohérence manifeste ↔ fichier :

```bash
curl -s -X POST "$URL/rest/v1/rpc/content_manifest" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" \
     -H "Content-Type: application/json" -d '{"p_language_id":"en"}'                  # version, bundle_path, sha256
curl -s "$URL/storage/v1/object/public/content/en/$VERSION.json" | sha256sum         # doit égaler le sha256 du manifeste
```

Règles : déposer le **fichier avant** de charger le seed (sinon des clients voient une version dont le bundle est introuvable) ; ne jamais réécrire un fichier déjà publié sous le même chemin (le CDN le met en cache) : toute modification = nouvelle `contentVersion` ; ne jamais supprimer un exercice, une unité ou un mot (les marquer `deprecated`). Le seed est rejouable : recharger la même version met simplement à jour ses lignes. Voir `docs/03-base-de-donnees.md` § 5.

Local : `supabase db reset` applique les migrations puis charge automatiquement `content_en.sql` et `seed.sql` (voir `[db.seed]` dans `config.toml`).

## 8. Vérifications après déploiement

```bash
# Sans jeton : refusé
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$URL/functions/v1/ai/explain-rule" -H "apikey: $ANON"            # 401
curl -s -o /dev/null -w "%{http_code}\n" "$URL/rest/v1/exercises?limit=1" -H "apikey: $ANON"                        # 401 (anon : aucun droit)
# Compte de test : inscription, confirmation par e-mail, connexion
curl -s -X POST "$URL/auth/v1/signup" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"email":"test+quinze@<domaine>","password":"MotDePasse123"}'
# Avec le JWT obtenu après confirmation :
curl -s -X POST "$URL/rest/v1/rpc/sync_pull" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{"p_language_id":"en","p_since":"1970-01-01T00:00:00Z"}'
curl -s -X POST "$URL/functions/v1/ai/explain-rule" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
     -d '{"languageCode":"en","level":2,"unitId":"en.g01.subject_pronouns","detail":"short"}'                       # 200, source "ai"
curl -s -X DELETE "$URL/functions/v1/account" -H "apikey: $ANON" -H "Authorization: Bearer $JWT"                    # {"deleted":true}
```

Liste de contrôle : migrations appliquées · RLS = 0 table sans RLS · bucket `content` public · seed chargé (60 leçons, 680 exercices) · `content_manifest('en')` renvoie la bonne version et le bon SHA-256 · confirmation d'e-mail reçue et lien ouvrant l'app · SMTP personnalisé · Apple opérationnel sur un vrai appareil · `ANTHROPIC_API_KEY` posée et quota testé · suppression de compte testée · sauvegardes actives (§ 9) · limite de dépense Anthropic fixée.

## 9. Sauvegardes et restauration

- **Sauvegardes Supabase** : sauvegardes quotidiennes automatiques sur les offres payantes (durée de rétention selon l'offre) ; **Point-in-Time Recovery** en option payante pour une restauration à la minute près. Vérifier l'offre souscrite (*Database > Backups*) et activer la PITR si la perte d'une journée d'apprentissage est inacceptable. Les offres gratuites ne conviennent pas à la production.
- **Sauvegarde logique indépendante** (hebdomadaire, hors Supabase, chiffrée, stockée dans l'UE) :

```bash
supabase db dump --linked -f backup/schema.sql                            # schéma public
supabase db dump --linked --data-only -f backup/data.sql                  # données (public)
pg_dump "$SUPABASE_DB_URL" --data-only --table=auth.users --table=auth.identities -f backup/auth.sql   # comptes (FK des tables utilisateur)
```

- **Storage** : les bundles de contenu sont reproductibles depuis le dépôt (`Content/build/en.json`) : pas de sauvegarde dédiée.
- **Restauration** : (1) créer un projet vide, (2) `supabase link` + `supabase db push`, (3) restaurer `auth.sql` puis `data.sql`, (4) republier le contenu (§ 7), (5) redéployer secrets et fonctions (§ 6). **Faire un exercice de restauration** sur un projet de test avant la mise en production et à chaque changement majeur de schéma.
- **RGPD** : une suppression de compte disparaît des sauvegardes à leur expiration ; documenter ce délai dans la politique de confidentialité.

## 10. Supervision

- **Journaux** (*Logs*) : *Edge Functions* (lignes JSON `ai_provider_error`, `ai_unparsable_output`, `ai_monthly_budget_reached`, `ai_function_error`, `account_delete_failed` — sans texte d'élève), *Postgres*, *Auth*, *API Gateway*. Pour l'archivage ou l'alerte : *Log Drains* vers l'outil de l'équipe.
- **Rapports** : *Reports* (API, base, Auth, Storage), *Advisors* (sécurité et performance : doit rester sans alerte RLS).
- **Suivi de l'IA** (SQL Editor) :

```sql
-- Volume, cache, latence, jetons par jour (30 jours)
select date_trunc('day', created_at)::date as jour, response_status, count(*) as n,
       round(avg(latency_ms)) as latence_ms, sum(input_tokens) as jetons_in, sum(output_tokens) as jetons_out
from ai_interactions where created_at > now() - interval '30 days' group by 1, 2 order by 1 desc, 2;

-- Avancement du plafond mensuel (mois civil UTC)
select count(*) as appels_payants_ce_mois
from ai_interactions
where response_status in ('ok','fallback') and model is not null and created_at >= date_trunc('month', now() at time zone 'utc');

-- Taux de réponses de secours et d'erreurs fournisseur (7 jours)
select response_status, count(*) from ai_interactions where created_at > now() - interval '7 days' group by 1;
```

- **Alertes à mettre en place** : > 5 % de `error` ou de `fallback` sur une heure (panne ou changement de format du modèle) ; plafond mensuel atteint à plus de 80 % ; erreurs 5xx de l'API ; taux de `429` Auth anormal ; espace disque / CPU de la base (*Reports*).
- **Rotation** : clés API (Anthropic, SMTP) à renouveler à intervalle fixe ; mot de passe de la base ; secret Apple web si utilisé (≤ 6 mois).
- **Maintenance** : planifier `public.ai_purge(90, 180)` (voir `docs/03-base-de-donnees.md` § 6).

## 11. Coûts

| Poste | Ordre de grandeur / règle |
|---|---|
| **Supabase** | Abonnement de base par organisation (plan Pro) + ressources (calcul, stockage, transfert) au-delà des quotas inclus. Quinze est léger : quelques lignes par session, un bundle de ~1,2 Mo téléchargé une fois par installation et par version. Consulter supabase.com/pricing. |
| **Anthropic (IA)** | Principal poste variable. Par demande non mise en cache : ~1 000 à 2 500 jetons en entrée (prompt système ≈ 450 + contenu validé + réponse de l'élève) et ~150 à 400 jetons en sortie. Coût ≈ (jetons_in × prix_entrée + jetons_out × prix_sortie) / 1 000 000. |
| **E-mails** | SMTP tiers : volume = inscriptions + réinitialisations (faible), souvent dans une offre gratuite/d'entrée. |
| **Apple Developer** | Adhésion annuelle (déjà nécessaire pour publier l'app). |

Exemple de calcul **avec des prix hypothétiques à remplacer par les tarifs réels du modèle choisi** : à 1 $ par million de jetons en entrée et 5 $ en sortie, 1 000 demandes de 2 000 jetons en entrée et 300 en sortie coûtent 2 × 1 + 0,3 × 5 = **3,50 $**, soit ~0,0035 $ par demande. Le cache (explications identiques d'un utilisateur à l'autre) réduit ce coût ; le suivi SQL du § 10 donne les jetons réels.

Dimensionner les plafonds : `AI_MONTHLY_BUDGET_REQUESTS ≈ budget mensuel / coût moyen par demande` (avec l'exemple : 350 $ ≈ 100 000 demandes). `AI_DAILY_QUOTA` borne le coût par utilisateur : au maximum 40 × 30 = 1 200 demandes par mois et par utilisateur, très au-dessus d'un usage normal (quelques explications par jour). Atteindre le plafond mensuel ne coupe pas l'app : les réponses de secours (contenu validé) prennent le relais.

## 12. Dépannage

| Symptôme | Piste |
|---|---|
| `db push` échoue sur `storage.objects` ou `auth.users` | exécuter avec le rôle `postgres` (le mot de passe de `supabase link`), pas un rôle limité |
| L'app reçoit `401` sur les RPC | JWT expiré (renouveler avec le refresh token) ou clé `anon` envoyée à la place du JWT utilisateur |
| `403 42501` sur une écriture | RLS : `user_id` ≠ utilisateur, colonne non modifiable, ou tentative déjà résolue (immuable) |
| `sync_push` : beaucoup de `rejected` | contenu du serveur plus ancien que celui de l'app (publier la nouvelle version, § 7) ou identifiants d'exercice/unité inconnus |
| `content_manifest` renvoie `null` | seed non chargé (§ 7) |
| Le lien de confirmation n'ouvre pas l'app | URL absente de *Redirect URLs*, schéma `quinze` non déclaré dans l'app, ou client mail qui bloque le lien |
| `ai` répond `503` | `ANTHROPIC_API_KEY` absente, fournisseur en erreur, plafond mensuel atteint : voir les journaux de la fonction ; la réponse contient `fallback` |
| `ai` répond `429` | quota de 24 h glissantes atteint (`resetAt`) ; vérifier `AI_DAILY_QUOTA` |
| Réponses IA qui ne changent pas après une mise à jour du contenu | la version du contenu n'a pas changé : le cache est valide tant que `content_version` est identique ; publier une nouvelle version |
