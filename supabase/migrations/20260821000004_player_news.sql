-- Player news blurbs from The Fantasy Footballers' news page.
--
-- Replaces external_articles, which pulled their podcast RSS feed. That feed
-- carries show episodes and long-form articles; this is the running feed of
-- short player updates — injuries, depth chart moves, practice reports — which
-- is what the league actually wants to see.
--
-- Stores the short factual blurb only. Their extended analysis paragraph is
-- deliberately not captured: it is the part with editorial value, and the app
-- links back for anyone who wants it.

drop table if exists public.external_articles;

create table public.player_news (
    id             uuid primary key default gen_random_uuid(),

    -- The publisher's own numeric id from the article URL. Sequential and
    -- stable, so it is what dedup keys on.
    source_id      bigint      not null unique,
    source_name    text        not null default 'The Fantasy Footballers',

    player_name    text        not null check (length(player_name) between 1 and 120),
    player_position text check (length(player_position) <= 8),
    player_team    text check (length(player_team) <= 8),
    headshot_url   text,

    headline       text        not null check (length(headline) between 1 and 300),
    -- The short blurb. Not the full article.
    blurb          text,
    url            text        not null check (url like 'http%'),

    published_at   timestamptz not null,
    fetched_at     timestamptz not null default now()
);

create index player_news_published_idx on public.player_news (published_at desc);

alter table public.player_news enable row level security;

-- Public headlines, so no membership requirement — the same reasoning as
-- 20260821000003. Anyone can read this on the publisher's own site.
create policy "Anyone can read player news"
    on public.player_news for select
    using (true);

-- No insert/update/delete policy: the daily ingest uses the service role.
