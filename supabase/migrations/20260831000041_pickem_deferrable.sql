-- Check the weights at the end of the transaction, not row by row.
--
-- Swapping two games' weights is the ordinary way to reorder a board, and it
-- passes through a moment where both hold the same number. A unique index is
-- checked as each row lands, so the swap was rejected — "couldn't save that
-- pick" — even though the set being saved was perfectly valid.
--
-- A deferrable constraint is checked when the transaction commits, by which
-- point the swap is complete. PostgREST runs each request in one transaction,
-- so a whole board arrives as a single set.
--
-- A unique *index* cannot be deferred; this has to be a constraint.
drop index if exists public.pickem_picks_unique_confidence;

alter table public.pickem_picks
    add constraint pickem_picks_unique_confidence
    unique (user_id, season, week, confidence)
    deferrable initially deferred;
