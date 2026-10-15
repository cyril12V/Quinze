-- 07 — Fonctions d'appui des Edge Functions IA, rétention, bucket Storage `content`.

-- ---------------------------------------------------------------------------
-- Cache IA : lecture + compteur de hits en un aller-retour (service role seulement).
-- ---------------------------------------------------------------------------
create or replace function public.ai_cache_get(p_cache_key text)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  with hit as (
    update public.ai_cache
       set hit_count = hit_count + 1, last_hit_at = now()
     where cache_key = p_cache_key
    returning response
  )
  select response from hit
$$;

-- ---------------------------------------------------------------------------
-- Rétention : purge des journaux IA et des entrées de cache peu utilisées.
-- À planifier (pg_cron / tâche externe) : voir docs/03-base-de-donnees.md.
-- ---------------------------------------------------------------------------
create or replace function public.ai_purge(p_interactions_days integer default 90, p_cache_days integer default 180)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_inter integer;
  v_cache integer;
begin
  delete from public.ai_interactions where created_at < now() - make_interval(days => greatest(p_interactions_days, 62));
  get diagnostics v_inter = row_count;
  delete from public.ai_cache where coalesce(last_hit_at, created_at) < now() - make_interval(days => greatest(p_cache_days, 1));
  get diagnostics v_cache = row_count;
  return jsonb_build_object('ai_interactions_deleted', v_inter, 'ai_cache_deleted', v_cache);
end $$;

-- Ces fonctions ne doivent jamais être appelables par les clients.
revoke execute on function public.ai_cache_get(text)           from public, anon, authenticated;
revoke execute on function public.ai_purge(integer, integer)   from public, anon, authenticated;
grant  execute on function public.ai_cache_get(text)           to service_role;
grant  execute on function public.ai_purge(integer, integer)   to service_role;

-- ---------------------------------------------------------------------------
-- Storage : bucket public `content` (bundles JSON de contenu, lecture publique,
-- écriture réservée au service role / au tableau de bord).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('content', 'content', true, 20971520, array['application/json'])
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "content bucket is publicly readable" on storage.objects;
create policy "content bucket is publicly readable"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'content');
-- Aucune policy d'écriture : seuls service_role / postgres peuvent déposer un bundle.
