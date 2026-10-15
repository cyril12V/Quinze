-- 20 — RPC sync_push / sync_pull / content_manifest.
-- Idempotence, dernière écriture gagne, références inconnues, anti-fraude,
-- curseur server_updated_at, restauration complète, isolation entre utilisateurs.

create or replace function tests.uid(n integer) returns uuid
language sql immutable as $$ select ('c1000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;

create or replace function tests.mk_attempt(
  p_id uuid, p_exercise text, p_session uuid default null, p_result text default 'correct',
  p_updated text default '2026-10-13T07:12:44.120Z', p_answer text default 'go')
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', p_id, 'exercise_id', p_exercise, 'session_id', p_session,
    'unit_ids', coalesce((select to_jsonb(e.unit_ids) from public.exercises e where e.id = p_exercise), '["en.g.unknown"]'::jsonb),
    'exercise_type', 'fill_blank', 'presentation', 'choices', 'submitted_answer', p_answer,
    'result', p_result, 'error_category', null, 'hint_used', false, 'is_remediation', false,
    'duration_ms', 8200, 'answered_at', '2026-10-13T07:12:44.120Z', 'updated_at', p_updated)
$$;

create or replace function tests.mk_session(
  p_id uuid, p_type text, p_slot text, p_status text,
  p_updated text default '2026-10-13T07:20:00.000Z', p_date text default '2026-10-13', p_items integer default 11)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', p_id, 'session_type', p_type, 'slot', p_slot, 'local_date', p_date,
    'scheduled_at', null, 'started_at', '2026-10-13T07:10:00.000Z', 'completed_at', '2026-10-13T07:15:00.000Z',
    'status', p_status, 'lesson_id', null, 'item_count', p_items, 'correct_count', 8, 'duration_seconds', 312,
    'score', null, 'emergency_unlocked', false, 'updated_at', p_updated)
$$;

create or replace function tests.mk_ms(p_unit text, p_updated text default '2026-10-13T07:30:00.000Z', p_stability double precision default 3.7)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'learning_unit_id', p_unit, 'stability', p_stability, 'difficulty', 5.2, 'review_count', 4, 'lapse_count', 1,
    'success_count', 3, 'failure_count', 1, 'no_hint_success_count', 3, 'delayed_success_count', 1,
    'production_success_count', 1, 'successful_exercise_types', jsonb_build_array('mcq', 'fill_blank'),
    'recent_results', jsonb_build_array(true, false, true), 'source', 'lesson',
    'first_seen_at', '2026-10-01T08:00:00.000Z', 'last_review_at', null, 'next_review_at', '2026-10-15T08:00:00.000Z',
    'updated_at', p_updated)
$$;

create or replace function tests.mk_voc(p_item text, p_status text default 'learning', p_updated text default '2026-10-13T07:40:00.000Z')
returns jsonb language sql stable as $$
  select jsonb_build_object('dictionary_item_id', p_item, 'added_at', '2026-10-13T07:39:00.000Z',
                            'learning_status', p_status, 'updated_at', p_updated)
$$;

create or replace function tests.snapshot() returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'sessions', (select jsonb_agg(to_jsonb(s) order by s.id) from public.learning_sessions s),
    'attempts', (select jsonb_agg(to_jsonb(a) order by a.id) from public.attempts a),
    'memory',   (select jsonb_agg(to_jsonb(m) order by m.learning_unit_id) from public.memory_states m),
    'vocab',    (select jsonb_agg(to_jsonb(v) order by v.dictionary_item_id) from public.user_vocabulary v))
$$;

do $test$
declare
  a constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b constant uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  s1 constant uuid := 'c0000000-0000-4000-8000-000000000001';
  s2 constant uuid := 'c0000000-0000-4000-8000-000000000002';
  s3 constant uuid := 'c0000000-0000-4000-8000-000000000003';
  s4 constant uuid := 'c0000000-0000-4000-8000-000000000004';
  s5 constant uuid := 'c0000000-0000-4000-8000-000000000005';
  ex text[]; units text[]; dis text[];
  p jsonb; r jsonb; r2 jsonb; snap jsonb; snap2 jsonb;
  cursor_ts timestamptz;
  n integer;
  iso_re constant text := '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$';
