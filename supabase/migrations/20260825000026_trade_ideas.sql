-- Trades that would genuinely improve both teams.
--
-- Kept rather than pushed straight out, so the same idea is not suggested
-- every night until somebody acts on it, and so a manager can be shown the
-- ideas involving their own roster whenever they open the app.
create table public.trade_ideas (
    id            uuid primary key default gen_random_uuid(),
    season        int  not null,
    week          int  not null,

    team_a        int  not null,
    team_a_name   text not null,
    team_b        int  not null,
    team_b_name   text not null,

    -- Who moves which way, as names, since that is what a manager reads.
    a_sends       text not null,
    b_sends       text not null,

    -- What each side's best lineup becomes. Both must improve, or it is not
    -- a trade worth proposing to anybody.
    a_gain        numeric not null,
    b_gain        numeric not null,

    found_at      timestamptz not null default now(),

    unique (season, week, team_a, team_b, a_sends, b_sends)
);

alter table public.trade_ideas enable row level security;

-- Anybody signed in can read them. Rosters are public to the league and so is
-- the arithmetic; hiding one manager's ideas from another would only mean the
-- ideas arrived by group chat instead.
create policy "Members read trade ideas" on public.trade_ideas
    for select using (auth.uid() is not null);
