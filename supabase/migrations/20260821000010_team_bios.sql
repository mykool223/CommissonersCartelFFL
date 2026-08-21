-- A line of flavour for each team.
--
-- Keyed by ESPN's team id rather than a name, because managers rename teams
-- mid-season and a bio should follow the seat, not the sign on it. Scoped by
-- season for the same reason ESPN scopes everything that way: ids are reused.

create table public.team_bios (
    season       int  not null check (season between 2000 and 2100),
    espn_team_id int  not null,
    -- The role, as in "The Boss". Shown above the bio.
    title        text not null check (length(title) between 1 and 60),
    bio          text not null check (length(bio) between 1 and 600),
    updated_at   timestamptz not null default now(),

    primary key (season, espn_team_id)
);

alter table public.team_bios enable row level security;

-- Readable without membership, matching league news: this is flavour text
-- about team names, not anything private.
create policy "Anyone can read team bios"
    on public.team_bios for select
    using (true);

create policy "Commissioners write team bios"
    on public.team_bios for all
    using (private.is_commissioner())
    with check (private.is_commissioner());
