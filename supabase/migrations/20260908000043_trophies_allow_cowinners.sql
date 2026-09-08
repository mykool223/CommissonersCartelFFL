-- Let a week's trophy be shared.
--
-- A confidence pool ends in a tie often enough to matter: two members can
-- finish on the same points having weighted different games. The old
-- constraint allowed exactly one row per kind per week, so the second winner
-- was silently dropped — the worst possible outcome in a twelve-man league
-- that argues about everything.
--
-- Adding the team to the key still stops the job awarding twice on a re-run,
-- which is what the constraint was for: the same team, week and kind is still
-- one row.
alter table public.trophies
    drop constraint trophies_season_week_kind_key;

alter table public.trophies
    add constraint trophies_unique_award unique (season, week, kind, espn_team_id);
