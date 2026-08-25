-- A logo the league controls, for teams that never uploaded one to ESPN.
--
-- Eight of the twelve are still on ESPN's stock art, which makes the members
-- list a wall of identical gold crests — you cannot tell one team from another
-- at a glance, which is most of what a logo is for.
--
-- Kept beside the bio because it is the same idea: things about a team that
-- ESPN does not hold. A row here wins over ESPN's logo; no row and the app
-- carries on using ESPN's, so a manager who later uploads their own is not
-- overridden by us.
alter table public.team_bios
    add column logo_url text;
