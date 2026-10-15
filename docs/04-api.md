# 04 — API du backend

Référence des endpoints utilisés par l'app iOS. Le contrat formel (formes JSON, ordre de traitement, limites) est `docs/contracts/backend.md` ; le schéma et la sécurité sont décrits dans `docs/03-base-de-donnees.md`.

## 1. Conventions

- **Base** : `https://<ref>.supabase.co` (local : `http://127.0.0.1:54321`).
  - Auth : `/auth/v1/…` — API REST/PostgREST : `/rest/v1/…` — RPC : `/rest/v1/rpc/<nom>` — Storage : `/storage/v1/…` — Edge Functions : `/functions/v1/<nom>/…`.
- **En-têtes** : `apikey: <clé anon / publishable>` sur tous les appels ; `Authorization: Bearer <access_token>` (JWT de l'utilisateur) sur tout ce qui n'est pas public ; `Content-Type: application/json`.
- **Dates** : ISO 8601 UTC avec fuseau et millisecondes (`2026-10-13T07:12:44.120Z`). Jours locaux `yyyy-MM-dd`, heures `HH:mm`.
- **Corps** : les RPC et PostgREST utilisent les noms de colonnes en `snake_case` ; les Edge Functions utilisent du JSON `camelCase`.
- Dans les exemples : `$URL` = URL du projet, `$ANON` = clé anon, `$JWT` = jeton d'accès de l'utilisateur.

### Correspondance avec les endpoints indicatifs du cahier des charges

Les chemins du cahier des charges sont indicatifs : ils sont réalisés par les services Supabase ci-dessous (l'app utilise le SDK Supabase ou ces appels HTTP).

| Endpoint indicatif | Réalisation | § |
|---|---|---|
| `auth/register` | `POST /auth/v1/signup` | 2.1 |
| `auth/login` | `POST /auth/v1/token?grant_type=password` | 2.2 |
| `auth/apple` | `POST /auth/v1/token?grant_type=id_token` (`provider: apple`) | 2.3 |
| `auth/refresh` | `POST /auth/v1/token?grant_type=refresh_token` | 2.4 |
| `auth/logout` | `POST /auth/v1/logout` | 2.5 |
| `auth/forgot-password`, `auth/reset-password` | `POST /auth/v1/recover`, puis `PUT /auth/v1/user` | 2.6 |
| `GET /me`, `PATCH /me` | `GET`/`PATCH /rest/v1/profiles?id=eq.<uid>` (+ `GET /auth/v1/user`) | 3.1 |
| `DELETE /me`, export des données | `DELETE /functions/v1/account`, `GET /functions/v1/account/export` | 6 |
| `learning/…` (langue, placement, niveau) | `POST /rest/v1/user_languages?on_conflict=user_id,language_id` | 3.2 |
| `learning/content` (manifeste, bundle) | RPC `content_manifest` + Storage public | 4.3 |
| `learning/sync` (envoi) | RPC `sync_push` | 4.1 |
| `learning/sync` (réception, restauration) | RPC `sync_pull` | 4.2 |
| `learning/sessions`, `attempts`, `progress` | via `sync_push`/`sync_pull` ; lecture directe possible (`/rest/v1/learning_sessions`…) | 4, 3.5 |
| `dictionary/…` (recherche, fiche, mes mots) | `GET /rest/v1/dictionary_items`, `user_vocabulary` via sync | 3.4 |
| `ai/…` | Edge Function `ai/<action>` | 5 |
| `settings` (horaires, préférences, notifications) | `daily_schedules`, `profiles.pedagogical_prefs` / `notification_prefs` | 3.1, 3.3 |

## 2. Authentification (Supabase Auth)

E-mail + mot de passe avec **confirmation obligatoire**, et Sign in with Apple. Les e-mails (confirmation, réinitialisation) contiennent un lien qui ramène dans l'app par le schéma `quinze://` : `quinze://auth-callback` (confirmation, connexion) et `quinze://reset-password` (réinitialisation). Ces deux URL sont déclarées dans `additional_redirect_urls`.

### 2.1 Inscription

```bash
curl -X POST "$URL/auth/v1/signup?redirect_to=quinze://auth-callback" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d '{"email":"emma@example.com","password":"MotDePasse123","data":{"display_name":"Emma"}}'
```

Réponse `200` : l'utilisateur (`id`, `email`, `confirmation_sent_at`) **sans session** tant que l'e-mail n'est pas confirmé. Le trigger crée aussitôt le profil (`display_name` repris de `data`). Le lien de l'e-mail renvoie vers `quinze://auth-callback#access_token=…&refresh_token=…&type=signup`. Renvoyer l'e-mail : `POST /auth/v1/resend` `{"type":"signup","email":"…"}`.

### 2.2 Connexion

```bash
curl -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d '{"email":"emma@example.com","password":"MotDePasse123"}'
```

Réponse `200` : `{"access_token":"…","token_type":"bearer","expires_in":3600,"refresh_token":"…","user":{…}}`.

### 2.3 Sign in with Apple (natif)

L'app obtient un `identityToken` Apple (et un `nonce` dont le SHA-256 a été passé à Apple), puis :

```bash
curl -X POST "$URL/auth/v1/token?grant_type=id_token" -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d '{"provider":"apple","id_token":"<identityToken>","nonce":"<nonce brut>"}'
```

Même réponse qu'en 2.2. Le nom éventuellement fourni par Apple n'est transmis qu'à la première connexion : l'app le copie dans `profiles.display_name` (§ 3.1). Configuration : `docs/06-deploiement-backend.md` § 5.

### 2.4 Renouvellement, 2.5 Déconnexion, 2.6 Mot de passe oublié

```bash
# Renouveler la session (rotation du refresh_token : conserver le NOUVEAU)
curl -X POST "$URL/auth/v1/token?grant_type=refresh_token" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"refresh_token":"…"}'
# Déconnexion (révoque la session)
curl -X POST "$URL/auth/v1/logout" -H "apikey: $ANON" -H "Authorization: Bearer $JWT"
# Mot de passe oublié : envoie un e-mail dont le lien ouvre quinze://reset-password
curl -X POST "$URL/auth/v1/recover?redirect_to=quinze://reset-password" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"email":"emma@example.com"}'
# Après ouverture du lien (session de récupération) : nouveau mot de passe
curl -X PUT "$URL/auth/v1/user" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{"password":"NouveauMotDePasse456"}'
```

### 2.7 Erreurs d'authentification

Format : `{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}`.

| HTTP | `error_code` | Cas |
|---|---|---|
| 400 | `invalid_credentials` | e-mail ou mot de passe incorrect |
| 400 | `email_not_confirmed` | connexion avant confirmation de l'e-mail |
| 422 | `weak_password` | moins de 8 caractères ou sans lettres + chiffres |
| 422 | `email_exists` / `user_already_exists` | e-mail déjà inscrit (selon la configuration, la réponse peut être neutralisée) |
| 429 | `over_email_send_rate_limit`, `over_request_rate_limit` | trop de demandes (≥ 60 s entre deux e-mails) |
| 400/401 | `refresh_token_not_found`, `session_expired`, `bad_jwt` | session à rouvrir : renvoyer vers l'écran de connexion |

## 3. Accès direct (PostgREST)

Toutes ces routes exigent `Authorization: Bearer $JWT` ; la RLS limite chaque utilisateur à ses lignes. Les en-têtes `Prefer: return=representation` (renvoyer la ligne) et `Prefer: resolution=merge-duplicates` (upsert) sont standards.

### 3.1 Profil — `profiles`

```bash
# Lire
curl "$URL/rest/v1/profiles?id=eq.$UID&select=id,email,display_name,pedagogical_prefs,notification_prefs,created_at" -H "apikey: $ANON" -H "Authorization: Bearer $JWT"
# Modifier (seules 3 colonnes sont modifiables)
curl -X PATCH "$URL/rest/v1/profiles?id=eq.$UID" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" -H "Prefer: return=representation" \
  -d '{"display_name":"Emma","pedagogical_prefs":{"aiDetail":"short"},"notification_prefs":{"reminders":true}}'
```

Un `PATCH` portant sur `email` ou `id` → `403 {"code":"42501",…}` (l'e-mail se change via `PUT /auth/v1/user`, et le profil le recopie).

### 3.2 Langue et niveau — `user_languages`

```bash
curl -X POST "$URL/rest/v1/user_languages?on_conflict=user_id,language_id" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" -H "Prefer: resolution=merge-duplicates,return=minimal" \
  -d '{"language_id":"en","estimated_level":1,"start_lesson_sequence":10,"placement":{"score":7},"started_at":"2026-10-13T07:00:00.000Z","updated_at":"2026-10-13T07:00:00.000Z"}'
```

`user_id` est renseigné par défaut (`auth.uid()`). Réponse `201`. Une écriture dont `updated_at` est plus ancien que celui de la ligne serveur est ignorée silencieusement (dernière écriture gagne).

### 3.3 Horaires — `daily_schedules`

```bash
curl -X POST "$URL/rest/v1/daily_schedules?on_conflict=user_id" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" -H "Prefer: resolution=merge-duplicates,return=minimal" \
  -d '{"morning_time":"09:00","afternoon_time":"14:00","evening_time":"20:00","timezone":"Europe/Paris","enabled":true,"safety_window_minutes":120,"early_start_minutes":60,"updated_at":"2026-10-13T07:00:00.000Z"}'
```

`timezone` doit être un identifiant IANA connu de PostgreSQL (sinon `400 {"code":"22023",…}`).

### 3.4 Dictionnaire — lecture du contenu

```bash
# Recherche par préfixe (index sur lower(word))
curl "$URL/rest/v1/dictionary_items?language_id=eq.en&word=ilike.thr*&select=id,word,translation,pronunciation&order=word&limit=20" -H "apikey: $ANON" -H "Authorization: Bearer $JWT"
# Fiche complète
curl "$URL/rest/v1/dictionary_items?id=eq.en.d.through&select=*" -H "apikey: $ANON" -H "Authorization: Bearer $JWT"
```

Réponse : `[{"id":"en.d.through","word":"through","translation":"à travers","definition":"…","examples":[{"text":"…","translation":"…"}],"pronunciation":"/θruː/","data":{…}, …}]`. « Mes mots » (`user_vocabulary`) se synchronisent via `sync_push`/`sync_pull` (§ 4) ; une lecture directe `GET /rest/v1/user_vocabulary?select=*` est possible. Le contenu (`languages`, `learning_units`, `lessons`, `exercises`, `dictionary_items`) est en lecture seule ; l'app lit en priorité son bundle local (§ 4.3).

### 3.5 Lectures de suivi (optionnel)

`GET /rest/v1/learning_sessions?language_id=eq.en&local_date=gte.2026-10-01&select=*`, `GET /rest/v1/memory_states?next_review_at=lte.<now>`, `GET /rest/v1/ai_interactions?select=request_type,response_status,created_at` (ses propres lignes).

### 3.6 Erreurs PostgREST

Format : `{"code":"…","message":"…","details":null,"hint":null}`.

| HTTP | `code` | Cause |
|---|---|---|
| 401 | `PGRST301` / `PGRST303` | JWT expiré ou invalide → renouveler la session (§ 2.4) |
| 401 | `42501` (rôle `anon`) | appel sans JWT utilisateur |
| 403 | `42501` | RLS refusée (`new row violates row-level security policy`), colonne non modifiable, tentative immuable, fonction réservée |
| 400 | `23514` | contrainte `CHECK` (énumération, borne) |
| 400 | `22023`, `22P02`, `22007` | valeur invalide (UUID, date, fuseau horaire, payload de RPC) |
| 409 | `23505` | unicité (par ex. un créneau déjà occupé : `(user_id, language_id, local_date, slot)`) |
| 409 | `23503` | clé étrangère (exercice, unité ou mot inconnu) |
| 404 | `PGRST202` | RPC inconnue ou paramètres incorrects |
| 413 | `PT413` | lot `sync_push` trop volumineux |

## 4. RPC de synchronisation

`POST /rest/v1/rpc/<nom>` avec `Authorization: Bearer $JWT`. Tous les RPC exigent un utilisateur authentifié (`anon` → `401`).

### 4.1 `sync_push(payload jsonb)`

Envoie les écritures locales. Corps : `{"payload": { … }}`.

```bash
curl -X POST "$URL/rest/v1/rpc/sync_push" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{
  "payload": {
    "language_id": "en",
    "sessions": [{"id":"6f1c…","session_type":"learning","slot":"morning","local_date":"2026-10-13","scheduled_at":null,
                  "started_at":"2026-10-13T07:10:00.000Z","completed_at":"2026-10-13T07:15:00.000Z","status":"completed",
                  "lesson_id":"en.l20","item_count":11,"correct_count":8,"duration_seconds":312,"score":null,
                  "emergency_unlocked":false,"updated_at":"2026-10-13T07:15:00.000Z"}],
    "attempts": [{"id":"a9d2…","exercise_id":"en.l20.e03","session_id":"6f1c…","unit_ids":["en.g15.present_simple_negative"],
                  "exercise_type":"fill_blank","presentation":"choices","submitted_answer":"go","result":"correct","error_category":null,
                  "hint_used":false,"is_remediation":false,"duration_ms":8200,
                  "answered_at":"2026-10-13T07:12:44.120Z","updated_at":"2026-10-13T07:12:44.120Z"}],
    "memory_states": [], "vocabulary": []
  }}'
```

Réponse `200` :

```json
{"server_time":"2026-10-13T07:15:02.481Z",
 "accepted":{"attempts":1,"sessions":1,"memory_states":0,"vocabulary":0},
 "rejected":{"attempts":0,"memory_states":0,"vocabulary":0,"sessions":0}}
```

- **Contrat** : `accepted`/`rejected` pour `attempts`, `memory_states`, `vocabulary` ; `sessions` est un ajout (sessions refusées pour conflit de créneau ou UUID déjà pris par un autre compte, § 4 de `docs/03`).
- `accepted` compte toute ligne valide, **y compris** celle déjà présente (idempotence) ou plus ancienne que la ligne serveur (dernière écriture gagne).
- `rejected` compte : référence inconnue (exercice, unité, mot ; d'une autre langue), valeur hors énumération, UUID/date illisible, élément qui n'est pas un objet.
- Ordre : sessions → attempts → memory_states → vocabulary, en une transaction. Chaque tableau est optionnel ; limites : 5000 attempts, 1000 sessions, 2000 memory_states, 2000 vocabulary.
- `validated` n'est pas un champ d'entrée : il est calculé par le serveur (≥ 4 tentatives pour une session `learning`/`application`/`consolidation` terminée).

Erreurs : `401` sans JWT ; `403 28000` JWT sans utilisateur ; `400 22023` (`payload must be a JSON object`, `unknown language_id: xx`, `attempts must be an array`) ; `413 PT413` (lot trop gros : renvoyer en plusieurs lots).

### 4.2 `sync_pull(p_language_id text, p_since timestamptz)`

```bash
# Restauration complète sur un nouvel iPhone
curl -X POST "$URL/rest/v1/rpc/sync_pull" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{"p_language_id":"en","p_since":"1970-01-01T00:00:00Z"}'
```

```json
{"server_time":"2026-10-13T07:15:00.482Z",
 "user_language":{"estimated_level":1,"start_lesson_sequence":10,"placement":{"score":7},"started_at":"2026-10-12T09:00:00.000Z","updated_at":"2026-10-12T09:00:00.000Z"},
 "schedule":{"morning_time":"09:00","afternoon_time":"14:00","evening_time":"20:00","timezone":"Europe/Paris","enabled":true,"safety_window_minutes":120,"early_start_minutes":60,"updated_at":"2026-10-12T09:00:00.000Z"},
 "sessions":[{"id":"6f1c…","session_type":"learning","slot":"morning","local_date":"2026-10-13","scheduled_at":null,"started_at":"…","completed_at":"…","status":"completed","lesson_id":"en.l20","item_count":11,"correct_count":8,"duration_seconds":312,"score":null,"emergency_unlocked":false,"validated":true,"updated_at":"2026-10-13T07:15:00.000Z"}],
 "memory_states":[{"learning_unit_id":"en.g15.present_simple_negative","stability":3.7,"difficulty":5.2,"review_count":4,"lapse_count":1,"success_count":3,"failure_count":1,"no_hint_success_count":3,"delayed_success_count":1,"production_success_count":1,"successful_exercise_types":["mcq","fill_blank"],"recent_results":[true,false,true],"source":"lesson","first_seen_at":"…","last_review_at":null,"next_review_at":"…","updated_at":"…"}],
 "vocabulary":[{"dictionary_item_id":"en.d.through","added_at":"…","learning_status":"learning","updated_at":"…"}],
 "attempts":[{"id":"a9d2…","exercise_id":"en.l20.e03","session_id":"6f1c…","unit_ids":["en.g15.present_simple_negative"],"exercise_type":"fill_blank","presentation":"choices","submitted_answer":"go","result":"correct","error_category":null,"hint_used":false,"is_remediation":false,"duration_ms":8200,"answered_at":"2026-10-13T07:12:44.120Z","updated_at":"2026-10-13T07:12:44.120Z"}]}
```

- **Synchronisation incrémentale** : mémoriser `server_time` et le renvoyer comme `p_since` au tour suivant. Seul ce qui a `server_updated_at > p_since` revient (les propres écritures de l'appareil reviennent aussi : la fusion côté client est idempotente).
- `server_time` est volontairement 2 s en retrait de l'horloge serveur : un élément peut revenir deux fois, jamais être manqué.
- `user_language` et `schedule` valent `null` s'ils n'existent pas **ou** n'ont pas changé depuis `p_since`.
- `attempts` : au plus les 2000 plus récentes (`answered_at` décroissant). Les autres tableaux sont complets.
- `validated` est exposé sur les sessions.
- Erreurs : `401`/`403`, `400 22023` (`unknown language_id`).

### 4.3 `content_manifest(p_language_id text)` et téléchargement du bundle

```bash
curl -X POST "$URL/rest/v1/rpc/content_manifest" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{"p_language_id":"en"}'
# -> {"version":"1.0.0","bundle_path":"en/1.0.0.json","sha256":"3d01677b…","published_at":"2026-10-13T06:00:00.000Z"}   (ou null)
# Bundle (bucket public, sans authentification) :
curl -O "$URL/storage/v1/object/public/content/en/1.0.0.json"
```

Le client compare `version` à sa version locale, télécharge le bundle si besoin et vérifie le SHA-256 du fichier. `null` : aucune version publiée pour cette langue.

## 5. Edge Function `ai` — professeur IA

`POST $URL/functions/v1/ai/<action>` — `Authorization: Bearer $JWT` (vérifié dans la fonction par `supabase.auth.getUser`), `Content-Type: application/json`, corps ≤ 16 000 caractères. Actions : `explain-answer`, `explain-word`, `explain-rule`, `follow-up`, `grade-answer`.

**Principe** : le serveur recharge l'exercice, la réponse attendue, les réponses acceptées, la règle de l'unité ou la fiche du mot **depuis la base**, à partir des identifiants ; le client n'envoie jamais le contenu. Le modèle (Claude, `ANTHROPIC_MODEL`, défaut `claude-haiku-5-5`) ne peut s'appuyer que sur ce contenu validé, doit dire quand il n'est pas sûr et refuse poliment le hors-sujet. Aucun e-mail, nom ni identifiant d'utilisateur n'est transmis au fournisseur.

### 5.1 Corps de requête

| Action | Corps |
|---|---|
| `explain-answer` | `{languageCode, level, exerciseId, userAnswer, detail?, previousErrorCategories?}` |
| `explain-word` | `{languageCode, level, word, sentence?, detail?}` |
| `explain-rule` | `{languageCode, level, unitId, detail?}` |
| `follow-up` | `{languageCode, level, exerciseId?, unitId?, word?, userAnswer?, previousExplanation, history?, question}` (au moins un de `exerciseId`/`unitId`/`word`) |
| `grade-answer` | `{languageCode, level, exerciseId, userAnswer}` |

- `languageCode` : `"en"` ; `level` : nombre de 0 à 20 (1 = grand débutant) ou niveau `A1…C2` ; `detail` : `"short"` (défaut) ou `"detailed"`.
- Limites : `userAnswer` ≤ 300 caractères (non vide pour `grade-answer`), `question` ≤ 500, `word` ≤ 60, `sentence` ≤ 300, `previousExplanation` ≤ 2000, `history` : les **6 derniers** messages (`{role:"user"|"tutor", text ≤ 600}` ; au-delà, les plus anciens sont ignorés), `previousErrorCategories` ≤ 10 catégories connues.
- `explain-word` : le mot est cherché dans le dictionnaire validé (formes simples : `goes` → `go`). S'il n'y figure pas, la réponse est un message de secours (`source:"fallback"`), **sans appel au fournisseur ni quota consommé**.

```bash
curl -X POST "$URL/functions/v1/ai/explain-answer" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{"languageCode":"en","level":2,"exerciseId":"en.l20.e03","userAnswer":"I doesn'"'"'t go","detail":"short","previousErrorCategories":["grammar"]}'
```

### 5.2 Réponses

`explain-answer`, `explain-word`, `explain-rule`, `follow-up` — `200` :

```json
{"text":"Après doesn't, le verbe reste à sa forme de base : on dit « He doesn't go ».",
 "examples":[{"text":"He doesn't work today.","translation":"Il ne travaille pas aujourd'hui."}],
 "source":"ai","remainingQuota":37}
```

`grade-answer` — `200` :

```json
{"verdict":"incorrect","errorCategory":"conjugation","explanation":"Avec I, on utilise don't, pas doesn't.","correctedAnswer":"I don't go","source":"ai","remainingQuota":36}
```

- `verdict` ∈ `correct` | `partial` | `incorrect` | `uncertain` ; `errorCategory` ∈ `vocabulary`, `grammar`, `conjugation`, `verb_tense`, `word_order`, `spelling`, `preposition`, `word_confusion`, `instruction` ou `null` (toujours `null` si `correct`).
- `source` : `"ai"` (réponse fraîche), `"cache"` (déjà calculée pour la même demande : gratuite, `remainingQuota` inchangé), `"fallback"` (réponse construite depuis le contenu validé : sortie du modèle inexploitable, ou mot inconnu). Un repli de `grade-answer` est déterministe : `correct` si la réponse est acceptée, `incorrect` avec la catégorie et le retour validés si elle correspond à une erreur connue de l'exercice, sinon `uncertain` avec la réponse attendue.
- `remainingQuota` : demandes restantes dans la fenêtre glissante de 24 h.

### 5.3 Erreurs

| HTTP | Corps | Cas |
|---|---|---|
| 401 | `{"error":"unauthorized"}` | jeton absent, invalide, expiré ou sans utilisateur |
| 400 | `{"error":"bad_request","message":"…"}` | champ manquant/invalide, limite dépassée, exercice / unité / langue inconnus, JSON illisible |
| 404 | `{"error":"not_found","message":"…"}` | action inconnue dans l'URL |
| 405 | `{"error":"method_not_allowed","message":"Utiliser POST."}` | méthode ≠ POST |
| 429 | `{"error":"rate_limited","message":"…","resetAt":"2026-10-14T08:12:00.000Z"}` + en-tête `Retry-After` | quota de 24 h glissantes atteint (`resetAt` = instant où une demande se libère) |
| 503 | `{"error":"unavailable","message":"…","fallback":{…réponse de secours, même forme qu'au § 5.2, "source":"fallback"…}}` | fournisseur injoignable / en erreur après une reprise, clé absente, **plafond mensuel global atteint**, base indisponible |
| 500 | `{"error":"internal_error","message":"Erreur interne."}` | erreur inattendue (rare) |

L'app peut toujours afficher `fallback` sur un `503`.

### 5.4 Quotas, cache et coûts

- **Quota par utilisateur** : `AI_DAILY_QUOTA` (défaut 40) demandes sur **24 h glissantes**. Compte une demande si un appel au fournisseur a eu lieu (`ai_interactions` : statut `ok` ou `fallback` avec `model` renseigné). **Gratuits** : réponses du cache, mots inconnus, échecs du fournisseur, demandes refusées. La réservation est comptée *avant* l'appel puis vérifiée une seconde fois : des demandes simultanées ne peuvent pas dépasser la limite.
- **Plafond mensuel global** : `AI_MONTHLY_BUDGET_REQUESTS` (défaut 200 000, mois civil UTC). Atteint : `503` + réponse de secours, sans appel payant.
- **Cache** (`ai_cache`, partagé entre utilisateurs, jamais lié à un compte) pour `explain-answer`, `explain-word`, `explain-rule`, `grade-answer` ; **jamais** pour `follow-up`. Clé : `sha256(action, identifiants, réponse normalisée, detail, level, version du contenu[, catégories d'erreurs récurrentes])`. La réponse est normalisée (espaces, apostrophes), **casse et ponctuation conservées**.
- **Journal** (`ai_interactions`) : type de demande, exercice, statut, modèle, jetons, latence. Jamais le texte de la réponse ou de la question.
- **Fournisseur** : `POST https://api.anthropic.com/v1/messages` (`x-api-key`, `anthropic-version: 2023-06-01`), délai de 20 s par tentative, une reprise sur 429 / 5xx / 529 ou erreur réseau (pas sur délai dépassé).

## 6. Edge Function `account` — droits RGPD

`Authorization: Bearer $JWT` requis (`401 {"error":"unauthorized"}` sinon).

### 6.1 `GET /functions/v1/account/export`

Renvoie, en pièce jointe (`Content-Disposition: attachment; filename="quinze-export-<date>.json"`), toutes les données de l'utilisateur :

```json
{"format":"quinze-export-v1","exportedAt":"2026-10-14T10:00:00.000Z",
 "account":{"id":"…","email":"emma@example.com","createdAt":"…","lastSignInAt":"…","providers":["email"]},
 "data":{"profiles":[…],"userLanguages":[…],"dailySchedules":[…],"learningSessions":[…],"attempts":[…],"memoryStates":[…],"userVocabulary":[…],"aiInteractions":[…]},
 "counts":{"profiles":1,"userLanguages":1,"dailySchedules":1,"learningSessions":120,"attempts":1850,"memoryStates":210,"userVocabulary":64,"aiInteractions":37}}
```

Les noms de colonnes sont en `camelCase` ; le contenu des colonnes jsonb (préférences, placement) est restitué tel quel.

### 6.2 `DELETE /functions/v1/account`

Supprime définitivement l'utilisateur Auth ; la cascade SQL supprime toutes ses données. Réponse `200 {"deleted":true}`. Après suppression, le JWT n'est plus accepté. Irréversible : l'app demande une confirmation explicite. Erreurs : `401`, `405`/`404` (méthode ou chemin inattendu), `500 {"error":"internal_error","message":"…"}`.

## 7. Récapitulatif des permissions

| Appel | `anon` | utilisateur | service role |
|---|---|---|---|
| `/auth/v1/signup`, `/token`, `/recover` | oui | oui | oui |
| `sync_push`, `sync_pull`, `content_manifest` | non (401) | oui | oui |
| lecture du contenu (`/rest/v1/exercises`…) | non | oui (lecture seule) | oui |
| `profiles`, `user_*`, `learning_sessions`, `attempts`, `memory_states` | non | ses lignes | oui |
| `ai_cache`, `ai_cache_get`, `ai_purge` | non | non | oui |
| bundle Storage `content` (lecture) | oui | oui | oui |
| `functions/v1/ai`, `functions/v1/account` | non (401) | oui | — |
