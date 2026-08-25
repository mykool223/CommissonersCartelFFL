-- How widely a player is rostered elsewhere.
--
-- A player owned in half the leagues on ESPN who is still free in ours is the
-- clearest waiver signal there is: somebody else's league has already worked
-- out that he is worth having.
--
-- This arrives inside the consensus rankings response we already fetch, so it
-- costs no extra calls against the daily allowance.
alter table public.fantasypros_rankings
    add column owned_avg   numeric,
    add column owned_espn  numeric,
    add column owned_yahoo numeric,
    -- Bye weeks come along in the same response and are worth having for
    -- planning further out than Sunday.
    add column bye_week    int;
