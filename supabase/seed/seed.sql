-- supabase/seed/seed.sql — point d'entrée documentaire du chargement du contenu.
--
-- Le contenu pédagogique (langues, unités, leçons, exercices, dictionnaire, version
-- courante) est dans un fichier GÉNÉRÉ, rejouable et idempotent (upserts) :
--
--     supabase/seed/content_en.sql     <- tools/build_content.py (ne pas éditer à la main)
--
-- Régénération (depuis la racine du dépôt) :
--
--     python3 tools/build_content.py            # écrit Content/build/en.json + supabase/seed/content_en.sql
--
-- Chargement :
--
--   * Local (supabase start / supabase db reset) : config.toml -> [db.seed].sql_paths
--     charge automatiquement content_en.sql PUIS ce fichier.
--   * Projet hébergé (le CLI ne rejoue pas les seeds sur `db push`) :
--
--         psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/content_en.sql
--         psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/seed.sql   # vérification
--
--     (SUPABASE_DB_URL = chaîne de connexion « Session pooler » ou directe, tableau de bord
--     > Project Settings > Database. Le rôle postgres contourne la RLS.)
--     Alternative : coller content_en.sql dans le SQL Editor du tableau de bord.
--
-- À chaque nouvelle version du contenu :
--   1. Régénérer (ci-dessus) -> content_en.sql + Content/build/en.json (nouveau contentVersion).
--   2. Déposer Content/build/en.json dans Storage : bucket `content`, chemin `en/<version>.json`.
--   3. Charger content_en.sql : il passe l'ancienne version à is_current = false et enregistre la
--      nouvelle (bundle_path + sha256). Les clients voient la nouvelle version via
--      content_manifest('en'). Les identifiants d'exercices/unités sont stables : les données
--      utilisateur déjà synchronisées restent valides.
--   Les éléments retirés d'une version doivent être marqués `deprecated` (jamais supprimés), car
--   attempts / memory_states / user_vocabulary les référencent.
--
-- Ce fichier ne fait que VÉRIFIER (il n'écrit rien) et affiche un résumé.

do $$
declare
  v_langs   integer;
  v_units   integer;
  v_lessons integer;
  v_ex      integer;
  v_dict    integer;
  v_current record;
begin
  select count(*) into v_langs   from public.languages where is_available;
  select count(*) into v_units   from public.learning_units;
  select count(*) into v_lessons from public.lessons;
  select count(*) into v_ex      from public.exercises;
  select count(*) into v_dict    from public.dictionary_items;

  raise notice 'contenu : % langue(s), % unités, % leçons, % exercices, % mots du dictionnaire',
    v_langs, v_units, v_lessons, v_ex, v_dict;

  if v_langs = 0 or v_units = 0 or v_ex = 0 then
    raise warning 'le contenu n''est pas chargé : exécuter supabase/seed/content_en.sql';
  end if;

  for v_current in
    select language_id, version, bundle_path, left(sha256, 12) as sha
      from public.content_versions where is_current order by language_id
  loop
    raise notice 'version courante % : % (%, sha256 %…)',
      v_current.language_id, v_current.version, v_current.bundle_path, v_current.sha;
  end loop;

  -- Bundle JSON correspondant dans Storage (déposé séparément) : informatif.
  if not exists (select 1 from storage.buckets where id = 'content' and public) then
    raise warning 'bucket Storage public `content` absent : appliquer les migrations';
  end if;
end $$;
