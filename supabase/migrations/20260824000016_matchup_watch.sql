-- Remembers who was leading each fixture, so a change can be noticed.
--
-- Without this the live job would either say nothing or say the same thing
-- every fifteen minutes. It stores the last leader it told people about, and
-- pushes only when that changes.

create table public.matchup_watch (
    season         int not null,
    week           int not null,
    home_team_id   int not null,
    away_team_id   int not null,
    leader_team_id int,
    home_points    numeric(7,2) not null default 0,
    away_points    numeric(7,2) not null default 0,
    is_final       boolean not null default false,
    updated_at     timestamptz not null default now(),

    primary key (season, week, home_team_id, away_team_id)
);

alter table public.matchup_watch enable row level security;

-- Nothing in the apps reads this; it is the job's own memory. No select policy
-- means the anon key sees nothing, which is correct.

alter table public.notification_preferences
    add column matchups boolean not null default true;
