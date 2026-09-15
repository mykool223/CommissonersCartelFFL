-- The season table, which is the one people actually argue about.
--
-- Until now the only standings were per week, so every Tuesday the board
-- appeared to reset: a new week has no final games, so everyone sat on zero
-- and the running total — the number that says who is winning the pool —
-- existed nowhere in the app at all.
--
-- Only final games count, which is also what makes this safe to show
-- everybody. The view runs as the caller, so it aggregates the picks that
-- caller may read; picks stay private until their game kicks off, and by the
-- time a game is final it has certainly started. Nothing here can reveal a
-- pick that is still hidden.
create view public.pickem_season_standings
with (security_invoker = true) as
    select p.season,
           p.user_id,
           count(*) filter (where g.final and g.winner_abbr = p.chosen_abbr) as correct,
           count(*) filter (where g.final) as decided,
           coalesce(sum(p.confidence)
                    filter (where g.final and g.winner_abbr = p.chosen_abbr), 0) as points,
           count(distinct p.week) filter (where g.final) as weeks_played,
           pr.display_name
      from public.pickem_picks p
      join public.pickem_games g
        on g.season = p.season and g.week = p.week and g.event_id = p.event_id
      left join public.profiles pr
        on pr.id = p.user_id
     group by p.season, p.user_id, pr.display_name;
