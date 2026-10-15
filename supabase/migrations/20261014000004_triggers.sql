-- 04 — Triggers : profil à l'inscription, horodatages, curseur de sync, anti-fraude.
--
-- Principe de synchronisation :
--   * updated_at (horloge du client) sert à départager deux versions d'une même ligne
--     (« dernière écriture gagne ») : un UPDATE dont updated_at est plus ANCIEN que
--     celui de la ligne en base est ignoré silencieusement (le trigger renvoie NULL).
--   * server_updated_at est TOUJOURS posé par le serveur (clock_timestamp() au moment
--     de l'écriture, la valeur envoyée par le client est écrasée) : c'est le curseur de
--     sync_pull, indépendant des horloges des iPhone.

-- ---------------------------------------------------------------------------
-- Profil créé à l'inscription (et recopie de l'e-mail s'il change).
-- ---------------------------------------------------------------------------
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    nullif(left(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name', '')), 80), '')
  )
  on conflict (id) do nothing;
  return new;
end $$;

create or replace function private.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set email = new.email where id = new.id and email is distinct from new.email;
  return new;
end $$;

revoke execute on function private.handle_new_user(), private.handle_user_email_change() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row when (old.email is distinct from new.email)
  execute function private.handle_user_email_change();

-- Comptes déjà existants au moment de la migration.
insert into public.profiles (id, email)
select u.id, u.email from auth.users u
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- profiles : updated_at posé par le serveur.
-- ---------------------------------------------------------------------------
create or replace function private.tg_profiles_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.id := old.id;
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_touch
  before update on public.profiles
  for each row execute function private.tg_profiles_touch();

-- ---------------------------------------------------------------------------
-- Tables synchronisées « simples » : dernière écriture gagne + server_updated_at.
-- (user_languages, daily_schedules, memory_states, user_vocabulary)
-- ---------------------------------------------------------------------------
create or replace function private.tg_sync_lww()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.user_id := old.user_id;
    new.updated_at := coalesce(new.updated_at, old.updated_at);
    if new.updated_at < old.updated_at then
      return null;  -- version plus ancienne que celle du serveur : ignorée
    end if;
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end $$;

create trigger user_languages_sync   before insert or update on public.user_languages
  for each row execute function private.tg_sync_lww();
create trigger daily_schedules_sync  before insert or update on public.daily_schedules
  for each row execute function private.tg_sync_lww();
create trigger memory_states_sync    before insert or update on public.memory_states
  for each row execute function private.tg_sync_lww();
create trigger user_vocabulary_sync  before insert or update on public.user_vocabulary
  for each row execute function private.tg_sync_lww();

-- Fuseau horaire IANA valide (le client planifie les créneaux dans ce fuseau).
create or replace function private.tg_schedule_validate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.timezone is distinct from old.timezone then
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = new.timezone) then
      raise exception 'invalid time zone: %', new.timezone using errcode = '22023';
    end if;
  end if;
  return new;
end $$;

create trigger daily_schedules_validate
  before insert or update on public.daily_schedules
  for each row execute function private.tg_schedule_validate();

-- ---------------------------------------------------------------------------
-- Anti-fraude : `validated` est calculé par le serveur.
-- Une session learning/application/consolidation « completed » avec moins de
-- 4 tentatives associées reste enregistrée mais validated = false.
-- ---------------------------------------------------------------------------
create or replace function private.session_is_valid(p_id uuid, p_user_id uuid, p_type text, p_status text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when p_status = 'completed' and p_type in ('learning', 'application', 'consolidation')
      then (select count(*) from public.attempts a where a.session_id = p_id and a.user_id = p_user_id) >= 4
    else true
  end
$$;
grant execute on function private.session_is_valid(uuid, uuid, text, text) to authenticated, service_role;

create or replace function private.tg_sessions_before()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.user_id := old.user_id;
    new.language_id := old.language_id;
    new.updated_at := coalesce(new.updated_at, old.updated_at);
    if new.updated_at < old.updated_at then
      return null;
    end if;
  end if;
  new.server_updated_at := clock_timestamp();
  new.validated := private.session_is_valid(new.id, new.user_id, new.session_type, new.status);
  return new;
end $$;

create trigger learning_sessions_before
  before insert or update on public.learning_sessions
  for each row execute function private.tg_sessions_before();

-- ---------------------------------------------------------------------------
-- attempts : immuables (sauf résolution d'une tentative pending).
-- ---------------------------------------------------------------------------
create or replace function private.tg_attempts_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if (new.id, new.user_id, new.language_id, new.exercise_id, new.unit_ids, new.exercise_type,
        new.presentation, new.submitted_answer, new.hint_used, new.is_remediation,
        new.duration_ms, new.answered_at)
       is distinct from
       (old.id, old.user_id, old.language_id, old.exercise_id, old.unit_ids, old.exercise_type,
        old.presentation, old.submitted_answer, old.hint_used, old.is_remediation,
        old.duration_ms, old.answered_at) then
      raise exception 'attempts are immutable (only result/error_category of a pending attempt can change)'
        using errcode = '42501';
    end if;
    if new.session_id is distinct from old.session_id and old.session_id is not null then
      raise exception 'attempts.session_id is immutable once set' using errcode = '42501';
    end if;
    if (new.result, new.error_category) is distinct from (old.result, old.error_category)
       and old.result <> 'pending' then
      raise exception 'only a pending attempt can be resolved' using errcode = '42501';
    end if;
    new.updated_at := coalesce(new.updated_at, old.updated_at);
    if new.updated_at < old.updated_at then
      return null;
    end if;
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end $$;

create trigger attempts_guard
  before insert or update on public.attempts
  for each row execute function private.tg_attempts_guard();

-- Après l'arrivée de tentatives (même lot que la session ou plus tard) : recalcul de
-- `validated` des sessions concernées (un seul UPDATE par instruction, pas par ligne).
create or replace function private.tg_attempts_refresh_sessions()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.learning_sessions s
     set validated = private.session_is_valid(s.id, s.user_id, s.session_type, s.status)
   where s.id in (select n.session_id from new_rows n where n.session_id is not null)
     and s.validated is distinct from private.session_is_valid(s.id, s.user_id, s.session_type, s.status);
  return null;
end $$;

create trigger attempts_refresh_sessions_ins
  after insert on public.attempts
  referencing new table as new_rows
  for each statement execute function private.tg_attempts_refresh_sessions();

create trigger attempts_refresh_sessions_upd
  after update on public.attempts
  referencing new table as new_rows
  for each statement execute function private.tg_attempts_refresh_sessions();
