-- 06 — RPC de synchronisation : sync_push, sync_pull, content_manifest.
--
-- Les trois fonctions sont SECURITY INVOKER : elles s'exécutent avec les droits de
-- l'appelant (rôle `authenticated`), donc la RLS s'applique à chaque lecture et
-- écriture ; auth.uid() est vérifié explicitement en plus. Aucune n'est accessible
-- à anon. search_path vide : tout est qualifié.

-- ---------------------------------------------------------------------------
-- sync_push(payload jsonb) -> jsonb
--
-- Ordre : sessions, attempts, memory_states, vocabulary — une seule transaction
-- (celle de l'appel RPC). Idempotent : renvoyer le même lot ne change rien (pas
-- d'écriture, donc pas de nouveau server_updated_at). Dernière écriture gagne sur
-- updated_at (horloge client) pour sessions / memory_states / vocabulary ; les
-- attempts sont immuables (seule une tentative `pending` peut être résolue).
-- Les références inconnues (exercice, unité, mot absents du serveur) sont ignorées
-- et comptées dans `rejected`. Une ligne mal formée est rejetée, pas fatale.
-- ---------------------------------------------------------------------------
create or replace function public.sync_push(payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_lang     text;
  v_key      text;
  v_s        jsonb;
  v_id       uuid;
  v_existing uuid;
  v_lesson   text;
  v_remap    jsonb := '{}'::jsonb;  -- id de session client -> id de session serveur (conflit de créneau)
  v_good     jsonb;
  v_total    integer;
  v_ok       integer;
  v_acc_ses  integer := 0;
  v_rej_ses  integer := 0;
  v_acc_att  integer := 0;
  v_rej_att  integer := 0;
  v_acc_mem  integer := 0;
  v_rej_mem  integer := 0;
  v_acc_voc  integer := 0;
  v_rej_voc  integer := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'payload must be a JSON object' using errcode = '22023';
  end if;
  v_lang := payload ->> 'language_id';
  if v_lang is null or not exists (select 1 from public.languages l where l.id = v_lang) then
    raise exception 'unknown language_id: %', coalesce(v_lang, '<null>') using errcode = '22023';
  end if;
  foreach v_key in array array['attempts', 'sessions', 'memory_states', 'vocabulary'] loop
    if payload ? v_key and jsonb_typeof(payload -> v_key) not in ('array', 'null') then
      raise exception '% must be an array', v_key using errcode = '22023';
    end if;
  end loop;
  if jsonb_array_length(private.json_array(payload -> 'attempts')) > 5000
     or jsonb_array_length(private.json_array(payload -> 'sessions')) > 1000
     or jsonb_array_length(private.json_array(payload -> 'memory_states')) > 2000
     or jsonb_array_length(private.json_array(payload -> 'vocabulary')) > 2000 then
    raise exception 'payload too large (max 5000 attempts, 1000 sessions, 2000 memory_states, 2000 vocabulary)'
      using errcode = 'PT413';  -- PostgREST : code SQLSTATE « PTnnn » = statut HTTP nnn
  end if;

  ------------------------------------------------------------------ sessions
  for v_s in select e.value from jsonb_array_elements(private.json_array(payload -> 'sessions')) as e loop
    v_existing := null;
    v_id := null;
    begin
      v_id := private.try_uuid(v_s ->> 'id');
      if v_id is null or jsonb_typeof(v_s) <> 'object' then
        raise exception 'invalid session' using errcode = '22023';
      end if;
      v_lesson := nullif(v_s ->> 'lesson_id', '');
      if v_lesson is not null
         and not exists (select 1 from public.lessons l where l.id = v_lesson and l.language_id = v_lang) then
        v_lesson := null;  -- leçon inconnue du serveur : la session est conservée sans la référence
      end if;

      insert into public.learning_sessions as ls (
        id, user_id, language_id, session_type, slot, local_date, scheduled_at, started_at, completed_at,
        status, lesson_id, item_count, correct_count, duration_seconds, score, emergency_unlocked, updated_at)
      values (
        v_id, v_uid, v_lang,
        v_s ->> 'session_type',
        nullif(v_s ->> 'slot', ''),
        private.try_date(v_s ->> 'local_date'),
        private.try_timestamptz(v_s ->> 'scheduled_at'),
        private.try_timestamptz(v_s ->> 'started_at'),
        private.try_timestamptz(v_s ->> 'completed_at'),
        v_s ->> 'status',
        v_lesson,
        coalesce(private.try_int(v_s ->> 'item_count'), 0),
        coalesce(private.try_int(v_s ->> 'correct_count'), 0),
        coalesce(private.try_int(v_s ->> 'duration_seconds'), 0),
        private.try_float(v_s ->> 'score')::numeric,
        coalesce(private.try_bool(v_s ->> 'emergency_unlocked'), false),
        coalesce(private.try_timestamptz(v_s ->> 'updated_at'), now())
      )
      on conflict (id) do update set
        session_type       = excluded.session_type,
        slot               = excluded.slot,
        local_date         = excluded.local_date,
        scheduled_at       = excluded.scheduled_at,
        started_at         = excluded.started_at,
        completed_at       = excluded.completed_at,
        status             = excluded.status,
        lesson_id          = excluded.lesson_id,
        item_count         = excluded.item_count,
        correct_count      = excluded.correct_count,
        duration_seconds   = excluded.duration_seconds,
        score              = excluded.score,
        emergency_unlocked = excluded.emergency_unlocked,
        updated_at         = excluded.updated_at
      where excluded.updated_at > ls.updated_at;
      v_acc_ses := v_acc_ses + 1;
    exception when unique_violation or insufficient_privilege or check_violation or not_null_violation
                   or foreign_key_violation or invalid_parameter_value or invalid_text_representation
                   or numeric_value_out_of_range or datetime_field_overflow then
      v_rej_ses := v_rej_ses + 1;
      -- Autre appareil / autre UUID pour le même créneau : on garde la session du serveur et
      -- on rattache à celle-ci les tentatives du lot qui référençaient l'UUID écarté.
      begin
        select s.id into v_existing
          from public.learning_sessions s
         where s.user_id = v_uid and s.language_id = v_lang
           and s.local_date = private.try_date(v_s ->> 'local_date')
           and s.slot = nullif(v_s ->> 'slot', '')
           and s.id is distinct from v_id;
        if v_existing is not null and v_id is not null then
          v_remap := v_remap || jsonb_build_object(v_id::text, v_existing::text);
        end if;
      exception when others then
        null;
      end;
    end;
  end loop;

  ------------------------------------------------------------------ attempts
  v_total := jsonb_array_length(private.json_array(payload -> 'attempts'));
  with el as materialized (
    select
      private.try_uuid(e ->> 'id') as id,
      e ->> 'exercise_id' as exercise_id,
      case
        when v_remap ? (e ->> 'session_id') then private.try_uuid(v_remap ->> (e ->> 'session_id'))
        else private.try_uuid(e ->> 'session_id')
      end as session_id,
      private.jsonb_text_array(e -> 'unit_ids') as unit_ids,
      e ->> 'exercise_type' as exercise_type,
      coalesce(nullif(e ->> 'presentation', ''), 'choices') as presentation,
      left(e ->> 'submitted_answer', 2000) as submitted_answer,
      e ->> 'result' as result,
      nullif(e ->> 'error_category', '') as error_category,
      coalesce(private.try_bool(e ->> 'hint_used'), false) as hint_used,
      coalesce(private.try_bool(e ->> 'is_remediation'), false) as is_remediation,
      private.try_int(e ->> 'duration_ms') as duration_ms,
      private.try_timestamptz(e ->> 'answered_at') as answered_at,
      private.try_timestamptz(e ->> 'updated_at') as updated_at_raw
    from jsonb_array_elements(private.json_array(payload -> 'attempts')) as x(e)
    where jsonb_typeof(e) = 'object'
  ),
  fin as (
    select
      el.id,
      el.exercise_id,
      case when exists (select 1 from public.learning_sessions s where s.id = el.session_id and s.user_id = v_uid)
           then el.session_id end as session_id,
      case when cardinality(el.unit_ids) = 0 then coalesce(ex.unit_ids, '{}') else el.unit_ids end as unit_ids,
      el.exercise_type, el.presentation, el.submitted_answer, el.result, el.error_category,
      el.hint_used, el.is_remediation, el.duration_ms, el.answered_at,
      coalesce(el.updated_at_raw, el.answered_at) as updated_at,
      ex.id is not null as exercise_known
    from el
    left join public.exercises ex on ex.id = el.exercise_id and ex.language_id = v_lang
  ),
  chk as (
    select f.*,
      (f.id is not null
       and f.exercise_known
       and f.answered_at is not null
       and coalesce(f.exercise_type, '') <> ''
       and f.result in ('correct', 'correct_typo', 'partial', 'incorrect', 'pending')
       and (f.error_category is null or f.error_category ~ '^[a-z][a-z_]{0,39}$')
       and coalesce(f.duration_ms, 0) >= 0
       and not exists (
         select 1 from unnest(f.unit_ids) as u(unit_id)
          where not exists (select 1 from public.learning_units lu where lu.id = u.unit_id and lu.language_id = v_lang))
      ) as ok
    from fin f
  )
  select
    count(*) filter (where c.ok),
    coalesce((
      select jsonb_agg(to_jsonb(d))
        from (select distinct on (c2.id) c2.* from chk c2 where c2.ok order by c2.id, c2.updated_at desc) d
    ), '[]'::jsonb)
  into v_ok, v_good
  from chk c;

  insert into public.attempts (
    id, user_id, language_id, exercise_id, session_id, unit_ids, exercise_type, presentation,
    submitted_answer, result, error_category, hint_used, is_remediation, duration_ms, answered_at, updated_at)
  select g.id, v_uid, v_lang, g.exercise_id, g.session_id, g.unit_ids, g.exercise_type, g.presentation,
         g.submitted_answer, g.result, g.error_category, g.hint_used, g.is_remediation, g.duration_ms,
         g.answered_at, g.updated_at
    from jsonb_to_recordset(v_good) as g(
      id uuid, exercise_id text, session_id uuid, unit_ids text[], exercise_type text, presentation text,
      submitted_answer text, result text, error_category text, hint_used boolean, is_remediation boolean,
      duration_ms integer, answered_at timestamptz, updated_at timestamptz)
  on conflict (id) do nothing;

  -- Résolution d'une tentative pending (réponse de l'IA) : plus récente et plus définitive.
  update public.attempts a
     set result = g.result, error_category = g.error_category, updated_at = g.updated_at
    from jsonb_to_recordset(v_good) as g(id uuid, result text, error_category text, updated_at timestamptz)
   where a.id = g.id and a.user_id = v_uid
     and a.result = 'pending' and g.result <> 'pending' and g.updated_at > a.updated_at;

  -- Rattachement tardif à une session (tentative arrivée avant sa session).
  update public.attempts a
     set session_id = g.session_id
    from jsonb_to_recordset(v_good) as g(id uuid, session_id uuid)
   where a.id = g.id and a.user_id = v_uid and a.session_id is null and g.session_id is not null;

  v_acc_att := v_ok;
  v_rej_att := v_total - v_ok;

  ------------------------------------------------------------- memory_states
  v_total := jsonb_array_length(private.json_array(payload -> 'memory_states'));
  with el as materialized (
    select
      e ->> 'learning_unit_id' as learning_unit_id,
      coalesce(private.try_float(e ->> 'stability'), 0) as stability,
      coalesce(private.try_float(e ->> 'difficulty'), 5) as difficulty,
      coalesce(private.try_int(e ->> 'review_count'), 0) as review_count,
      coalesce(private.try_int(e ->> 'lapse_count'), 0) as lapse_count,
      coalesce(private.try_int(e ->> 'success_count'), 0) as success_count,
      coalesce(private.try_int(e ->> 'failure_count'), 0) as failure_count,
      coalesce(private.try_int(e ->> 'no_hint_success_count'), 0) as no_hint_success_count,
      coalesce(private.try_int(e ->> 'delayed_success_count'), 0) as delayed_success_count,
      coalesce(private.try_int(e ->> 'production_success_count'), 0) as production_success_count,
      private.jsonb_text_array(e -> 'successful_exercise_types') as successful_exercise_types,
      private.jsonb_bool_array(e -> 'recent_results') as recent_results,
      coalesce(nullif(e ->> 'source', ''), 'lesson') as source,
      private.try_timestamptz(e ->> 'first_seen_at') as first_seen_raw,
      private.try_timestamptz(e ->> 'last_review_at') as last_review_at,
      private.try_timestamptz(e ->> 'next_review_at') as next_review_at,
      coalesce(private.try_timestamptz(e ->> 'updated_at'), now()) as updated_at
    from jsonb_array_elements(private.json_array(payload -> 'memory_states')) as x(e)
    where jsonb_typeof(e) = 'object'
  ),
  chk as (
    select el.*,
      (el.learning_unit_id is not null
       and exists (select 1 from public.learning_units lu where lu.id = el.learning_unit_id and lu.language_id = v_lang)
       and el.stability >= 0 and el.difficulty >= 0
       and el.review_count >= 0 and el.lapse_count >= 0 and el.success_count >= 0 and el.failure_count >= 0
       and el.no_hint_success_count >= 0 and el.delayed_success_count >= 0 and el.production_success_count >= 0
       and el.source in ('lesson', 'diagnostic', 'dictionary')
       and cardinality(el.recent_results) <= 100
      ) as ok
    from el
  )
  select
    count(*) filter (where c.ok),
    coalesce((
      select jsonb_agg(to_jsonb(d))
        from (select distinct on (c2.learning_unit_id) c2.* from chk c2 where c2.ok
              order by c2.learning_unit_id, c2.updated_at desc) d
    ), '[]'::jsonb)
  into v_ok, v_good
  from chk c;

  insert into public.memory_states as ms (
    user_id, language_id, learning_unit_id, stability, difficulty, review_count, lapse_count, success_count,
    failure_count, no_hint_success_count, delayed_success_count, production_success_count,
    successful_exercise_types, recent_results, source, first_seen_at, last_review_at, next_review_at, updated_at)
  select v_uid, v_lang, g.learning_unit_id, g.stability, g.difficulty, g.review_count, g.lapse_count,
         g.success_count, g.failure_count, g.no_hint_success_count, g.delayed_success_count,
         g.production_success_count, g.successful_exercise_types, g.recent_results, g.source,
         coalesce(g.first_seen_raw, g.updated_at), g.last_review_at, g.next_review_at, g.updated_at
    from jsonb_to_recordset(v_good) as g(
      learning_unit_id text, stability double precision, difficulty double precision, review_count integer,
      lapse_count integer, success_count integer, failure_count integer, no_hint_success_count integer,
      delayed_success_count integer, production_success_count integer, successful_exercise_types text[],
      recent_results boolean[], source text, first_seen_raw timestamptz, last_review_at timestamptz,
      next_review_at timestamptz, updated_at timestamptz)
  on conflict (user_id, learning_unit_id) do update set
    stability                 = excluded.stability,
    difficulty                = excluded.difficulty,
    review_count              = excluded.review_count,
    lapse_count               = excluded.lapse_count,
    success_count             = excluded.success_count,
    failure_count             = excluded.failure_count,
    no_hint_success_count     = excluded.no_hint_success_count,
    delayed_success_count     = excluded.delayed_success_count,
    production_success_count  = excluded.production_success_count,
    successful_exercise_types = excluded.successful_exercise_types,
    recent_results            = excluded.recent_results,
    source                    = excluded.source,
    first_seen_at             = least(ms.first_seen_at, excluded.first_seen_at),
    last_review_at            = excluded.last_review_at,
    next_review_at            = excluded.next_review_at,
    updated_at                = excluded.updated_at
  where excluded.updated_at > ms.updated_at;

  v_acc_mem := v_ok;
  v_rej_mem := v_total - v_ok;

  --------------------------------------------------------------- vocabulary
  v_total := jsonb_array_length(private.json_array(payload -> 'vocabulary'));
  with el as materialized (
    select
      e ->> 'dictionary_item_id' as dictionary_item_id,
      coalesce(nullif(e ->> 'learning_status', ''), 'learning') as learning_status,
      private.try_timestamptz(e ->> 'added_at') as added_raw,
      coalesce(private.try_timestamptz(e ->> 'updated_at'), now()) as updated_at
    from jsonb_array_elements(private.json_array(payload -> 'vocabulary')) as x(e)
    where jsonb_typeof(e) = 'object'
  ),
  chk as (
    select el.*,
      (el.dictionary_item_id is not null
       and exists (select 1 from public.dictionary_items di where di.id = el.dictionary_item_id and di.language_id = v_lang)
       and el.learning_status in ('learning', 'known', 'mastered')
      ) as ok
    from el
  )
  select
    count(*) filter (where c.ok),
    coalesce((
      select jsonb_agg(to_jsonb(d))
        from (select distinct on (c2.dictionary_item_id) c2.* from chk c2 where c2.ok
              order by c2.dictionary_item_id, c2.updated_at desc) d
    ), '[]'::jsonb)
  into v_ok, v_good
  from chk c;

  insert into public.user_vocabulary as uv (user_id, dictionary_item_id, added_at, learning_status, updated_at)
  select v_uid, g.dictionary_item_id, coalesce(g.added_raw, g.updated_at), g.learning_status, g.updated_at
    from jsonb_to_recordset(v_good) as g(
      dictionary_item_id text, learning_status text, added_raw timestamptz, updated_at timestamptz)
  on conflict (user_id, dictionary_item_id) do update set
    learning_status = excluded.learning_status,
    added_at        = least(uv.added_at, excluded.added_at),
    updated_at      = excluded.updated_at
  where excluded.updated_at > uv.updated_at;

  v_acc_voc := v_ok;
  v_rej_voc := v_total - v_ok;

  return jsonb_build_object(
    'server_time', private.iso(clock_timestamp()),
    'accepted', jsonb_build_object(
      'attempts', v_acc_att, 'sessions', v_acc_ses, 'memory_states', v_acc_mem, 'vocabulary', v_acc_voc),
    'rejected', jsonb_build_object(
      'attempts', v_rej_att, 'memory_states', v_rej_mem, 'vocabulary', v_rej_voc, 'sessions', v_rej_ses)
  );
end $$;

comment on function public.sync_push(jsonb) is
  'Synchronisation montante idempotente (sessions, attempts, memory_states, vocabulary). Voir docs/04-api.md.';

-- ---------------------------------------------------------------------------
-- sync_pull(p_language_id, p_since) -> jsonb
--
-- Tout ce dont server_updated_at > p_since (epoch = restauration complète).
-- `server_time` est le prochain curseur : il est volontairement en retrait de 2 s sur
-- l'horloge du serveur, pour qu'une transaction concurrente validée un peu après sa
-- lecture ne soit jamais manquée (au pire une ligne est renvoyée deux fois : le client
-- fusionne de façon idempotente). Il ne recule jamais sous p_since.
-- user_language / schedule : null s'ils n'existent pas OU n'ont pas changé depuis p_since.
-- attempts : au plus les 2000 plus récentes (answered_at).
-- ---------------------------------------------------------------------------
create or replace function public.sync_pull(p_language_id text, p_since timestamptz default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_since timestamptz := coalesce(p_since, 'epoch'::timestamptz);
  v_time  timestamptz := clock_timestamp();
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if p_language_id is null or not exists (select 1 from public.languages l where l.id = p_language_id) then
    raise exception 'unknown language_id: %', coalesce(p_language_id, '<null>') using errcode = '22023';
  end if;

  return jsonb_build_object(
    'server_time', private.iso(greatest(v_since, v_time - interval '2 seconds')),

    'user_language', (
      select jsonb_build_object(
        'estimated_level', ul.estimated_level,
        'start_lesson_sequence', ul.start_lesson_sequence,
        'placement', ul.placement,
        'started_at', private.iso(ul.started_at),
        'updated_at', private.iso(ul.updated_at))
        from public.user_languages ul
       where ul.user_id = v_uid and ul.language_id = p_language_id and ul.server_updated_at > v_since
    ),

    'schedule', (
      select jsonb_build_object(
        'morning_time', to_char(ds.morning_time, 'HH24:MI'),
        'afternoon_time', to_char(ds.afternoon_time, 'HH24:MI'),
        'evening_time', to_char(ds.evening_time, 'HH24:MI'),
        'timezone', ds.timezone,
        'enabled', ds.enabled,
        'safety_window_minutes', ds.safety_window_minutes,
        'early_start_minutes', ds.early_start_minutes,
        'updated_at', private.iso(ds.updated_at))
        from public.daily_schedules ds
       where ds.user_id = v_uid and ds.server_updated_at > v_since
    ),

    'sessions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'session_type', s.session_type,
        'slot', s.slot,
        'local_date', to_char(s.local_date, 'YYYY-MM-DD'),
        'scheduled_at', private.iso(s.scheduled_at),
        'started_at', private.iso(s.started_at),
        'completed_at', private.iso(s.completed_at),
        'status', s.status,
        'lesson_id', s.lesson_id,
        'item_count', s.item_count,
        'correct_count', s.correct_count,
        'duration_seconds', s.duration_seconds,
        'score', s.score,
        'emergency_unlocked', s.emergency_unlocked,
        'validated', s.validated,
        'updated_at', private.iso(s.updated_at)) order by s.server_updated_at, s.id)
        from public.learning_sessions s
       where s.user_id = v_uid and s.language_id = p_language_id and s.server_updated_at > v_since
    ), '[]'::jsonb),

    'memory_states', coalesce((
      select jsonb_agg(jsonb_build_object(
        'learning_unit_id', m.learning_unit_id,
        'stability', m.stability,
        'difficulty', m.difficulty,
        'review_count', m.review_count,
        'lapse_count', m.lapse_count,
        'success_count', m.success_count,
        'failure_count', m.failure_count,
        'no_hint_success_count', m.no_hint_success_count,
        'delayed_success_count', m.delayed_success_count,
        'production_success_count', m.production_success_count,
        'successful_exercise_types', to_jsonb(m.successful_exercise_types),
        'recent_results', to_jsonb(m.recent_results),
        'source', m.source,
        'first_seen_at', private.iso(m.first_seen_at),
        'last_review_at', private.iso(m.last_review_at),
        'next_review_at', private.iso(m.next_review_at),
        'updated_at', private.iso(m.updated_at)) order by m.server_updated_at, m.learning_unit_id)
        from public.memory_states m
       where m.user_id = v_uid and m.language_id = p_language_id and m.server_updated_at > v_since
    ), '[]'::jsonb),

    'vocabulary', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dictionary_item_id', uv.dictionary_item_id,
        'added_at', private.iso(uv.added_at),
        'learning_status', uv.learning_status,
        'updated_at', private.iso(uv.updated_at)) order by uv.server_updated_at, uv.dictionary_item_id)
        from public.user_vocabulary uv
        join public.dictionary_items di on di.id = uv.dictionary_item_id
       where uv.user_id = v_uid and di.language_id = p_language_id and uv.server_updated_at > v_since
    ), '[]'::jsonb),

    'attempts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id,
        'exercise_id', t.exercise_id,
        'session_id', t.session_id,
        'unit_ids', to_jsonb(t.unit_ids),
        'exercise_type', t.exercise_type,
        'presentation', t.presentation,
        'submitted_answer', t.submitted_answer,
        'result', t.result,
        'error_category', t.error_category,
        'hint_used', t.hint_used,
        'is_remediation', t.is_remediation,
        'duration_ms', t.duration_ms,
        'answered_at', private.iso(t.answered_at),
        'updated_at', private.iso(t.updated_at)) order by t.answered_at desc, t.id)
        from (
          select a.* from public.attempts a
           where a.user_id = v_uid and a.language_id = p_language_id and a.server_updated_at > v_since
           order by a.answered_at desc, a.id
           limit 2000
        ) t
    ), '[]'::jsonb)
  );
