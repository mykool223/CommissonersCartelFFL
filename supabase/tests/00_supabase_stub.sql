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
end $$;
