-- Preseason draft rankings, which are how a whole roster gets valued.
--
-- Weekly rankings answer "who do I start on Sunday" and rest-of-season answers
-- "who is worth more from here". Neither answers "whose team is best", which
-- is what a power ranking is for — and it is what FantasyPros' own league
-- analyzer scores rosters on.
alter table public.fantasypros_rankings
    drop constraint fantasypros_rankings_kind_check;

alter table public.fantasypros_rankings
    add constraint fantasypros_rankings_kind_check
    check (kind in ('weekly', 'ros', 'draft'));
