-- A confidence pool: pick every NFL game, weight each pick, live with it.
--
-- The weighting is what makes it a game rather than a coin-flip contest.
-- Sixteen games means sixteen down to one, each value used exactly once, so
-- being right about the game you were sure of is worth more than being right
-- about a game nobody could call.

-- The week's fixtures, synced from ESPN's public scoreboard.
create table public.pickem_games (
    season      int  not null,
    week        int  not null,
    -- ESPN's own event id, so a re-sync updates rather than duplicates.
    event_id    text not null,

    home_abbr   text not null,
    home_name   text not null,
    away_abbr   text not null,
    away_name   text not null,

    kickoff_at  timestamptz not null,
    -- Null until the game is over. The abbreviation of whoever won; a tie
    -- leaves it null and the game scores nothing for anybody.
    winner_abbr text,
    final       boolean not null default false,

    updated_at  timestamptz not null default now(),
    primary key (season, week, event_id)
);

create index pickem_games_week_idx on public.pickem_games (season, week, kickoff_at);

alter table public.pickem_games enable row level security;

-- The fixtures are public knowledge; anybody can read them.
create policy "Anyone can read the fixtures" on public.pickem_games
    for select using (true);

-- One pick per person per game.
create table public.pickem_picks (
    user_id     uuid not null references auth.users (id) on delete cascade,
    season      int  not null,
    week        int  not null,
    event_id    text not null,

    -- The abbreviation of the team they think wins.
    chosen_abbr text not null,
    -- How sure they are: 1 up to the number of games that week, each value
    -- used once. Enforced per week below.
    confidence  int  not null check (confidence >= 1),

    updated_at  timestamptz not null default now(),

    primary key (user_id, season, week, event_id),
    foreign key (season, week, event_id)
        references public.pickem_games (season, week, event_id) on delete cascade
);

-- Each weight spent once a week. Two games at sixteen points is not a
-- confidence pool.
create unique index pickem_picks_unique_confidence
    on public.pickem_picks (user_id, season, week, confidence);

alter table public.pickem_picks enable row level security;

-- Everybody's picks are visible once their game has started, and your own
-- always are. Reading somebody else's picks before kickoff would be copying.
create policy "Read your own picks, and everyone's once they are locked"
    on public.pickem_picks
    for select using (
        auth.uid() = user_id
        or exists (
            select 1 from public.pickem_games g
             where g.season = pickem_picks.season
               and g.week = pickem_picks.week
               and g.event_id = pickem_picks.event_id
               and g.kickoff_at <= now()
        )
    );

-- You may set your own picks, and only before that game kicks off.
create policy "Make your own picks before kickoff" on public.pickem_picks
    for insert with check (
        auth.uid() = user_id
        and private.is_member()
        and exists (
            select 1 from public.pickem_games g
             where g.season = pickem_picks.season
               and g.week = pickem_picks.week
               and g.event_id = pickem_picks.event_id
               and g.kickoff_at > now()
        )
    );

create policy "Change your own picks before kickoff" on public.pickem_picks
    for update using (
        auth.uid() = user_id
        and exists (
            select 1 from public.pickem_games g
             where g.season = pickem_picks.season
               and g.week = pickem_picks.week
               and g.event_id = pickem_picks.event_id
               and g.kickoff_at > now()
        )
    ) with check (auth.uid() = user_id);

-- What everyone scored, computed rather than stored: a stored total is a
-- total that can disagree with the picks it came from.
create or replace view public.pickem_standings
with (security_invoker = true) as
    select p.season,
           p.week,
           p.user_id,
           count(*) filter (where g.final and g.winner_abbr = p.chosen_abbr) as correct,
           count(*) filter (where g.final) as decided,
           coalesce(sum(p.confidence)
                    filter (where g.final and g.winner_abbr = p.chosen_abbr), 0) as points
      from public.pickem_picks p
      join public.pickem_games g
        on g.season = p.season and g.week = p.week and g.event_id = p.event_id
     group by p.season, p.week, p.user_id;
