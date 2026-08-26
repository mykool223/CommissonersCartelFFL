-- How to refer to each manager.
--
-- Devon Carney uses she/her and is the only woman in the league, which means
-- anything generating prose about managers will get her wrong by default —
-- and did, on her team bio and again in Landry's messages.
--
-- Kept here rather than on profiles because only four of the twelve have
-- accounts, and a coach writing about somebody should get their pronouns
-- right whether or not they have signed up. team_bios is already where
-- things about a team that ESPN does not hold are kept.
alter table public.team_bios
    add column manager_pronouns text;

comment on column public.team_bios.manager_pronouns is
    'Subjective/objective, e.g. "she/her". Null means unknown, which callers '
    'must treat as they/them rather than as he/him.';
