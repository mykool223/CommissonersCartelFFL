-- Full articles from FantasyPros, via their public RSS feed.
--
-- Replaces fantasypros_news, which was a mistake: their API's news endpoint
-- returns single-player blurbs, which is the same thing the Fantasy
-- Footballers feed already gives us. Two feeds of the same material is one
-- feed too many. The articles — sleepers, start/sit, draft advice — are what
-- the section was meant to carry.
--
-- RSS is published for syndication, so this is the intended way to read it.
-- The excerpt is stored and the card links out for the full piece.
drop table if exists public.fantasypros_news;

create table public.fantasypros_articles (
    id           uuid primary key default gen_random_uuid(),
    -- The feed's own guid, so a re-poll updates rather than duplicates.
    guid         text not null unique,

    title        text not null,
    excerpt      text,
    link         text not null,
    author       text,
    categories   text[] not null default '{}',

    published_at timestamptz not null,
    created_at   timestamptz not null default now()
);

create index fantasypros_articles_published_idx
    on public.fantasypros_articles (published_at desc);

alter table public.fantasypros_articles enable row level security;

create policy "Anyone can read FantasyPros articles" on public.fantasypros_articles
    for select using (true);
