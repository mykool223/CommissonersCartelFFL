-- Rest-of-season projections, which are the right currency for a trade.
--
-- Weekly points answer "who do I start on Sunday". A trade is about the rest
-- of the year, and a player worth 14 points this week against a soft defence
-- may be worth far less over sixteen. Kept in its own table rather than as
-- week 0 of the weekly one, so the purge of played weeks cannot take it.
create table public.fantasypros_ros_projections (
    season     int not null,
    fp_id      int not null references public.fantasypros_players (fp_id) on delete cascade,
    points_ppr numeric,
    updated_at timestamptz not null default now(),
    primary key (season, fp_id)
);

alter table public.fantasypros_ros_projections enable row level security;
