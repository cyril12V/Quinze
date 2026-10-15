-- 01 — Extensions, schéma privé et fonctions utilitaires.
--
-- Le schéma `private` n'est PAS exposé par PostgREST (config.toml : api.schemas
-- = public + graphql_public). Il contient les fonctions-triggers et les petits
-- utilitaires purs appelés par les RPC. `authenticated` n'y a que le droit
-- d'USAGE + EXECUTE sur les utilitaires (les RPC s'exécutent en SECURITY INVOKER).

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- ISO 8601 UTC à la milliseconde (« 2026-10-13T07:12:44.120Z »), tronquée (jamais
-- arrondie au-dessus) : un curseur tronqué ne peut que redonner une ligne en trop.
create or replace function private.iso(p_ts timestamptz)
returns text
language sql
stable
strict
parallel safe
set search_path = ''
as $$
  select to_char(p_ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
$$;

-- Conversions tolérantes : renvoient NULL au lieu de lever une exception, pour que
-- sync_push puisse compter une ligne mal formée dans `rejected` sans faire échouer
-- toute la synchronisation.
create or replace function private.try_uuid(p_text text)
returns uuid
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
begin
  return p_text::uuid;
exception when others then
  return null;
end $$;

create or replace function private.try_timestamptz(p_text text)
returns timestamptz
language plpgsql
stable
parallel safe
set search_path = ''
as $$
begin
  if p_text is null or p_text = '' then return null; end if;
  return p_text::timestamptz;
exception when others then
  return null;
end $$;

create or replace function private.try_date(p_text text)
returns date
language plpgsql
stable
parallel safe
set search_path = ''
as $$
begin
  if p_text is null or p_text = '' then return null; end if;
  return p_text::date;
exception when others then
  return null;
end $$;

create or replace function private.try_int(p_text text)
returns integer
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
begin
  if p_text is null or p_text = '' then return null; end if;
  return p_text::numeric::integer;
exception when others then
  return null;
end $$;

create or replace function private.try_float(p_text text)
returns double precision
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
declare v double precision;
begin
  if p_text is null or p_text = '' then return null; end if;
  v := p_text::double precision;
  if v = 'NaN'::double precision or v in ('Infinity'::double precision, '-Infinity'::double precision) then
    return null;
  end if;
  return v;
exception when others then
  return null;
end $$;

create or replace function private.try_bool(p_text text)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
begin
  if p_text is null or p_text = '' then return null; end if;
  return p_text::boolean;
exception when others then
  return null;
end $$;

-- Tableau JSON (ou tableau vide si absent / null / autre type).
create or replace function private.json_array(p_json jsonb)
returns jsonb
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case when jsonb_typeof(p_json) = 'array' then p_json else '[]'::jsonb end
$$;

create or replace function private.jsonb_text_array(p_json jsonb)
returns text[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(
    array(select jsonb_array_elements_text(private.json_array(p_json))),
    '{}'::text[])
$$;

create or replace function private.jsonb_bool_array(p_json jsonb)
returns boolean[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(
    array(
      select b from (
        select private.try_bool(x) as b
        from jsonb_array_elements_text(private.json_array(p_json)) as t(x)
      ) q where b is not null
    ),
    '{}'::boolean[])
$$;

grant execute on all functions in schema private to authenticated, service_role;
revoke execute on all functions in schema private from anon, public;
