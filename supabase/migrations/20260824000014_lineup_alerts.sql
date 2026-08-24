-- Sunday lineup warnings: "you are starting someone on a bye".
--
-- Recorded so the same warning is not sent twice — the job runs more than once
-- on a Sunday, and being told about the same mistake every half hour is how
-- people turn notifications off.

create table public.lineup_alerts (
    id           uuid primary key default gen_random_uuid(),
    season       int  not null,
    week         int  not null,
    user_id      uuid not null references auth.users (id) on delete cascade,
    espn_team_id int  not null,
    player_id    int  not null,
    reason       text not null,
    sent_at      timestamptz not null default now(),

    -- One warning per player per week, however often the job runs.
    unique (season, week, user_id, player_id)
);

alter table public.lineup_alerts enable row level security;

create policy "Members read their own lineup alerts" on public.lineup_alerts
    for select using (auth.uid() = user_id);

-- Written only by the job, which uses the service role key.

alter table public.notification_preferences
    add column lineup boolean not null default true;
