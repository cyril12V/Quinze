-- 03 — Tables utilisateur.
--
-- Toutes référencent auth.users(id) ON DELETE CASCADE : supprimer le compte
-- supprime l'intégralité des données (droit à l'effacement, RGPD).
-- Colonnes de synchronisation (tables synchronisées) :
--   updated_at         horloge CLIENT (fusion « dernière écriture gagne »)
--   server_updated_at  horloge SERVEUR posée par trigger = curseur de sync_pull
-- Les identifiants des tentatives et des sessions sont générés par le client
-- (UUID) : un renvoi du même lot est donc idempotent.

create table public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  email              text,
  display_name       text check (display_name is null or char_length(display_name) <= 80),
  pedagogical_prefs  jsonb not null default '{}'::jsonb check (jsonb_typeof(pedagogical_prefs) = 'object'),
  notification_prefs jsonb not null default '{}'::jsonb check (jsonb_typeof(notification_prefs) = 'object'),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint profiles_prefs_size check (
    pg_column_size(pedagogical_prefs) <= 16384 and pg_column_size(notification_prefs) <= 16384)
);
comment on table public.profiles is 'Profil créé automatiquement à l''inscription (trigger sur auth.users).';

create table public.user_languages (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null default auth.uid() references auth.users (id) on delete cascade,
  language_id           text not null references public.languages (id),
  estimated_level       integer not null default 1 check (estimated_level >= 0),
  start_lesson_sequence integer not null default 1 check (start_lesson_sequence >= 0),
  placement             jsonb check (placement is null or (jsonb_typeof(placement) = 'object' and pg_column_size(placement) <= 65536)),
  started_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  server_updated_at     timestamptz not null default clock_timestamp(),
  constraint user_languages_user_language_key unique (user_id, language_id)
);

create table public.daily_schedules (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null default auth.uid() unique references auth.users (id) on delete cascade,
  morning_time           time not null default '09:00',
  afternoon_time         time not null default '14:00',
  evening_time           time not null default '20:00',
  timezone               text not null default 'Europe/Paris',
  enabled                boolean not null default true,
  safety_window_minutes  integer not null default 120 check (safety_window_minutes between 0 and 1440),
  early_start_minutes    integer not null default 60 check (early_start_minutes between 0 and 1440),
  updated_at             timestamptz not null default now(),
  server_updated_at      timestamptz not null default clock_timestamp()
);

create table public.learning_sessions (
  id                 uuid primary key,  -- généré par le client
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  language_id        text not null references public.languages (id),
  session_type       text not null check (session_type ~ '^[a-z][a-z_]{0,39}$'),
  slot               text check (slot in ('morning', 'afternoon', 'evening')),
  local_date         date not null,
  scheduled_at       timestamptz,
  started_at         timestamptz,
  completed_at       timestamptz,
  status             text not null check (status in ('scheduled', 'in_progress', 'completed', 'expired', 'skipped')),
  lesson_id          text references public.lessons (id) on delete set null,
  item_count         integer not null default 0 check (item_count >= 0),
  correct_count      integer not null default 0 check (correct_count >= 0),
  duration_seconds   integer not null default 0 check (duration_seconds between 0 and 86400),
  score              numeric check (score is null or score >= 0),
  emergency_unlocked boolean not null default false,
  validated          boolean not null default true,  -- recalculé par trigger (anti-fraude), jamais écrit par le client
  updated_at         timestamptz not null default now(),
  server_updated_at  timestamptz not null default clock_timestamp()
);
comment on column public.learning_sessions.validated is
  'Anti-fraude : false si une session learning/application/consolidation « completed » a moins de 4 tentatives. Calculé par le serveur.';

create table public.attempts (
  id                uuid primary key,  -- généré par le client
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  language_id       text not null references public.languages (id),
  exercise_id       text not null references public.exercises (id),
  session_id        uuid references public.learning_sessions (id) on delete cascade,
  unit_ids          text[] not null default '{}',
  exercise_type     text not null check (exercise_type <> ''),
  presentation      text not null default 'choices' check (presentation <> ''),
  submitted_answer  text check (submitted_answer is null or char_length(submitted_answer) <= 2000),
  result            text not null check (result in ('correct', 'correct_typo', 'partial', 'incorrect', 'pending')),
  error_category    text check (error_category is null or error_category ~ '^[a-z][a-z_]{0,39}$'),
  hint_used         boolean not null default false,
  is_remediation    boolean not null default false,
  duration_ms       integer check (duration_ms is null or duration_ms >= 0),
  answered_at       timestamptz not null,
  updated_at        timestamptz not null default now(),
  server_updated_at timestamptz not null default clock_timestamp()
);
comment on table public.attempts is
  'Tentatives d''exercices. Immuables, sauf result/error_category d''une tentative pending (résolution IA) et session_id tant qu''il est NULL.';

