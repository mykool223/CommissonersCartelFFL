-- Adds, drops, waiver claims and completed trades, pulled from ESPN.
--
-- Stored rather than fetched live because ESPN returns a transaction as team
-- ids and player ids with no names, and resolving those costs a second request
-- per batch. Doing that on every app launch, on every phone, to render a list
-- that changes a few times a week would be absurd.

create table public.league_activity (
    id                  uuid primary key default gen_random_uuid(),
    season              int  not null check (season between 2000 and 2100),
    -- ESPN's own id for the transaction, so re-running the ingest is a no-op.
    espn_transaction_id text not null,
    kind                text not null check (kind in ('add', 'drop', 'waiver', 'trade')),
    espn_team_id        int,
    headline            text not null check (length(headline) between 1 and 200),
    detail              text check (length(detail) <= 400),
    occurred_at         timestamptz not null,
    created_at          timestamptz not null default now(),

    unique (season, espn_transaction_id)
);

create index league_activity_recent_idx
    on public.league_activity (season, occurred_at desc);

alter table public.league_activity enable row level security;

-- Readable signed out, like league news: it is the league's own record of
-- itself, and there is nothing private in it.
create policy "Anyone can read league activity" on public.league_activity
    for select using (true);

-- Written only by the ingest job, which uses the service role key. No policy
-- grants insert, so nothing else can write.

-- Members can mute it independently of the other kinds; roster churn is
-- noisier than league news and some people will not want it.
alter table public.notification_preferences
    add column activity boolean not null default true;

create or replace function private.on_league_activity_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform private.notify_push(
        'activity',
        'League activity',
        private.push_preview(new.headline),
        -- No author to exclude: this comes from ESPN, not from a member.
        null
    );
    return null;
end;
$$;

create trigger league_activity_notify
    after insert on public.league_activity
    for each row execute function private.on_league_activity_insert();
