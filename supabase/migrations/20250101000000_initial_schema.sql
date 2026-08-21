-- Core tables for league-authored content.
--
-- ESPN owns rosters, scores and standings; this database owns only what the
-- league writes itself. Nothing here duplicates ESPN data, so there is no sync
-- to keep correct.

create extension if not exists "pgcrypto";

-- One row per signed-in league member, mirroring auth.users.
create table public.profiles (
    id              uuid primary key references auth.users (id) on delete cascade,
    display_name    text        not null check (length(display_name) between 1 and 60),
    avatar_url      text,
    -- Links this account to its ESPN member, so the app can tell which team is
    -- "yours". ESPN's SWID, brace-wrapped: '{1A2B...}'.
    espn_swid       text unique,
    is_commissioner boolean     not null default false,
    created_at      timestamptz not null default now()
);

comment on column public.profiles.espn_swid is
    'ESPN member SWID, brace-wrapped. Set once by the commissioner.';

create table public.news_posts (
    id              uuid primary key default gen_random_uuid(),
    title           text        not null check (length(title) between 1 and 200),
    body            text        not null check (length(body) > 0),
    author_id       uuid references public.profiles (id) on delete set null,
    -- Denormalised so a post keeps its byline if the author's account is deleted.
    author_name     text        not null,
    week            int check (week between 1 and 18),
    season          int         not null check (season between 2000 and 2100),
    cover_image_url text,
    published_at    timestamptz not null default now(),
    created_at      timestamptz not null default now()
);

-- The feed is always "this season, newest first".
create index news_posts_season_published_idx
    on public.news_posts (season, published_at desc);

create table public.recaps (
    id          uuid primary key default gen_random_uuid(),
    season      int         not null check (season between 2000 and 2100),
    week        int         not null check (week between 1 and 18),
    -- ESPN's schedule item id, so the app can show a recap under its matchup.
    -- Nullable: a recap can cover the whole week instead of one game.
    matchup_id  int,
    headline    text        not null check (length(headline) between 1 and 200),
    body        text        not null check (length(body) > 0),
    author_id   uuid references public.profiles (id) on delete set null,
    author_name text        not null,
    created_at  timestamptz not null default now()
);

create index recaps_season_week_idx on public.recaps (season, week);

create table public.polls (
    id              uuid primary key default gen_random_uuid(),
    question        text        not null check (length(question) between 1 and 300),
    season          int         not null check (season between 2000 and 2100),
    week            int check (week between 1 and 18),
    created_by      uuid references public.profiles (id) on delete set null,
    created_by_name text        not null,
    -- Null means the poll never closes.
    closes_at       timestamptz,
    created_at      timestamptz not null default now()
);

create index polls_season_created_idx on public.polls (season, created_at desc);

create table public.poll_options (
    id       uuid primary key default gen_random_uuid(),
    poll_id  uuid not null references public.polls (id) on delete cascade,
    label    text not null check (length(label) between 1 and 120),
    position int  not null default 0,

    -- Lets poll_votes reference (option_id, poll_id) as a pair, which is what
    -- makes "vote for an option on a different poll" impossible.
    unique (id, poll_id)
);

create index poll_options_poll_idx on public.poll_options (poll_id, position);

create table public.poll_votes (
    poll_id    uuid        not null references public.polls (id) on delete cascade,
    option_id  uuid        not null,
    voter_id   uuid        not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),

    -- One vote per person per poll. Changing your mind is an UPDATE, not a
    -- second row, so the tally can never be inflated by re-voting.
    primary key (poll_id, voter_id),

    -- The chosen option must belong to the poll being voted on.
    foreign key (option_id, poll_id)
        references public.poll_options (id, poll_id) on delete cascade
);

create index poll_votes_option_idx on public.poll_votes (option_id);

-- Create a profile automatically whenever someone signs up, so the app never
-- has to handle a signed-in user with no profile row.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(
            new.raw_user_meta_data ->> 'display_name',
            split_part(new.email, '@', 1),
            'New member'
        )
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
