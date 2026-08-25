-- Each week's power ranking, kept so the next one can show movement.
--
-- A ranking without arrows is a list. The interesting part is who climbed.
create table public.power_rankings (
    season       int  not null,
    week         int  not null,
    espn_team_id int  not null,
    team_name    text not null,
    -- Best legal lineup on the expert consensus, which is what the coach and
    -- the app both mean by strength.
    score        numeric not null,
    rank         int  not null,
    computed_at  timestamptz not null default now(),

    primary key (season, week, espn_team_id)
);

alter table public.power_rankings enable row level security;

-- Members can read them: unlike the FantasyPros cache, this is our own
-- arithmetic about our own league.
create policy "Members read power rankings" on public.power_rankings
    for select using (auth.uid() is not null);
