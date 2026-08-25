-- The power ranking is readable signed out, as league news is.
--
-- It was behind a sign-in, which meant the members list showed ESPN's playoff
-- seed to anyone not signed in and the league's ranking to anyone who was —
-- the same screen, two different numbers, depending on who was looking.
--
-- There is nothing private here: it is twelve public team names in an order
-- the commissioner reads off a public tool.
drop policy if exists "Members read power rankings" on public.power_rankings;

create policy "Anyone can read power rankings" on public.power_rankings
    for select using (true);
