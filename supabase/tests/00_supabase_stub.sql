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
