-- Faux environnement Supabase pour tester les migrations sur un Postgres nu.
-- Reproduit uniquement ce dont les migrations dépendent : rôles, schéma auth
-- (auth.users, auth.uid()), schéma extensions, schéma storage, privilèges par
-- défaut (volontairement larges, comme sur Supabase : les migrations doivent
-- donc révoquer explicitement ce qu'elles ne veulent pas exposer).

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login noinherit;
  end if;
end $$;

grant anon, authenticated, service_role to authenticator;

create schema if not exists extensions;
create schema if not exists auth;
create schema if not exists storage;

grant usage on schema public, extensions, auth to anon, authenticated, service_role;
grant usage on schema storage to anon, authenticated, service_role;

create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  raw_app_meta_data jsonb not null default '{}'::jsonb,
  email_confirmed_at timestamptz,
  last_sign_in_at timestamptz,
  is_anonymous boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Mêmes définitions que GoTrue (lecture des claims posés par PostgREST).
create or replace function auth.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;

grant execute on function auth.uid(), auth.role(), auth.jwt() to anon, authenticated, service_role;
-- GoTrue supprime les utilisateurs avec un rôle qui a ce droit ; on le simule.
grant select, delete on auth.users to service_role;

create table storage.buckets (
  id text primary key,
  name text not null unique,
  owner uuid,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text,
  owner uuid,
  metadata jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table storage.objects enable row level security;
grant select on storage.buckets, storage.objects to anon, authenticated, service_role;

-- Privilèges par défaut de Supabase pour les objets créés par `postgres`.
alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on functions to anon, authenticated, service_role;

-- Utilitaires de test.
create schema if not exists tests;
grant usage on schema tests to public;

create or replace function tests.as_user(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create or replace function tests.as_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('role', 'anon', true);
end $$;

create or replace function tests.as_service() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  perform set_config('role', 'service_role', true);
end $$;

create or replace function tests.as_admin() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end $$;

create or replace function tests.ok(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if p_cond is not true then
    raise exception 'FAIL - %', p_msg;
  end if;
  raise notice 'ok - %', p_msg;
end $$;

-- Exécute une instruction et vérifie qu'elle échoue avec le SQLSTATE attendu.
create or replace function tests.throws(p_sql text, p_sqlstate text, p_msg text) returns void
language plpgsql as $$
declare v_state text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    if v_state = p_sqlstate then
      raise notice 'ok - % (%)', p_msg, v_state;
      return;
    end if;
    raise exception 'FAIL - % : attendu %, obtenu % (%)', p_msg, p_sqlstate, v_state, sqlerrm;
  end;
  raise exception 'FAIL - % : aucune erreur levée (attendu %)', p_msg, p_sqlstate;
end $$;

-- Exécute une requête (une valeur) et renvoie son résultat en jsonb.
create or replace function tests.q(p_sql text) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  execute 'select to_jsonb(t) from (' || p_sql || ') t' into v;
  return v;
end $$;
