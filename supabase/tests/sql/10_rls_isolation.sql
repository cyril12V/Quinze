-- 10 — RLS, privilèges, contraintes et triggers.
-- Deux utilisateurs (A, B) : chacun ne voit / ne modifie / ne supprime que ses lignes.

do $test$
declare
  a     constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b     constant uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  s_a   constant uuid := 'a0000000-0000-4000-8000-000000000001';
  s_a2  constant uuid := 'a0000000-0000-4000-8000-000000000002';
  s_a3  constant uuid := 'a0000000-0000-4000-8000-000000000003';
  att_a constant uuid := 'a0000000-0000-4000-8000-0000000000a1';
  ex text; un text; di text;
  n integer;
  t text;
  v boolean;
  ts timestamptz;
begin
  perform tests.as_admin();
  delete from auth.users where id in (a, b);
  insert into auth.users (id, email, raw_user_meta_data)
  values (a, 'a@example.test', '{"display_name":"Alice"}'), (b, 'b@example.test', '{}');

  select e.id, e.learning_unit_id into ex, un
    from public.exercises e where e.language_id = 'en' and e.lesson_id is not null order by e.id limit 1;
  select d.id into di from public.dictionary_items d where d.language_id = 'en' order by d.id limit 1;
  perform tests.ok(ex is not null and un is not null and di is not null, 'contenu réel chargé (exercice, unité, mot)');

  -- ---------------------------------------------------------------- structure
  select count(*) into n
    from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  perform tests.ok(n = 0, 'RLS activée sur toutes les tables de public');

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  perform tests.ok(n = 0, 'aucune fonction de public exécutable par anon');

  perform tests.ok((select count(*) from public.profiles where id in (a, b)) = 2, 'profil créé par trigger à l''inscription');
  perform tests.ok((select display_name from public.profiles where id = a) = 'Alice', 'display_name repris des métadonnées d''inscription');
  update auth.users set email = 'a2@example.test' where id = a;
  perform tests.ok((select email from public.profiles where id = a) = 'a2@example.test', 'l''e-mail du profil suit auth.users');

  -- ------------------------------------------------------- A écrit ses lignes
  perform tests.as_user(a);
  insert into public.user_languages (language_id, estimated_level, start_lesson_sequence, placement)
    values ('en', 2, 10, '{"score": 7}');
  insert into public.daily_schedules (timezone) values ('Europe/Paris');
  insert into public.learning_sessions (id, language_id, session_type, slot, local_date, status, updated_at)
    values (s_a, 'en', 'learning', 'morning', '2026-10-13', 'in_progress', '2026-10-13T07:00:00Z');
  insert into public.attempts (id, language_id, exercise_id, session_id, unit_ids, exercise_type, result, answered_at)
    values (att_a, 'en', ex, s_a, array[un], 'fill_blank', 'pending', '2026-10-13T07:01:00Z');
  insert into public.memory_states (language_id, learning_unit_id) values ('en', un);
  insert into public.user_vocabulary (dictionary_item_id) values (di);
  update public.profiles set display_name = 'Alice 2', pedagogical_prefs = '{"detail":"short"}' where id = a;
  perform tests.ok((select display_name from public.profiles where id = a) = 'Alice 2', 'A met à jour son profil');
  perform tests.ok((select user_id from public.user_languages) = a, 'user_id posé par défaut (auth.uid())');

  foreach t in array array['user_languages', 'daily_schedules', 'learning_sessions', 'attempts', 'memory_states', 'user_vocabulary'] loop
    execute format('select count(*) from public.%I', t) into n;
    perform tests.ok(n = 1, format('A voit sa ligne dans %s', t));
  end loop;

  -- ------------------------------------------------------------- B est isolé
  perform tests.as_user(b);
  foreach t in array array['user_languages', 'daily_schedules', 'learning_sessions', 'attempts', 'memory_states', 'user_vocabulary'] loop
    execute format('select count(*) from public.%I', t) into n;
    perform tests.ok(n = 0, format('B ne voit rien de A dans %s (select)', t));
  end loop;
  perform tests.ok((select count(*) from public.profiles) = 1 and (select id from public.profiles) = b, 'B ne voit que son profil');

  update public.learning_sessions set status = 'skipped' where id = s_a;
  get diagnostics n = row_count;
  perform tests.ok(n = 0, 'B ne peut pas modifier la session de A (update : 0 ligne)');
  update public.user_vocabulary set learning_status = 'known';
  get diagnostics n = row_count;
  perform tests.ok(n = 0, 'B ne peut pas modifier le vocabulaire de A');
  update public.profiles set display_name = 'Hacked' where id = a;
  get diagnostics n = row_count;
  perform tests.ok(n = 0, 'B ne peut pas modifier le profil de A');
  delete from public.attempts where id = att_a;
  get diagnostics n = row_count;
  perform tests.ok(n = 0, 'B ne peut pas supprimer la tentative de A (delete : 0 ligne)');
  delete from public.memory_states;
  get diagnostics n = row_count;
  perform tests.ok(n = 0, 'B ne peut pas supprimer les états mémoire de A');

  perform tests.throws(format($q$insert into public.user_languages (user_id, language_id) values (%L, 'en')$q$, a),
    '42501', 'B ne peut pas insérer une ligne au nom de A (user_languages)');
  perform tests.throws(format($q$insert into public.learning_sessions (id, user_id, language_id, session_type, local_date, status)
    values (gen_random_uuid(), %L, 'en', 'learning', '2026-10-13', 'scheduled')$q$, a),
    '42501', 'B ne peut pas insérer une session au nom de A');
  perform tests.throws(format($q$insert into public.attempts (id, language_id, exercise_id, session_id, unit_ids, exercise_type, result, answered_at)
    values (gen_random_uuid(), 'en', %L, %L, '{}', 'mcq', 'correct', now())$q$, ex, s_a),
    '42501', 'B ne peut pas rattacher une tentative à la session de A');
  perform tests.throws(format($q$insert into public.attempts (id, user_id, language_id, exercise_id, unit_ids, exercise_type, result, answered_at)
    values (gen_random_uuid(), %L, 'en', %L, '{}', 'mcq', 'correct', now())$q$, a, ex),
    '42501', 'B ne peut pas insérer une tentative au nom de A');
  perform tests.throws($q$update public.profiles set email = 'x@example.test'$q$, '42501', 'l''e-mail du profil n''est pas modifiable par le client');
  perform tests.throws($q$delete from public.profiles$q$, '42501', 'un client ne peut pas supprimer son profil');
  perform tests.throws(format($q$insert into public.profiles (id, email) values (%L, 'z@example.test')$q$, b), '42501', 'un client ne peut pas créer de profil');

  -- ------------------------------------------------- ai_interactions / ai_cache
  perform tests.as_admin();
  insert into public.ai_interactions (user_id, request_type, response_status, model) values (a, 'explain-rule', 'ok', 'm');
  insert into public.ai_cache (cache_key, request_type, response, model) values (repeat('a', 64), 'explain-rule', '{"text":"x"}', 'm');

  perform tests.as_user(b);
  perform tests.ok((select count(*) from public.ai_interactions) = 0, 'B ne voit pas les ai_interactions de A');
  perform tests.throws($q$insert into public.ai_interactions (user_id, request_type, response_status) values (auth.uid(), 'explain-rule', 'ok')$q$,
    '42501', 'un client ne peut pas écrire dans ai_interactions');
  perform tests.throws($q$select count(*) from public.ai_cache$q$, '42501', 'ai_cache inaccessible aux utilisateurs');
  perform tests.throws($q$select public.ai_cache_get(repeat('a', 64))$q$, '42501', 'ai_cache_get réservé au service role');
  perform tests.as_user(a);
  perform tests.ok((select count(*) from public.ai_interactions) = 1, 'A voit ses propres ai_interactions');
  perform tests.as_service();
  perform tests.ok((select count(*) from public.ai_cache) = 1, 'le service role lit ai_cache');
  perform tests.ok(public.ai_cache_get(repeat('a', 64)) = '{"text":"x"}'::jsonb, 'ai_cache_get renvoie la réponse');
  perform tests.ok((select hit_count from public.ai_cache where cache_key = repeat('a', 64)) = 1, 'ai_cache_get incrémente hit_count');
  perform tests.ok(public.ai_cache_get(repeat('b', 64)) is null, 'ai_cache_get : clé inconnue -> null');

  -- ------------------------------------------------------------------ contenu
  perform tests.as_user(a);
  perform tests.ok((select count(*) from public.exercises) > 100, 'un utilisateur authentifié lit les exercices');
  perform tests.ok((select count(*) from public.dictionary_items) > 10, 'un utilisateur authentifié lit le dictionnaire');
  perform tests.throws($q$insert into public.languages (id, code, name, native_name, tts_locale) values ('xx', 'xx', 'X', 'X', 'xx-XX')$q$,
    '42501', 'le contenu est en lecture seule (insert)');
  perform tests.throws($q$update public.exercises set question = 'x'$q$, '42501', 'le contenu est en lecture seule (update)');
  perform tests.throws($q$delete from public.learning_units$q$, '42501', 'le contenu est en lecture seule (delete)');
  perform tests.as_anon();
  perform tests.throws($q$select count(*) from public.exercises$q$, '42501', 'anon ne lit pas le contenu');
  perform tests.throws($q$select count(*) from public.attempts$q$, '42501', 'anon ne lit pas les tentatives');
  perform tests.throws($q$select public.content_manifest('en')$q$, '42501', 'anon ne peut pas appeler content_manifest');
  perform tests.throws($q$select public.sync_pull('en', null)$q$, '42501', 'anon ne peut pas appeler sync_pull');
  perform tests.throws($q$select public.sync_push('{"language_id":"en"}')$q$, '42501', 'anon ne peut pas appeler sync_push');

  -- ------------------------------------------- triggers, contraintes, anti-fraude
  perform tests.as_user(a);
  -- server_updated_at est posé par le serveur, quoi qu'envoie le client.
  insert into public.attempts (id, language_id, exercise_id, unit_ids, exercise_type, result, answered_at, server_updated_at)
    values ('a0000000-0000-4000-8000-0000000000a2', 'en', ex, array[un], 'mcq', 'correct', now(), '2000-01-01');
  select server_updated_at into ts from public.attempts where id = 'a0000000-0000-4000-8000-0000000000a2';
  perform tests.ok(ts > now() - interval '1 minute', 'server_updated_at écrasé par le serveur');

  -- tentatives immuables, sauf résolution d'une tentative pending
  perform tests.throws(format($q$update public.attempts set submitted_answer = 'x' where id = %L$q$, att_a), '42501', 'attempts : submitted_answer immuable');
  perform tests.throws(format($q$update public.attempts set exercise_id = 'en.nope' where id = %L$q$, att_a), '42501', 'attempts : exercise_id immuable');
  update public.attempts set result = 'correct', updated_at = now() + interval '1 minute' where id = att_a;
  get diagnostics n = row_count;
  perform tests.ok(n = 1 and (select result from public.attempts where id = att_a) = 'correct', 'une tentative pending peut être résolue');
  perform tests.throws(format($q$update public.attempts set result = 'incorrect' where id = %L$q$, att_a), '42501', 'une tentative résolue ne change plus');

  -- anti-fraude : validated n'est jamais choisi par le client
  insert into public.learning_sessions (id, language_id, session_type, slot, local_date, status, validated, completed_at)
    values (s_a2, 'en', 'learning', 'afternoon', '2026-10-13', 'completed', true, now());
  select validated into v from public.learning_sessions where id = s_a2;
  perform tests.ok(v = false, 'session completed sans tentatives : validated forcé à false');
  update public.learning_sessions set validated = true where id = s_a2;
  select validated into v from public.learning_sessions where id = s_a2;
  perform tests.ok(v = false, 'le client ne peut pas forcer validated = true');

  insert into public.attempts (id, language_id, exercise_id, session_id, unit_ids, exercise_type, result, answered_at)
    select gen_random_uuid(), 'en', ex, s_a2, array[un], 'mcq', 'correct', now() from generate_series(1, 3);
  select validated into v from public.learning_sessions where id = s_a2;
  perform tests.ok(v = false, '3 tentatives : validated reste false');
  insert into public.attempts (id, language_id, exercise_id, session_id, unit_ids, exercise_type, result, answered_at)
    values (gen_random_uuid(), 'en', ex, s_a2, array[un], 'mcq', 'correct', now());
  select validated into v from public.learning_sessions where id = s_a2;
  perform tests.ok(v = true, '4 tentatives : validated repasse à true');

  insert into public.learning_sessions (id, language_id, session_type, slot, local_date, status)
    values (s_a3, 'en', 'review', 'evening', '2026-10-13', 'completed');
  perform tests.ok((select validated from public.learning_sessions where id = s_a3), 'type hors learning/application/consolidation : toujours validé');

  -- unicité d'un créneau
  perform tests.throws($q$insert into public.learning_sessions (id, language_id, session_type, slot, local_date, status)
    values (gen_random_uuid(), 'en', 'learning', 'morning', '2026-10-13', 'scheduled')$q$, '23505', 'une seule session par utilisateur/langue/jour/créneau');
  insert into public.learning_sessions (id, language_id, session_type, slot, local_date, status)
    values (gen_random_uuid(), 'en', 'extra', null, '2026-10-13', 'scheduled'), (gen_random_uuid(), 'en', 'extra', null, '2026-10-13', 'scheduled');
  perform tests.ok(true, 'sessions sans créneau : plusieurs autorisées');
  perform tests.as_user(b);
  insert into public.learning_sessions (id, language_id, session_type, slot, local_date, status)
    values (gen_random_uuid(), 'en', 'learning', 'morning', '2026-10-13', 'scheduled');
  perform tests.ok(true, 'le même créneau est libre pour un autre utilisateur');

  -- contraintes CHECK / FK
  perform tests.as_user(a);
  perform tests.throws($q$insert into public.learning_sessions (id, language_id, session_type, slot, local_date, status)
    values (gen_random_uuid(), 'en', 'learning', 'night', '2026-10-14', 'scheduled')$q$, '23514', 'slot invalide refusé');
  perform tests.throws($q$insert into public.learning_sessions (id, language_id, session_type, slot, local_date, status)
    values (gen_random_uuid(), 'en', 'learning', 'morning', '2026-10-14', 'bogus')$q$, '23514', 'status invalide refusé');
  perform tests.throws($q$insert into public.learning_sessions (id, language_id, session_type, slot, local_date, status)
    values (gen_random_uuid(), 'en', 'Bad Type', 'morning', '2026-10-14', 'scheduled')$q$, '23514', 'session_type invalide refusé');
  perform tests.throws(format($q$insert into public.attempts (id, language_id, exercise_id, unit_ids, exercise_type, result, answered_at)
    values (gen_random_uuid(), 'en', %L, '{}', 'mcq', 'bogus', now())$q$, ex), '23514', 'result invalide refusé');
  perform tests.throws($q$insert into public.attempts (id, language_id, exercise_id, unit_ids, exercise_type, result, answered_at)
    values (gen_random_uuid(), 'en', 'en.inconnu', '{}', 'mcq', 'correct', now())$q$, '23503', 'exercice inconnu refusé (clé étrangère)');
  perform tests.throws($q$insert into public.memory_states (language_id, learning_unit_id) values ('en', 'en.g.inconnu')$q$, '23503', 'unité inconnue refusée (clé étrangère)');
  perform tests.throws($q$insert into public.user_vocabulary (dictionary_item_id) values ('en.d.inconnu')$q$, '23503', 'mot inconnu refusé (clé étrangère)');
  perform tests.throws($q$update public.daily_schedules set timezone = 'Mars/Olympus'$q$, '22023', 'fuseau horaire invalide refusé');
  perform tests.throws($q$update public.daily_schedules set safety_window_minutes = -1$q$, '23514', 'safety_window_minutes hors bornes refusé');
  update public.daily_schedules set timezone = 'America/Martinique' where true;
  perform tests.ok((select timezone from public.daily_schedules) = 'America/Martinique', 'fuseau IANA valide accepté');

  -- dernière écriture gagne (écritures directes type PostgREST merge-duplicates)
  insert into public.user_languages (language_id, estimated_level, updated_at)
    values ('en', 9, now() - interval '1 day')
    on conflict (user_id, language_id) do update set estimated_level = excluded.estimated_level, updated_at = excluded.updated_at;
  perform tests.ok((select estimated_level from public.user_languages) = 2, 'écriture plus ancienne ignorée (user_languages)');
  insert into public.user_languages (language_id, estimated_level, updated_at)
    values ('en', 9, now() + interval '1 minute')
    on conflict (user_id, language_id) do update set estimated_level = excluded.estimated_level, updated_at = excluded.updated_at;
  perform tests.ok((select estimated_level from public.user_languages) = 9, 'écriture plus récente appliquée (user_languages)');

  -- ------------------------------------------------------------------ nettoyage
  perform tests.as_admin();
  delete from public.ai_cache where cache_key = repeat('a', 64);
  delete from auth.users where id in (a, b);
  perform tests.ok(not exists (select 1 from public.profiles where id in (a, b)), 'nettoyage des utilisateurs de test');
end
$test$;