begin
  perform tests.as_admin();
  delete from auth.users where id in (a, b);
  insert into auth.users (id, email) values (a, 'a@example.test'), (b, 'b@example.test');
  select array_agg(id order by id) into ex
    from (select id from public.exercises where language_id = 'en' and lesson_id is not null order by id limit 12) q;
  select array_agg(id order by id) into units from (select id from public.learning_units where language_id = 'en' order by id limit 4) q;
  select array_agg(id order by id) into dis from (select id from public.dictionary_items where language_id = 'en' order by id limit 4) q;
  perform tests.ok(cardinality(ex) = 12 and cardinality(units) = 4 and cardinality(dis) = 4, 'jeu de données de test sélectionné');

  -- ---------------------------------------------------- erreurs de l'appelant
  perform tests.as_anon();
  perform tests.throws($q$select public.sync_push('{"language_id":"en"}')$q$, '42501', 'sync_push : anon refusé');
  perform set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  perform tests.throws($q$select public.sync_push('{"language_id":"en"}')$q$, '28000', 'sync_push : jeton sans utilisateur refusé');
  perform tests.throws($q$select public.sync_pull('en', null)$q$, '28000', 'sync_pull : jeton sans utilisateur refusé');

  perform tests.as_user(a);
  perform tests.throws($q$select public.sync_push(null)$q$, '22023', 'sync_push : payload null refusé');
  perform tests.throws($q$select public.sync_push('[]')$q$, '22023', 'sync_push : payload non objet refusé');
  perform tests.throws($q$select public.sync_push('{"language_id":"xx"}')$q$, '22023', 'sync_push : langue inconnue refusée');
  perform tests.throws($q$select public.sync_push('{"language_id":"en","attempts":{}}')$q$, '22023', 'sync_push : attempts non tableau refusé');
  perform tests.throws($q$select public.sync_push((select jsonb_build_object('language_id', 'en', 'attempts', jsonb_agg('{}'::jsonb)) from generate_series(1, 5001)))$q$,
    'PT413', 'sync_push : lot trop gros refusé (HTTP 413 côté PostgREST)');
  perform tests.throws($q$select public.sync_pull('xx', null)$q$, '22023', 'sync_pull : langue inconnue refusée');

  -- ------------------------------------------------ premier envoi (utilisateur A)
  p := jsonb_build_object(
    'language_id', 'en',
    'sessions', jsonb_build_array(
      tests.mk_session(s1, 'learning', 'morning', 'completed'),
      tests.mk_session(s2, 'learning', 'afternoon', 'completed'),
      tests.mk_session(s3, 'review', 'evening', 'completed')),
    'attempts', jsonb_build_array(
      tests.mk_attempt(tests.uid(1), ex[1], s1), tests.mk_attempt(tests.uid(2), ex[2], s1),
      tests.mk_attempt(tests.uid(3), ex[3], s1), tests.mk_attempt(tests.uid(4), ex[4], s1),
      tests.mk_attempt(tests.uid(5), ex[5], s2), tests.mk_attempt(tests.uid(6), ex[6], s2),
      tests.mk_attempt(tests.uid(7), 'en.zz.inconnu', s2),
      tests.mk_attempt(tests.uid(8), ex[1], s2) || jsonb_build_object('unit_ids', jsonb_build_array('en.g.inconnue')),
      tests.mk_attempt(tests.uid(9), ex[1], s2, 'bogus')),
    'memory_states', jsonb_build_array(tests.mk_ms(units[1]), tests.mk_ms(units[2]), tests.mk_ms('en.g.inconnue')),
    'vocabulary', jsonb_build_array(tests.mk_voc(dis[1]), tests.mk_voc(dis[2]), tests.mk_voc('en.d.inconnu')));
  r := public.sync_push(p);
  perform tests.ok(r -> 'accepted' = '{"attempts":6,"sessions":3,"memory_states":2,"vocabulary":2}'::jsonb, 'sync_push : compteurs accepted');
  perform tests.ok((r -> 'rejected') @> '{"attempts":3,"memory_states":1,"vocabulary":1,"sessions":0}'::jsonb,
    'sync_push : références inconnues / lignes invalides comptées dans rejected');
  perform tests.ok((r ->> 'server_time') ~ iso_re, 'sync_push : server_time au format ISO 8601 UTC (ms)');
  perform tests.ok((select count(*) from public.attempts) = 6, 'sync_push : 6 tentatives enregistrées, les rejetées ignorées');
  perform tests.ok((select count(*) from public.attempts where exercise_id = 'en.zz.inconnu') = 0, 'sync_push : exercice inconnu non enregistré');
  perform tests.ok((select count(*) from public.memory_states) = 2 and (select count(*) from public.user_vocabulary) = 2,
    'sync_push : états mémoire et vocabulaire enregistrés');

  -- anti-fraude
  perform tests.ok((select validated from public.learning_sessions where id = s1), 'anti-fraude : 4 tentatives (même lot, après la session) -> validated');
  perform tests.ok(not (select validated from public.learning_sessions where id = s2), 'anti-fraude : 2 tentatives -> validated = false (session conservée)');
  perform tests.ok((select validated from public.learning_sessions where id = s3), 'anti-fraude : type review non concerné');
  perform tests.ok((select count(*) from public.learning_sessions) = 3, 'anti-fraude : la session invalidée reste enregistrée');

  -- ------------------------------------------------------------- idempotence
  snap := tests.snapshot();
  r2 := public.sync_push(p);
  snap2 := tests.snapshot();
  perform tests.ok(r2 -> 'accepted' = r -> 'accepted' and r2 -> 'rejected' = r -> 'rejected', 'idempotence : mêmes compteurs au renvoi du même lot');
  perform tests.ok(snap = snap2, 'idempotence : aucune ligne modifiée (server_updated_at inclus) au renvoi');

  -- ------------------------------------------- dernière écriture gagne (updated_at)
  r := public.sync_push(jsonb_build_object('language_id', 'en',
    'sessions', jsonb_build_array(tests.mk_session(s1, 'learning', 'morning', 'skipped', '2026-10-13T07:00:00.000Z')),
    'memory_states', jsonb_build_array(tests.mk_ms(units[1], '2026-10-13T06:00:00.000Z', 99)),
    'vocabulary', jsonb_build_array(tests.mk_voc(dis[1], 'mastered', '2026-10-13T06:00:00.000Z'))));
  perform tests.ok((select status from public.learning_sessions where id = s1) = 'completed', 'LWW : session plus ancienne ignorée');
  perform tests.ok((select stability from public.memory_states where learning_unit_id = units[1]) = 3.7, 'LWW : état mémoire plus ancien ignoré');
  perform tests.ok((select learning_status from public.user_vocabulary where dictionary_item_id = dis[1]) = 'learning', 'LWW : vocabulaire plus ancien ignoré');
  r := public.sync_push(jsonb_build_object('language_id', 'en',
    'sessions', jsonb_build_array(tests.mk_session(s1, 'learning', 'morning', 'completed', '2026-10-13T08:00:00.000Z', '2026-10-13', 99)),
    'memory_states', jsonb_build_array(tests.mk_ms(units[1], '2026-10-13T09:00:00.000Z', 7.5)),
    'vocabulary', jsonb_build_array(tests.mk_voc(dis[1], 'known', '2026-10-13T09:00:00.000Z'))));
  perform tests.ok((select item_count from public.learning_sessions where id = s1) = 99, 'LWW : session plus récente appliquée');
  perform tests.ok((select stability from public.memory_states where learning_unit_id = units[1]) = 7.5, 'LWW : état mémoire plus récent appliqué');
  perform tests.ok((select learning_status from public.user_vocabulary where dictionary_item_id = dis[1]) = 'known', 'LWW : vocabulaire plus récent appliqué');
  perform tests.ok((select validated from public.learning_sessions where id = s1), 'LWW : validated conservé après mise à jour de la session');

  -- tentative pending -> résolue par l'IA, puis immuable
  perform public.sync_push(jsonb_build_object('language_id', 'en', 'attempts',
    jsonb_build_array(tests.mk_attempt(tests.uid(20), ex[7], s1, 'pending', '2026-10-13T07:30:00.000Z', 'I goes'))));
  perform tests.ok((select result from public.attempts where id = tests.uid(20)) = 'pending', 'attempt pending enregistrée');
  perform public.sync_push(jsonb_build_object('language_id', 'en', 'attempts',
    jsonb_build_array(tests.mk_attempt(tests.uid(20), ex[7], s1, 'incorrect', '2026-10-13T07:31:00.000Z', 'I goes'))));
  perform tests.ok((select result from public.attempts where id = tests.uid(20)) = 'incorrect', 'attempt pending résolue par un renvoi plus récent');
  perform public.sync_push(jsonb_build_object('language_id', 'en', 'attempts',
    jsonb_build_array(tests.mk_attempt(tests.uid(20), ex[7], s1, 'correct', '2026-10-13T07:40:00.000Z', 'changé'))));
  perform tests.ok((select result from public.attempts where id = tests.uid(20)) = 'incorrect'
                   and (select submitted_answer from public.attempts where id = tests.uid(20)) = 'I goes', 'attempt résolue : immuable');

  -- même créneau, autre UUID (deuxième appareil) : la session du serveur est gardée
  r := public.sync_push(jsonb_build_object('language_id', 'en',
    'sessions', jsonb_build_array(tests.mk_session(s4, 'learning', 'morning', 'completed', '2026-10-13T08:30:00.000Z')),
    'attempts', jsonb_build_array(tests.mk_attempt(tests.uid(30), ex[8], s4))));
  perform tests.ok((r -> 'rejected' ->> 'sessions')::int = 1 and (r -> 'accepted' ->> 'attempts')::int = 1, 'conflit de créneau : session écartée, tentative acceptée');
  perform tests.ok((select session_id from public.attempts where id = tests.uid(30)) = s1, 'conflit de créneau : tentative rattachée à la session existante');
  perform tests.ok(not exists (select 1 from public.learning_sessions where id = s4), 'conflit de créneau : aucun doublon de session');

  -- lignes mal formées : rejetées sans faire échouer le lot
  r := public.sync_push('{"language_id":"en","sessions":[{"id":"nope"}],"attempts":[{"id":"pas-un-uuid"}, 5, "x"],"memory_states":[null],"vocabulary":[{}]}');
  perform tests.ok(r -> 'accepted' = '{"attempts":0,"sessions":0,"memory_states":0,"vocabulary":0}'::jsonb
                   and (r -> 'rejected' ->> 'attempts')::int = 3 and (r -> 'rejected' ->> 'sessions')::int = 1
                   and (r -> 'rejected' ->> 'memory_states')::int = 1 and (r -> 'rejected' ->> 'vocabulary')::int = 1, 'lignes mal formées : rejetées, lot non interrompu');
  r := public.sync_push('{"language_id":"en"}');
  perform tests.ok(r -> 'accepted' = '{"attempts":0,"sessions":0,"memory_states":0,"vocabulary":0}'::jsonb, 'lot vide accepté');

  -- tentative d'une exercice d'une autre langue
  perform tests.as_admin();
  insert into public.languages (id, code, name, native_name, tts_locale, is_available) values ('fr', 'fr', 'Français', 'Français', 'fr-FR', false);
  perform tests.as_user(a);
  r := public.sync_push(jsonb_build_object('language_id', 'fr', 'attempts', jsonb_build_array(tests.mk_attempt(tests.uid(40), ex[9], null))));
  perform tests.ok((r -> 'rejected' ->> 'attempts')::int = 1, 'exercice d''une autre langue rejeté');

  -- ----------------------------------------------- isolation entre utilisateurs
  perform tests.as_user(b);
  r := public.sync_push(jsonb_build_object('language_id', 'en',
    'sessions', jsonb_build_array(tests.mk_session(s1, 'learning', 'morning', 'skipped', '2030-01-01T00:00:00.000Z')),
    'attempts', jsonb_build_array(tests.mk_attempt(tests.uid(1), ex[1], null, 'incorrect', '2030-01-01T00:00:00.000Z'))));
  perform tests.ok((r -> 'rejected' ->> 'sessions')::int = 1, 'B ne peut pas écraser la session de A via sync_push');
  perform tests.ok((select count(*) from public.attempts) = 0 and (select count(*) from public.learning_sessions) = 0, 'B ne voit toujours rien de A');
  perform tests.as_admin();
  perform tests.ok((select user_id from public.attempts where id = tests.uid(1)) = a and (select result from public.attempts where id = tests.uid(1)) = 'correct',
    'la tentative de A n''a pas été modifiée par B');
  perform tests.ok((select status from public.learning_sessions where id = s1) = 'completed', 'la session de A n''a pas été modifiée par B');

  -- -------------------------------------------------------------- sync_pull
  perform tests.as_user(a);
  r := public.sync_pull('en', null);
  perform tests.ok(jsonb_array_length(r -> 'sessions') = 3 and jsonb_array_length(r -> 'memory_states') = 2
                   and jsonb_array_length(r -> 'vocabulary') = 2
                   and jsonb_array_length(r -> 'attempts') = (select count(*) from public.attempts),
    'sync_pull(null) : restauration complète');
  perform tests.ok(r -> 'user_language' = 'null'::jsonb and r -> 'schedule' = 'null'::jsonb, 'sync_pull : user_language et schedule null s''ils n''existent pas');
  perform tests.ok((r ->> 'server_time') ~ iso_re, 'sync_pull : server_time au format ISO 8601 UTC (ms)');
  perform tests.ok((select bool_and((x ->> 'updated_at') ~ iso_re and (x ->> 'local_date') ~ '^\d{4}-\d{2}-\d{2}$') from jsonb_array_elements(r -> 'sessions') x),
    'sync_pull : dates ISO 8601 et local_date yyyy-MM-dd');
  perform tests.ok((select x ->> 'updated_at' from jsonb_array_elements(r -> 'sessions') x where x ->> 'id' = s1::text) = '2026-10-13T08:00:00.000Z',
    'sync_pull : updated_at client restitué à l''identique');
  perform tests.ok((select (x ->> 'validated')::boolean from jsonb_array_elements(r -> 'sessions') x where x ->> 'id' = s2::text) = false, 'sync_pull : validated restitué');
  perform tests.ok((select x -> 'recent_results' from jsonb_array_elements(r -> 'memory_states') x where x ->> 'learning_unit_id' = units[2]) = '[true,false,true]'::jsonb
                   and (select x -> 'successful_exercise_types' from jsonb_array_elements(r -> 'memory_states') x where x ->> 'learning_unit_id' = units[2]) = '["mcq","fill_blank"]'::jsonb,
    'sync_pull : tableaux des états mémoire restitués');
  perform tests.ok((select x -> 'unit_ids' from jsonb_array_elements(r -> 'attempts') x where x ->> 'id' = tests.uid(1)::text) is not null
                   and (select count(*) from jsonb_array_elements(r -> 'attempts') x where x ->> 'id' = tests.uid(1)::text) = 1, 'sync_pull : attempts restituées');

  insert into public.user_languages (language_id, estimated_level, start_lesson_sequence, placement, started_at)
    values ('en', 3, 10, '{"score": 7, "levels": [1,2]}', '2026-10-12T09:00:00Z');
  insert into public.daily_schedules (morning_time, afternoon_time, evening_time, timezone) values ('09:00', '14:00', '20:00', 'Europe/Paris');
  r := public.sync_pull('en', 'epoch');
  perform tests.ok((r -> 'user_language' ->> 'estimated_level') = '3' and (r -> 'user_language' -> 'placement' ->> 'score') = '7'
                   and (r -> 'user_language' ->> 'started_at') = '2026-10-12T09:00:00.000Z', 'sync_pull : user_language (placement inclus)');
  perform tests.ok((r -> 'schedule' ->> 'morning_time') = '09:00' and (r -> 'schedule' ->> 'evening_time') = '20:00'
                   and (r -> 'schedule' ->> 'timezone') = 'Europe/Paris' and (r -> 'schedule' ->> 'enabled') = 'true', 'sync_pull : schedule (heures HH:mm)');

  -- curseur : seules les lignes écrites après server_time reviennent
  perform pg_sleep(2.3);
  r := public.sync_pull('en', 'epoch');
  cursor_ts := (r ->> 'server_time')::timestamptz;
  perform public.sync_push(jsonb_build_object('language_id', 'en',
    'sessions', jsonb_build_array(tests.mk_session(s5, 'learning', 'evening', 'completed', '2026-10-14T20:00:00.000Z', '2026-10-14')),
    'attempts', jsonb_build_array(tests.mk_attempt(tests.uid(50), ex[10], s5)),
    'memory_states', jsonb_build_array(tests.mk_ms(units[1], '2026-10-14T20:00:00.000Z', 8.8)),
    'vocabulary', jsonb_build_array(tests.mk_voc(dis[3], 'learning', '2026-10-14T20:00:00.000Z'))));
  r2 := public.sync_pull('en', cursor_ts);
  perform tests.ok(jsonb_array_length(r2 -> 'sessions') = 1 and (r2 -> 'sessions' -> 0 ->> 'id') = s5::text, 'curseur : une seule session nouvelle');
  perform tests.ok(jsonb_array_length(r2 -> 'attempts') = 1 and (r2 -> 'attempts' -> 0 ->> 'id') = tests.uid(50)::text, 'curseur : une seule tentative nouvelle');
  perform tests.ok(jsonb_array_length(r2 -> 'memory_states') = 1 and (r2 -> 'memory_states' -> 0 ->> 'stability') = '8.8', 'curseur : état mémoire mis à jour');
  perform tests.ok(jsonb_array_length(r2 -> 'vocabulary') = 1 and (r2 -> 'vocabulary' -> 0 ->> 'dictionary_item_id') = dis[3], 'curseur : nouveau mot');
  perform tests.ok(r2 -> 'user_language' = 'null'::jsonb and r2 -> 'schedule' = 'null'::jsonb, 'curseur : user_language / schedule inchangés -> null');
  perform tests.ok((r2 ->> 'server_time')::timestamptz >= cursor_ts, 'curseur : server_time ne recule jamais');
  r2 := public.sync_pull('en', now() + interval '1 hour');
  perform tests.ok(jsonb_array_length(r2 -> 'sessions') = 0 and jsonb_array_length(r2 -> 'attempts') = 0
                   and jsonb_array_length(r2 -> 'memory_states') = 0 and jsonb_array_length(r2 -> 'vocabulary') = 0, 'curseur futur : rien');
  r2 := public.sync_pull('fr', null);
  perform tests.ok(jsonb_array_length(r2 -> 'sessions') = 0 and jsonb_array_length(r2 -> 'attempts') = 0, 'sync_pull filtre par langue');

  -- l'utilisateur B ne reçoit rien de A ; plafond de 2000 tentatives
  perform tests.as_user(b);
  r := public.sync_pull('en', null);
  perform tests.ok(jsonb_array_length(r -> 'sessions') = 0 and jsonb_array_length(r -> 'attempts') = 0
                   and jsonb_array_length(r -> 'memory_states') = 0 and jsonb_array_length(r -> 'vocabulary') = 0
                   and r -> 'user_language' = 'null'::jsonb, 'sync_pull : B ne reçoit rien de A');
  perform tests.as_admin();
  insert into public.attempts (id, user_id, language_id, exercise_id, unit_ids, exercise_type, result, answered_at)
    select gen_random_uuid(), b, 'en', ex[1], '{}', 'mcq', 'correct', timestamptz '2026-01-01 00:00:00+00' + (g || ' minutes')::interval
      from generate_series(1, 2005) g;
  perform tests.as_user(b);
  r := public.sync_pull('en', 'epoch');
  perform tests.ok(jsonb_array_length(r -> 'attempts') = 2000, 'sync_pull : au plus 2000 tentatives');
  perform tests.ok((r -> 'attempts' -> 0 ->> 'answered_at') = '2026-01-02T09:25:00.000Z', 'sync_pull : ce sont les plus récentes (answered_at décroissant)');

  -- ------------------------------------------------------- content_manifest
  perform tests.as_user(a);
  r := public.content_manifest('en');
  perform tests.ok(r ->> 'version' ~ '^\d+\.\d+\.\d+' and r ->> 'bundle_path' = 'en/' || (r ->> 'version') || '.json'
                   and r ->> 'sha256' ~ '^[0-9a-f]{64}$' and r ->> 'published_at' ~ iso_re, 'content_manifest : version courante');
  perform tests.ok(public.content_manifest('xx') is null, 'content_manifest : null si langue sans contenu');
  perform tests.ok(public.content_manifest('fr') is null, 'content_manifest : null si aucune version publiée');

  -- ------------------------------------------------------------------ nettoyage
  perform tests.as_admin();
  delete from auth.users where id in (a, b);
  delete from public.languages where id = 'fr';
  perform tests.ok(true, 'nettoyage');
end
$test$;
