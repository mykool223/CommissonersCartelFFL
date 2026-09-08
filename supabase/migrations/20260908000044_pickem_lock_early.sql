-- Lock a game's pick half an hour before kickoff, not at it.
--
-- Kickoff is the wrong deadline in practice: inactives are announced about
-- ninety minutes out, and a pick made in the last seconds before the whistle
-- is a pick made on information nobody else had time to act on. Thirty
-- minutes is the cushion the league agreed on.
--
-- This has to move here as well as in the apps, and the two must agree. The
-- apps decide what to grey out; the database decides what is actually
-- allowed. If only the apps moved, an older build — or anything that is not
-- the app — could still write inside the window. If only the database moved,
-- the app would offer a pick it cannot save and report a failure instead.
drop policy "Make your own picks before kickoff" on public.pickem_picks;

create policy "Make your own picks before the lock" on public.pickem_picks
    for insert with check (
        auth.uid() = user_id
        and private.is_member()
        and exists (
            select 1 from public.pickem_games g
             where g.season = pickem_picks.season
               and g.week = pickem_picks.week
               and g.event_id = pickem_picks.event_id
               and g.kickoff_at > now() + interval '30 minutes'
        )
    );

drop policy "Change your own picks before kickoff" on public.pickem_picks;

create policy "Change your own picks before the lock" on public.pickem_picks
    for update using (
        auth.uid() = user_id
        and exists (
            select 1 from public.pickem_games g
             where g.season = pickem_picks.season
               and g.week = pickem_picks.week
               and g.event_id = pickem_picks.event_id
               and g.kickoff_at > now() + interval '30 minutes'
        )
    ) with check (auth.uid() = user_id);
