-- Where a ranking came from.
--
-- FantasyPros' league analyzer grades whole rosters using a value model their
-- public API does not expose — three attempts to reproduce its ordering from
-- the draft rankings were displaced by forty places across twelve teams, which
-- is barely better than shuffling. So the commissioner reads it off their site
-- and it is stored here verbatim.
--
-- The job that solves each team's best lineup still writes its own rows,
-- marked 'computed', so the two never overwrite each other. They measure
-- different things and both are worth keeping.
alter table public.power_rankings
    add column source text not null default 'fantasypros'
        check (source in ('fantasypros', 'computed')),
    -- Their analyzer scores out of 100. Ours is projected points. The unit
    -- belongs with the number.
    add column unit text;

-- One ranking per source per week, rather than per week.
alter table public.power_rankings
    drop constraint power_rankings_pkey;

alter table public.power_rankings
    add primary key (season, week, source, espn_team_id);