end $$;

comment on function public.sync_pull(text, timestamptz) is
  'Synchronisation descendante par curseur server_updated_at. Voir docs/04-api.md.';

-- ---------------------------------------------------------------------------
-- content_manifest(p_language_id) -> jsonb | null
-- ---------------------------------------------------------------------------
create or replace function public.content_manifest(p_language_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'version', cv.version,
    'bundle_path', cv.bundle_path,
    'sha256', cv.sha256,
    'published_at', private.iso(cv.published_at))
  from public.content_versions cv
  where cv.language_id = p_language_id and cv.is_current
  limit 1
$$;

comment on function public.content_manifest(text) is
  'Version courante du bundle de contenu d''une langue, ou null.';

-- ---------------------------------------------------------------------------
-- Droits : authentifiés uniquement (jamais anon / public).
-- ---------------------------------------------------------------------------
revoke execute on function public.sync_push(jsonb)                  from public, anon;
revoke execute on function public.sync_pull(text, timestamptz)      from public, anon;
revoke execute on function public.content_manifest(text)            from public, anon;
grant  execute on function public.sync_push(jsonb)                  to authenticated, service_role;
grant  execute on function public.sync_pull(text, timestamptz)      to authenticated, service_role;
grant  execute on function public.content_manifest(text)            to authenticated, service_role;
