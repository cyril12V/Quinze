-- 02 — Tables de contenu pédagogique (lecture seule pour les utilisateurs).
--
-- Alimentées par supabase/seed/content_en.sql (généré par tools/build_content.py)
-- via le rôle service/postgres uniquement. Les clés étrangères entre tables de
-- contenu sont DEFERRABLE INITIALLY DEFERRED : le seed les vérifie à la fin de sa
-- transaction, quel que soit l'ordre des INSERT.

create table public.languages (
  id                text primary key check (id ~ '^[a-z]{2,8}(-[A-Za-z0-9]{2,8})*$'),
  code              text not null unique,
  name              text not null,
  native_name       text not null,
  writing_direction text not null default 'ltr' check (writing_direction in ('ltr', 'rtl')),
  tts_locale        text not null,
  is_available      boolean not null default false
);
comment on table public.languages is 'Langues apprenables. id = code court (en).';

create table public.content_versions (
  id           bigserial primary key,
  language_id  text not null references public.languages (id) on delete cascade,
  version      text not null check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'),
  bundle_path  text not null check (bundle_path !~ '\.\.' and bundle_path !~ '^/' and bundle_path ~ '\.json$'),
  sha256       text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  published_at timestamptz not null default now(),
  is_current   boolean not null default false,
  unique (language_id, version)
);
comment on table public.content_versions is
  'Versions publiées du bundle de contenu (fichier JSON dans le bucket Storage `content`). Une seule is_current par langue.';
create unique index content_versions_one_current_per_language
  on public.content_versions (language_id) where is_current;

-- Une seule version courante par langue (la précédente est rétrogradée) et seed
-- rejouable : insérer une (langue, version) déjà présente met la ligne à jour.
create or replace function private.tg_content_versions()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_id bigint;
begin
  if tg_op = 'INSERT' then
    select cv.id into v_id
    from public.content_versions cv
    where cv.language_id = new.language_id and cv.version = new.version;
    if found then
      update public.content_versions
         set bundle_path = new.bundle_path,
             sha256 = new.sha256,
             is_current = new.is_current,
             published_at = now()
       where id = v_id;
      return null;
    end if;
  end if;
  if new.is_current then
    update public.content_versions
       set is_current = false
     where language_id = new.language_id and is_current and id is distinct from new.id;
  end if;
  return new;
end $$;

create trigger content_versions_current
  before insert or update on public.content_versions
  for each row execute function private.tg_content_versions();

create table public.learning_units (
  id              text primary key,
  language_id     text not null references public.languages (id) on delete cascade,
  kind            text not null check (kind <> ''),
  category        text not null,
  title           text not null,
  difficulty      integer not null check (difficulty >= 0),
  prerequisites   text[] not null default '{}',
  module          integer not null check (module >= 0),
  data            jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  content_version text not null,
  deprecated      boolean not null default false
);
comment on table public.learning_units is
  'Unités d''apprentissage (règle de grammaire, mot, expression…). data.rule = règle validée utilisée par le professeur IA.';

create table public.lessons (
  id              text primary key,
  language_id     text not null references public.languages (id) on delete cascade,
  module          integer not null check (module >= 0),
  title           text not null,
  description     text not null default '',
  difficulty      integer not null check (difficulty >= 0),
  sequence_order  integer not null check (sequence_order >= 0),
  grammar_unit_id text references public.learning_units (id) deferrable initially deferred,
  introduces      text[] not null default '{}',
  reviews         text[] not null default '{}',
  content_version text not null,
  deprecated      boolean not null default false,
  constraint lessons_language_sequence_key unique (language_id, sequence_order)
);

create table public.exercises (
  id               text primary key,
  language_id      text not null references public.languages (id) on delete cascade,
  lesson_id        text references public.lessons (id) deferrable initially deferred,
  learning_unit_id text not null references public.learning_units (id) deferrable initially deferred,
  unit_ids         text[] not null check (cardinality(unit_ids) >= 1),
  exercise_type    text not null check (exercise_type <> ''),
  pool             text not null check (pool in ('lesson', 'diagnostic', 'assessment')),
  question         text not null,
  accepted_answers text[] not null default '{}',
  explanation      text not null default '',
  difficulty       integer not null check (difficulty >= 0),
  data             jsonb not null check (jsonb_typeof(data) = 'object'),
  content_version  text not null,
  deprecated       boolean not null default false,
  constraint exercises_main_unit_in_unit_ids check (learning_unit_id = any (unit_ids))
);
comment on column public.exercises.data is
  'Exercice complet (prompt, answer, acceptedAnswers, explanation, tip, extraExample…) tel que dans le bundle.';

create table public.dictionary_items (
  id              text primary key,
  language_id     text not null references public.languages (id) on delete cascade,
  word            text not null check (word <> ''),
  translation     text not null,
  definition      text,
  examples        jsonb not null default '[]'::jsonb,
  pronunciation   text,
  data            jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  content_version text not null
);

-- Index (clés étrangères + chemins de lecture de l'app et des Edge Functions).
create index learning_units_language_idx   on public.learning_units (language_id, module);
create index lessons_language_module_idx   on public.lessons (language_id, module);
create index lessons_grammar_unit_idx      on public.lessons (grammar_unit_id);
create index exercises_language_lesson_idx on public.exercises (language_id, lesson_id);
create index exercises_unit_idx            on public.exercises (learning_unit_id);
create index exercises_unit_ids_gin_idx    on public.exercises using gin (unit_ids);
create index exercises_pool_idx            on public.exercises (language_id, pool);
create index dictionary_items_word_idx     on public.dictionary_items (language_id, lower(word));
