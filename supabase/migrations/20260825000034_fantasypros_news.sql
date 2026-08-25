-- Player news and analysis from FantasyPros.
--
-- Their news endpoint carries a headline, a short factual description and an
-- "impact" paragraph explaining what it means for fantasy. We store the first
-- two and link out for the rest: the analysis is their editorial work, our
-- licence is for personal use, and a link is the honest way to pass somebody
-- else's writing along.
--
-- Separate from player_news, which comes from The Fantasy Footballers. Two
-- sources disagree usefully, and merging them into one table would lose which
-- is which.
create table public.fantasypros_news (
    id           uuid primary key default gen_random_uuid(),
    -- Their own id, so a re-fetch updates rather than duplicates.
    source_id    bigint not null unique,

    title        text not null,
    description  text,
    -- What it means for fantasy, in their words. Shown as a short extract
    -- with a link to the full piece.
    impact       text,
    link         text not null,

    player_name  text,
    team         text,
    author       text,
    categories   text[] not null default '{}',

    published_at timestamptz not null,
    created_at   timestamptz not null default now()
);

create index fantasypros_news_published_idx
    on public.fantasypros_news (published_at desc);

alter table public.fantasypros_news enable row level security;

-- Readable signed out, like league news and player news. It is a feed.
create policy "Anyone can read FantasyPros news" on public.fantasypros_news
    for select using (true);
