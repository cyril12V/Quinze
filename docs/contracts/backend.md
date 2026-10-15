# Contrat backend ↔ app iOS (Supabase)

Référence partagée entre le backend (`supabase/`) et le client iOS (`App/Sources/Services/`). Toute modification doit être faite des deux côtés.

Principes :
- L'app fonctionne **hors ligne d'abord** : tout est écrit localement (SwiftData) puis synchronisé.
- Identifiants des tentatives et des sessions **générés côté client** (UUID) → synchronisation idempotente.
- Chaque table utilisateur a `user_id uuid` + RLS `user_id = auth.uid()` et une colonne `server_updated_at timestamptz` posée **par le serveur** (trigger) qui sert de curseur de synchronisation (pas d'horloge client).
- Dates : ISO 8601 UTC avec fuseau (`2026-10-13T07:12:44.120Z`). Jours locaux : `yyyy-MM-dd`. Heures : `HH:mm`.
- Le contenu pédagogique est en lecture seule pour les utilisateurs authentifiés.

## Tables

Contenu (lecture seule, alimenté par `supabase/seed/`) :
- `languages(id text pk, code text unique, name, native_name, writing_direction ('ltr'|'rtl'), tts_locale, is_available bool)`
- `content_versions(id bigserial, language_id, version text, bundle_path text, sha256 text, published_at, is_current bool)` — un seul `is_current` par langue.
- `learning_units(id text pk, language_id, kind, category, title, difficulty int, prerequisites text[], module int, data jsonb, content_version text, deprecated bool)`
- `lessons(id text pk, language_id, module int, title, description, difficulty int, sequence_order int, grammar_unit_id, introduces text[], reviews text[], content_version, deprecated)` — unique `(language_id, sequence_order)`.
- `exercises(id text pk, language_id, lesson_id text null, learning_unit_id text (unité principale), unit_ids text[], exercise_type, pool ('lesson'|'diagnostic'|'assessment'), question text, accepted_answers text[], explanation text, difficulty int, data jsonb (exercice complet), content_version, deprecated)`
- `dictionary_items(id text pk, language_id, word, translation, definition, examples jsonb, pronunciation text, data jsonb, content_version)`

Utilisateur (RLS) :
- `profiles(id uuid pk = auth.users.id, email, display_name, pedagogical_prefs jsonb, notification_prefs jsonb, created_at, updated_at)` — créé par trigger à l'inscription.
- `user_languages(id uuid, user_id, language_id, estimated_level int, start_lesson_sequence int, placement jsonb, started_at, updated_at, server_updated_at)` — unique `(user_id, language_id)`.
- `daily_schedules(id uuid, user_id unique, morning_time time, afternoon_time time, evening_time time, timezone text, enabled bool, safety_window_minutes int, early_start_minutes int, updated_at, server_updated_at)`
- `learning_sessions(id uuid pk (client), user_id, language_id, session_type, slot ('morning'|'afternoon'|'evening'|null), local_date date, scheduled_at, started_at, completed_at, status ('scheduled'|'in_progress'|'completed'|'expired'|'skipped'), lesson_id, item_count, correct_count, duration_seconds, score numeric, emergency_unlocked bool, validated bool, updated_at, server_updated_at)` — unique `(user_id, language_id, local_date, slot)` quand `slot` non nul.
- `attempts(id uuid pk (client), user_id, language_id, exercise_id → exercises, session_id → learning_sessions null, unit_ids text[], exercise_type, presentation, submitted_answer, result ('correct'|'correct_typo'|'partial'|'incorrect'|'pending'), error_category null, hint_used, is_remediation, duration_ms int, answered_at, updated_at, server_updated_at)`
- `memory_states(id uuid, user_id, language_id, learning_unit_id → learning_units, stability float8, difficulty float8, review_count, lapse_count, success_count, failure_count, no_hint_success_count, delayed_success_count, production_success_count, successful_exercise_types text[], recent_results boolean[], source ('lesson'|'diagnostic'|'dictionary'), first_seen_at, last_review_at, next_review_at, updated_at, server_updated_at)` — unique `(user_id, learning_unit_id)`.
- `user_vocabulary(id uuid, user_id, dictionary_item_id → dictionary_items, added_at, learning_status ('learning'|'known'|'mastered'), updated_at, server_updated_at)` — unique `(user_id, dictionary_item_id)`.
- `ai_interactions(id uuid, user_id, exercise_id null, request_type, response_status ('ok'|'cached'|'fallback'|'rate_limited'|'error'), model, input_tokens, output_tokens, latency_ms, created_at)` — **jamais** le texte des réponses ni de données personnelles.
- `ai_cache(cache_key text pk, request_type, response jsonb, model, created_at, hit_count, last_hit_at)` — accès service role uniquement.

Fusion des conflits : pour `learning_sessions`, `memory_states`, `user_vocabulary`, la ligne entrante remplace la ligne existante **seulement si son `updated_at` (horloge client) est plus récent**. Les `attempts` sont immuables sauf `result`/`error_category` d'une tentative `pending` (résolution IA).

Anti-fraude : une session de type `learning`/`application`/`consolidation` passée à `completed` avec moins de 4 tentatives associées est conservée mais `validated = false` (elle ne compte pas dans les statistiques serveur). Le déblocage Screen Time, lui, est **local** et ne dépend jamais du serveur.

## RPC (PostgREST, `POST /rest/v1/rpc/<nom>`, JWT utilisateur)

### `sync_push(payload jsonb) returns jsonb`

```json
{
  "language_id": "en",
  "attempts": [{
    "id": "uuid", "exercise_id": "en.l20.e03", "session_id": "uuid|null", "unit_ids": ["en.g15.present_simple_negative"],
    "exercise_type": "fill_blank", "presentation": "choices", "submitted_answer": "go",
    "result": "correct", "error_category": null, "hint_used": false, "is_remediation": false,
    "duration_ms": 8200, "answered_at": "2026-10-13T07:12:44.120Z", "updated_at": "2026-10-13T07:12:44.120Z"
  }],
  "sessions": [{
    "id": "uuid", "session_type": "learning", "slot": "morning", "local_date": "2026-10-13",
    "scheduled_at": "…|null", "started_at": "…", "completed_at": "…|null", "status": "completed",
    "lesson_id": "en.l20|null", "item_count": 11, "correct_count": 8, "duration_seconds": 312,
    "score": null, "emergency_unlocked": false, "updated_at": "…"
  }],
  "memory_states": [{
    "learning_unit_id": "en.g15.present_simple_negative", "stability": 3.7, "difficulty": 5.2,
    "review_count": 4, "lapse_count": 1, "success_count": 3, "failure_count": 1,
    "no_hint_success_count": 3, "delayed_success_count": 1, "production_success_count": 1,
    "successful_exercise_types": ["mcq", "fill_blank"], "recent_results": [true, false, true],
    "source": "lesson", "first_seen_at": "…", "last_review_at": "…|null", "next_review_at": "…", "updated_at": "…"
  }],
  "vocabulary": [{ "dictionary_item_id": "en.d.through", "added_at": "…", "learning_status": "learning", "updated_at": "…" }]
}
```
Ordre de traitement : sessions, puis attempts, puis memory_states, puis vocabulary (en une transaction). Les références inconnues (exercice ou unité absents côté serveur) sont ignorées et comptées dans `rejected`.

Réponse : `{"server_time": "…", "accepted": {"attempts": 12, "sessions": 1, "memory_states": 5, "vocabulary": 0}, "rejected": {"attempts": 0, "memory_states": 0, "vocabulary": 0}}`

### `sync_pull(p_language_id text, p_since timestamptz) returns jsonb`

Renvoie tout ce dont `server_updated_at > p_since` (`p_since = '1970-01-01'` pour une restauration complète sur un nouvel iPhone) :

```json
{
  "server_time": "…",
  "user_language": {"estimated_level": 1, "start_lesson_sequence": 10, "placement": {…DiagnosticResult…}, "started_at": "…", "updated_at": "…"} ,
  "schedule": {"morning_time": "09:00", "afternoon_time": "14:00", "evening_time": "20:00", "timezone": "Europe/Paris", "enabled": true, "safety_window_minutes": 120, "early_start_minutes": 60, "updated_at": "…"},
  "sessions": [ …même forme que sync_push + "validated" … ],
  "memory_states": [ … ],
  "vocabulary": [ … ],
  "attempts": [ … au plus les 2000 plus récentes … ]
}
```
`user_language` et `schedule` valent `null` s'ils n'existent pas. Le client mémorise `server_time` comme prochain `p_since`.

### `content_manifest(p_language_id text) returns jsonb`

`{"version": "1.0.0", "bundle_path": "en/1.0.0.json", "sha256": "…", "published_at": "…"}` ou `null`. Le bundle est téléchargeable dans le bucket Storage **public** `content` : `GET /storage/v1/object/public/content/<bundle_path>`.

## PostgREST direct

- `GET/PATCH /rest/v1/profiles?id=eq.<uid>` : `display_name`, `pedagogical_prefs`, `notification_prefs`.
- `POST /rest/v1/user_languages?on_conflict=user_id,language_id` (Prefer: resolution=merge-duplicates) : `estimated_level`, `start_lesson_sequence`, `placement`, `started_at`, `updated_at`.
- `POST /rest/v1/daily_schedules?on_conflict=user_id` (merge-duplicates) : horaires.

## Edge Functions

Toutes exigent `Authorization: Bearer <JWT utilisateur>` (vérifié dans la fonction). Corps et réponses en JSON camelCase.

### `ai` — professeur IA (Claude)

`POST /functions/v1/ai/<action>` avec `<action>` ∈ :

| Action | Corps |
|---|---|
| `explain-answer` | `{languageCode, level, exerciseId, userAnswer, detail: "short"|"detailed", previousErrorCategories: [string]}` |
| `explain-word` | `{languageCode, level, word, sentence?, detail}` |
| `explain-rule` | `{languageCode, level, unitId, detail}` |
| `follow-up` | `{languageCode, level, exerciseId?, unitId?, word?, userAnswer?, previousExplanation, history: [{role: "user"|"tutor", text}], question}` |
| `grade-answer` | `{languageCode, level, exerciseId, userAnswer}` |

Le serveur **recharge l'exercice, la réponse attendue, les réponses acceptées et la règle depuis la base** à partir des identifiants : l'IA s'appuie uniquement sur le contenu validé. `history` est limité à 6 messages, `question` à 500 caractères, `userAnswer` à 300.

Réponse `explain-*` et `follow-up` :
```json
{"text": "Après doesn't, le verbe reste à sa forme de base…", "examples": [{"text": "He doesn't work today.", "translation": "Il ne travaille pas aujourd'hui."}], "source": "ai|cache|fallback", "remainingQuota": 37}
```
Réponse `grade-answer` :
```json
{"verdict": "correct|partial|incorrect|uncertain", "errorCategory": "conjugation|null", "explanation": "…", "correctedAnswer": "…|null", "source": "ai|cache|fallback", "remainingQuota": 36}
```
Erreurs : `401 {"error":"unauthorized"}`, `400 {"error":"bad_request","message"}`, `429 {"error":"rate_limited","message":"…","resetAt":"…"}`, `503 {"error":"unavailable","message":"…","fallback":{…réponse de secours…}}`.

Quotas (variables d'environnement) : `AI_DAILY_QUOTA` (défaut 40 requêtes / utilisateur / 24 h glissantes), `AI_MONTHLY_BUDGET_REQUESTS` (plafond global mensuel, défaut 200000). Les réponses servies depuis le cache ne consomment pas de quota.

### `account`

- `GET /functions/v1/account/export` → JSON complet des données de l'utilisateur (RGPD, droit d'accès/portabilité).
- `DELETE /functions/v1/account` → supprime l'utilisateur Supabase Auth et, par cascade, toutes ses données. Réponse `{"deleted": true}`.
