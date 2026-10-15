-- 05 — Row Level Security et privilèges.
--
-- Supabase accorde par défaut tous les droits à anon/authenticated sur les nouvelles
-- tables : on révoque tout puis on accorde le strict nécessaire. RLS est activé sur
-- TOUTES les tables de `public` ; service_role contourne RLS (Edge Functions, seed).

-- ---------------------------------------------------------------------------
-- Contenu : lecture seule pour les utilisateurs authentifiés (pas pour anon).
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['languages', 'content_versions', 'learning_units', 'lessons', 'exercises', 'dictionary_items']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Tables utilisateur : chaque utilisateur ne voit / n'écrit que ses lignes.
-- ---------------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.user_languages    enable row level security;
alter table public.daily_schedules   enable row level security;
alter table public.learning_sessions enable row level security;
alter table public.attempts          enable row level security;
alter table public.memory_states     enable row level security;
alter table public.user_vocabulary   enable row level security;
alter table public.ai_interactions   enable row level security;
alter table public.ai_cache          enable row level security;

revoke all on public.profiles, public.user_languages, public.daily_schedules, public.learning_sessions,
              public.attempts, public.memory_states, public.user_vocabulary,
              public.ai_interactions, public.ai_cache
  from anon, authenticated;

-- profiles : lecture + mise à jour de 3 colonnes (ni insertion — faite par trigger —,
-- ni suppression — faite par la suppression du compte —, ni changement d'e-mail).
grant select on public.profiles to authenticated;
grant update (display_name, pedagogical_prefs, notification_prefs) on public.profiles to authenticated;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Tables synchronisées : CRUD sur ses propres lignes.
do $$
declare t text;
begin
  foreach t in array array['user_languages', 'daily_schedules', 'learning_sessions', 'attempts', 'memory_states', 'user_vocabulary']
  loop
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using (user_id = (select auth.uid()))', t || '_select', t);
    execute format('create policy %I on public.%I for delete to authenticated using (user_id = (select auth.uid()))', t || '_delete', t);
    if t <> 'attempts' then
      execute format('create policy %I on public.%I for insert to authenticated with check (user_id = (select auth.uid()))', t || '_insert', t);
      execute format('create policy %I on public.%I for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t || '_update', t);
    end if;
  end loop;
end $$;

-- attempts : en plus, la session référencée doit appartenir à l'utilisateur
-- (la sous-requête est elle-même filtrée par la RLS de learning_sessions).
create policy attempts_insert on public.attempts for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (session_id is null
         or exists (select 1 from public.learning_sessions s where s.id = session_id and s.user_id = (select auth.uid())))
  );
create policy attempts_update on public.attempts for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (session_id is null
         or exists (select 1 from public.learning_sessions s where s.id = session_id and s.user_id = (select auth.uid())))
  );

-- ai_interactions : lecture de ses propres lignes ; écriture réservée au service role.
grant select on public.ai_interactions to authenticated;
create policy ai_interactions_select on public.ai_interactions for select to authenticated
  using (user_id = (select auth.uid()));

-- ai_cache : service role uniquement (RLS activée, aucune policy, aucun privilège).
-- (volontairement aucune policy pour anon/authenticated)

-- Les séquences (content_versions.id) n'ont pas à être touchées par les clients.
revoke all on all sequences in schema public from anon, authenticated;
