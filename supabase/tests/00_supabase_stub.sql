-- Minimal stand-in for the parts of Supabase this schema depends on.
-- Supabase provides these; a bare Postgres does not.
create schema if not exists auth;

create table auth.users (
    id                 uuid primary key default gen_random_uuid(),
    email              text,
    raw_user_meta_data jsonb default '{}'::jsonb
);

-- Impersonation hook: tests set request.jwt.claim.sub to act as a user.
create or replace function auth.uid() returns uuid
language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- PostgREST's roles.
do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end $$;

-- Supabase grants EXECUTE on every function created in `public` to these roles
-- by default. This is NOT standard Postgres behaviour, and leaving it out of
-- the stub hides a whole class of bug: a `revoke ... from public` looks
-- effective locally while `anon` keeps an explicit grant in production.
alter default privileges in schema public
    grant execute on functions to anon, authenticated, service_role;

-- Vault, where push credentials live in production. Tests leave it empty, so
-- private.notify_push takes its "not configured yet" path and stays silent.
create schema if not exists vault;

create table if not exists vault.decrypted_secrets (
    name             text primary key,
    decrypted_secret text
);

-- pg_net stand-in. Records calls instead of making them, so a test can assert
-- that an insert queued exactly one push without touching the network.
create schema if not exists net;

create table if not exists net.sent (
    id      bigserial primary key,
    url     text,
    headers jsonb,
    body    jsonb
);

create or replace function net.http_post(
    url text,
    body jsonb default '{}'::jsonb,
    params jsonb default '{}'::jsonb,
    headers jsonb default '{}'::jsonb,
    timeout_milliseconds int default 5000
) returns bigint
language sql as $$
    insert into net.sent (url, headers, body) values (url, headers, body)
    returning id;
$$;

-- Assertions read net.sent while impersonating a member, so the test roles
-- need to see the recorded calls. Production grants nothing of the sort:
-- there, only the security-definer function reaches pg_net.
grant usage on schema net to anon, authenticated, service_role;
grant select on net.sent to anon, authenticated, service_role;