create table public.memory_states (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  language_id               text not null references public.languages (id),
  learning_unit_id          text not null references public.learning_units (id),
  stability                 double precision not null default 0 check (stability >= 0),
  difficulty                double precision not null default 5 check (difficulty >= 0),
  review_count              integer not null default 0 check (review_count >= 0),
  lapse_count               integer not null default 0 check (lapse_count >= 0),
  success_count             integer not null default 0 check (success_count >= 0),
  failure_count             integer not null default 0 check (failure_count >= 0),
  no_hint_success_count     integer not null default 0 check (no_hint_success_count >= 0),
  delayed_success_count     integer not null default 0 check (delayed_success_count >= 0),
  production_success_count  integer not null default 0 check (production_success_count >= 0),
  successful_exercise_types text[] not null default '{}',
  recent_results            boolean[] not null default '{}' check (cardinality(recent_results) <= 100),
  source                    text not null default 'lesson' check (source in ('lesson', 'diagnostic', 'dictionary')),
  first_seen_at             timestamptz not null default now(),
  last_review_at            timestamptz,
  next_review_at            timestamptz,
  updated_at                timestamptz not null default now(),
  server_updated_at         timestamptz not null default clock_timestamp(),
  constraint memory_states_user_unit_key unique (user_id, learning_unit_id)
);

create table public.user_vocabulary (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  dictionary_item_id text not null references public.dictionary_items (id),
  added_at           timestamptz not null default now(),
  learning_status    text not null default 'learning' check (learning_status in ('learning', 'known', 'mastered')),
  updated_at         timestamptz not null default now(),
  server_updated_at  timestamptz not null default clock_timestamp(),
  constraint user_vocabulary_user_item_key unique (user_id, dictionary_item_id)
);

-- Journal des appels IA : AUCUN texte de réponse, de question ni donnée personnelle.
create table public.ai_interactions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  exercise_id     text references public.exercises (id) on delete set null,
  request_type    text not null check (request_type in ('explain-answer', 'explain-word', 'explain-rule', 'follow-up', 'grade-answer')),
  response_status text not null check (response_status in ('ok', 'cached', 'fallback', 'rate_limited', 'error')),
  model           text,
  input_tokens    integer check (input_tokens is null or input_tokens >= 0),
  output_tokens   integer check (output_tokens is null or output_tokens >= 0),
  latency_ms      integer check (latency_ms is null or latency_ms >= 0),
  created_at      timestamptz not null default now()
);
comment on table public.ai_interactions is
  'Compteur de quota + observabilité. Une ligne comptée au quota = response_status in (ok, fallback) ET model non nul (un appel au fournisseur a eu lieu).';

-- Cache des réponses IA (partagé entre utilisateurs, clé = sha256 de l'action, des ids, de la réponse normalisée…).
create table public.ai_cache (
  cache_key    text primary key check (cache_key ~ '^[0-9a-f]{64}$'),
  request_type text not null check (request_type in ('explain-answer', 'explain-word', 'explain-rule', 'grade-answer')),
  response     jsonb not null,
  model        text,
  created_at   timestamptz not null default now(),
  hit_count    integer not null default 0 check (hit_count >= 0),
  last_hit_at  timestamptz
);

-- Index : curseurs de synchronisation et clés étrangères.
create index user_languages_sync_idx     on public.user_languages (user_id, language_id, server_updated_at);
create index user_languages_language_idx on public.user_languages (language_id);
create index daily_schedules_sync_idx    on public.daily_schedules (user_id, server_updated_at);

create index learning_sessions_sync_idx    on public.learning_sessions (user_id, language_id, server_updated_at);
create index learning_sessions_date_idx    on public.learning_sessions (user_id, language_id, local_date);
create index learning_sessions_lesson_idx  on public.learning_sessions (lesson_id);
-- Unicité : une seule session par utilisateur / langue / jour local / créneau.
create unique index learning_sessions_user_language_date_slot_key
  on public.learning_sessions (user_id, language_id, local_date, slot) where slot is not null;

create index attempts_sync_idx     on public.attempts (user_id, language_id, server_updated_at);
create index attempts_recent_idx   on public.attempts (user_id, language_id, answered_at desc);
create index attempts_session_idx  on public.attempts (session_id) where session_id is not null;
create index attempts_exercise_idx on public.attempts (exercise_id);
create index attempts_language_idx on public.attempts (language_id);

create index memory_states_sync_idx   on public.memory_states (user_id, language_id, server_updated_at);
create index memory_states_due_idx    on public.memory_states (user_id, language_id, next_review_at);
create index memory_states_unit_idx   on public.memory_states (learning_unit_id);
create index memory_states_language_idx on public.memory_states (language_id);

create index user_vocabulary_sync_idx on public.user_vocabulary (user_id, server_updated_at);
create index user_vocabulary_item_idx on public.user_vocabulary (dictionary_item_id);

create index ai_interactions_user_idx     on public.ai_interactions (user_id, created_at desc);
create index ai_interactions_exercise_idx on public.ai_interactions (exercise_id) where exercise_id is not null;
create index ai_interactions_budget_idx   on public.ai_interactions (created_at)
  where response_status in ('ok', 'fallback') and model is not null;
create index ai_cache_last_hit_idx        on public.ai_cache (coalesce(last_hit_at, created_at));
