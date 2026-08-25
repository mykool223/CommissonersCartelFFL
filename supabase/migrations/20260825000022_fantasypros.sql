-- A local cache of FantasyPros consensus data.
--
-- Their licence allows one call per second and 100 calls per day, total, and
-- asks that clients cache rather than poll. That budget rules out fetching
-- during a coach question: a dozen members asking would exhaust a day's calls
-- before lunch. So a nightly job fills these tables and everything else reads
-- from here, which is also faster and works when their API is down.
--
-- Two things are deliberately absent. The licence does not grant use of
-- historical player statistics or player image URLs, so neither is requested
-- nor stored, and the sync deletes rows for weeks that have passed.

-- The join between their world and ESPN's. Their players endpoint can return
-- an ESPN id per player, which beats matching on names — names disagree about
-- punctuation, suffixes and, for defences, almost everything.
create table public.fantasypros_players (
    fp_id      int primary key,
    espn_id    int unique,
    name       text not null,
    team       text,
    position   text,
    updated_at timestamptz not null default now()
);

create index fantasypros_players_espn_idx on public.fantasypros_players (espn_id)
    where espn_id is not null;

-- Consensus rankings: where dozens of experts collectively put a player.
-- `kind` is 'weekly' for this week's start/sit or 'ros' for rest of season.
create table public.fantasypros_rankings (
    season     int  not null,
    week       int  not null,
    kind       text not null check (kind in ('weekly', 'ros')),
    fp_id      int  not null references public.fantasypros_players (fp_id) on delete cascade,

    rank_ecr   int,
    -- "RB7" — more useful than an overall rank when filling one slot.
    pos_rank   text,
    -- Players within a tier are close enough that the order is noise.
    tier       int,
    -- How far the experts disagree, and which way the rank is moving.
    rank_min   int,
    rank_max   int,
    rank_std   numeric,
    ecr_delta  numeric,

    updated_at timestamptz not null default now(),
    primary key (season, week, kind, fp_id)
);

-- Their projected points, kept beside ESPN's rather than replacing them: the
-- league reads ESPN's numbers in ESPN's app, so those stay the arithmetic that
-- the app quotes. Disagreement between the two is itself worth surfacing.
create table public.fantasypros_projections (
    season     int not null,
    week       int not null,
    fp_id      int not null references public.fantasypros_players (fp_id) on delete cascade,
    points_ppr numeric,
    updated_at timestamptz not null default now(),
    primary key (season, week, fp_id)
);

-- Injuries, with the practice-report probability of playing. ESPN says
-- "Questionable" and stops; this says how likely they are to take the field.
create table public.fantasypros_injuries (
    season       int  not null,
    week         int  not null,
    fp_id        int  not null references public.fantasypros_players (fp_id) on delete cascade,
    status       text,
    probability  numeric,
    injury_type  text,
    comment      text,
    updated_at   timestamptz not null default now(),
    primary key (season, week, fp_id)
);

alter table public.fantasypros_players     enable row level security;
alter table public.fantasypros_rankings    enable row level security;
alter table public.fantasypros_projections enable row level security;
alter table public.fantasypros_injuries    enable row level security;

-- No member-facing policies. The data reaches members only through the coach,
-- which reads with the service role and attributes it. Licensed for personal
-- use, so it is not republished as an open feed.

-- A record of what the sync spent, so the daily budget can be enforced against
-- something real rather than assumed. One row per day.
create table public.fantasypros_usage (
    day        date primary key default current_date,
    calls      int  not null default 0,
    updated_at timestamptz not null default now()
);

alter table public.fantasypros_usage enable row level security;
