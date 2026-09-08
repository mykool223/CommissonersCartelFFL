-- Put the member's name on the standings row.
--
-- The apps asked PostgREST to embed it — `select=*,profiles(display_name)` —
-- and PostgREST refused: a view has no foreign keys, so there is no
-- relationship for it to follow. Every request came back 400, and both apps
-- treat a failed standings fetch as "the table is a nicety" and swallow it. So
-- the weekly table has never appeared on either platform, and nothing said so.
--
-- Joining the name into the view itself removes the embed, and with it the
-- need for PostgREST to infer anything.
--
-- `create or replace view` can only append columns, never reorder or retype
-- the existing ones, which is why display_name goes last.
--
-- The join is a LEFT join on purpose: the view runs as the caller, so a
-- profile the caller cannot read leaves a null name rather than dropping that
-- member's score out of the standings entirely.
create or replace view public.pickem_standings
with (security_invoker = true) as
    select p.season,
           p.week,
           p.user_id,
           count(*) filter (where g.final and g.winner_abbr = p.chosen_abbr) as correct,
           count(*) filter (where g.final) as decided,
           coalesce(sum(p.confidence)
                    filter (where g.final and g.winner_abbr = p.chosen_abbr), 0) as points,
           pr.display_name
      from public.pickem_picks p
      join public.pickem_games g
        on g.season = p.season and g.week = p.week and g.event_id = p.event_id
      left join public.profiles pr
        on pr.id = p.user_id
     group by p.season, p.week, p.user_id, pr.display_name;
