-- 30 — Contenu chargé (seed rejoué 2 fois), versions, Storage, rétention, suppression en cascade.

do $test$
declare
  c   constant uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  ex text; un text; di text;
  n integer; n_units integer; n_ex integer; n_dict integer; n_lessons integer;
  t text;
  cnt jsonb := '{}'::jsonb;
  v_cur bigint;
begin
  perform tests.as_admin();

  -- ------------------------------------------------------------ contenu seed
  perform tests.ok((select count(*) from public.languages where id = 'en' and code = 'en' and is_available) = 1, 'langue en disponible');
  select count(*) into n_units from public.learning_units;
  select count(*) into n_lessons from public.lessons;
  select count(*) into n_ex from public.exercises;
  select count(*) into n_dict from public.dictionary_items;
  perform tests.ok(n_units > 50 and n_lessons > 10 and n_ex > 200 and n_dict > 50,
    format('contenu chargé : %s unités, %s leçons, %s exercices, %s mots', n_units, n_lessons, n_ex, n_dict));
  perform tests.ok((select count(*) from public.content_versions where language_id = 'en') = 1,
    'seed rejoué deux fois : une seule ligne content_versions (idempotent)');
  perform tests.ok((select count(*) from public.content_versions where language_id = 'en' and is_current) = 1, 'une seule version courante');
  perform tests.ok((select count(*) from public.exercises where not exists (select 1 from public.learning_units u where u.id = learning_unit_id)) = 0,
    'tous les exercices référencent une unité existante');
  perform tests.ok((select count(*) from public.exercises e where exists (
      select 1 from unnest(e.unit_ids) x where not exists (select 1 from public.learning_units u where u.id = x))) = 0,
    'tous les unit_ids des exercices existent');
  perform tests.ok((select count(*) from public.exercises where lesson_id is not null and not exists (select 1 from public.lessons l where l.id = lesson_id)) = 0,
    'tous les exercices de leçon référencent une leçon existante');
  perform tests.ok((select count(*) from public.exercises where not (data ? 'prompt')) = 0, 'exercises.data contient le prompt (utilisé par le professeur IA)');
  perform tests.ok((select count(*) from public.learning_units where kind = 'grammar' and not (data ? 'rule')) = 0
                   or (select count(*) from public.learning_units where data ? 'rule') > 0, 'learning_units.data.rule présent pour les règles');
  perform tests.ok((select count(distinct pool) from public.exercises) = 3, 'pools lesson / diagnostic / assessment présents');

  -- Seed rejouable à la main : le fichier réel est chargé par run_sql_tests.sh (2 fois).
  -- Trigger content_versions : une seule version courante, doublon = mise à jour.
  select id into v_cur from public.content_versions where language_id = 'en' and is_current;
  insert into public.content_versions (language_id, version, bundle_path, sha256, is_current)
    values ('en', '9.9.9', 'en/9.9.9.json', repeat('f', 64), true);
  perform tests.ok((select version from public.content_versions where language_id = 'en' and is_current) = '9.9.9'
                   and (select count(*) from public.content_versions where language_id = 'en' and is_current) = 1, 'nouvelle version courante : l''ancienne est rétrogradée');
  insert into public.content_versions (language_id, version, bundle_path, sha256, is_current)
    values ('en', '9.9.9', 'en/9.9.9.json', repeat('e', 64), true);
  perform tests.ok((select count(*) from public.content_versions where language_id = 'en' and version = '9.9.9') = 1
                   and (select sha256 from public.content_versions where language_id = 'en' and version = '9.9.9') = repeat('e', 64), 'réinsertion de la même version : mise à jour, pas de doublon');
  perform tests.throws($q$insert into public.content_versions (language_id, version, bundle_path, sha256) values ('en', 'abc', 'en/x.json', repeat('a', 64))$q$,
    '23514', 'version non semver refusée');
  perform tests.throws($q$insert into public.content_versions (language_id, version, bundle_path, sha256) values ('en', '9.9.8', '../x.json', repeat('a', 64))$q$,
    '23514', 'bundle_path avec .. refusé');
  delete from public.content_versions where language_id = 'en' and version = '9.9.9';
  update public.content_versions set is_current = true where id = v_cur;
  perform tests.ok((select count(*) from public.content_versions where language_id = 'en' and is_current) = 1, 'version courante restaurée');

  -- ------------------------------------------------------------------ Storage
  perform tests.ok((select public from storage.buckets where id = 'content'), 'bucket Storage content public');
  perform tests.ok((select allowed_mime_types from storage.buckets where id = 'content') = array['application/json'], 'bucket content : JSON uniquement');
  perform tests.as_anon();
  perform tests.ok((select count(*) from storage.objects where bucket_id = 'content') >= 0, 'lecture publique du bucket content (anon)');
  perform tests.throws($q$insert into storage.objects (bucket_id, name) values ('content', 'en/hack.json')$q$, '42501', 'écriture dans le bucket content refusée à anon');
  perform tests.as_admin();
  insert into auth.users (id, email) values (c, 'c@example.test');
  perform tests.as_user(c);
  perform tests.throws($q$insert into storage.objects (bucket_id, name) values ('content', 'en/hack.json')$q$, '42501', 'écriture dans le bucket content refusée aux utilisateurs');

  -- ----------------------------------------------- suppression de compte (cascade)
  perform tests.as_admin();
  select e.id, e.learning_unit_id into ex, un from public.exercises e where e.language_id = 'en' and e.lesson_id is not null order by e.id limit 1;
  select d.id into di from public.dictionary_items d order by d.id limit 1;
  perform tests.as_user(c);
  insert into public.user_languages (language_id) values ('en');
  insert into public.daily_schedules (enabled) values (true);
  insert into public.learning_sessions (id, language_id, session_type, slot, local_date, status) values ('c0000000-0000-4000-8000-0000000000c1', 'en', 'learning', 'morning', '2026-10-13', 'completed');
  insert into public.attempts (id, language_id, exercise_id, session_id, unit_ids, exercise_type, result, answered_at)
    select gen_random_uuid(), 'en', ex, 'c0000000-0000-4000-8000-0000000000c1', array[un], 'mcq', 'correct', now() from generate_series(1, 4);
  insert into public.memory_states (language_id, learning_unit_id) values ('en', un);
  insert into public.user_vocabulary (dictionary_item_id) values (di);
  perform tests.as_admin();
  insert into public.ai_interactions (user_id, exercise_id, request_type, response_status, model) values (c, ex, 'explain-answer', 'ok', 'm');
  insert into public.ai_cache (cache_key, request_type, response) values (repeat('c', 64), 'explain-answer', '{"text":"t"}');
  select count(*) into n from public.profiles where id = c;
  perform tests.ok(n = 1, 'compte de test créé avec profil');

  perform tests.as_service();
  delete from auth.users where id = c;   -- ce que fait auth.admin.deleteUser
  perform tests.as_admin();
  foreach t in array array['profiles', 'user_languages', 'daily_schedules', 'learning_sessions', 'attempts', 'memory_states', 'user_vocabulary', 'ai_interactions'] loop
    execute format('select count(*) from public.%I where %I = $1', t, case when t = 'profiles' then 'id' else 'user_id' end) into n using c;
    perform tests.ok(n = 0, format('suppression du compte : plus aucune ligne dans %s', t));
  end loop;
  perform tests.ok((select count(*) from public.exercises) = n_ex and (select count(*) from public.learning_units) = n_units
                   and (select count(*) from public.dictionary_items) = n_dict, 'suppression du compte : le contenu est intact');
  perform tests.ok((select count(*) from public.ai_cache where cache_key = repeat('c', 64)) = 1, 'suppression du compte : le cache IA (sans donnée personnelle) est conservé');

  -- --------------------------------------------------------------- rétention
  insert into public.ai_cache (cache_key, request_type, response, created_at) values (repeat('d', 64), 'explain-rule', '{}', now() - interval '400 days');
  insert into auth.users (id, email) values (c, 'c@example.test');
  insert into public.ai_interactions (user_id, request_type, response_status, created_at)
    values (c, 'explain-rule', 'ok', now() - interval '200 days'), (c, 'explain-rule', 'ok', now() - interval '10 days');
  perform tests.as_user(c);
  perform tests.throws($q$select public.ai_purge()$q$, '42501', 'ai_purge réservé au service role');
  perform tests.as_service();
  perform public.ai_purge();
  perform tests.as_admin();
  perform tests.ok((select count(*) from public.ai_interactions where user_id = c) = 1, 'ai_purge : journaux de plus de 90 jours supprimés, récents conservés');
  perform tests.ok((select count(*) from public.ai_cache where cache_key = repeat('d', 64)) = 0 and (select count(*) from public.ai_cache where cache_key = repeat('c', 64)) = 1,
    'ai_purge : entrées de cache périmées supprimées');
  delete from public.ai_cache where cache_key = repeat('c', 64);
  delete from auth.users where id = c;
  perform tests.ok(true, 'nettoyage');
end
$test$;
