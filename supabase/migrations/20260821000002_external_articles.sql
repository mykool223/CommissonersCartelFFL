-- Headlines syndicated from outside the league.
--
-- Only ever holds the *reference* to an article — headline, excerpt, link —
-- never the full text. The app links out to the publisher. Reproducing their
-- writing would be a copyright problem; sending them the traffic is the deal
-- an RSS feed implies.

create table public.external_articles (
    id           uuid primary key default gen_random_uuid(),

    -- Machine key for the publisher ("fantasy_footballers") plus the display
    -- name, so the UI can attribute without a lookup table.
    source_key   text        not null check (length(source_key) between 1 and 60),
    source_name  text        not null check (length(source_name) between 1 and 120),

    -- The feed's own identifier for the item. Feeds re-publish the same entry
    -- on every fetch, so this is what stops the table filling with duplicates.
    guid         text        not null check (length(guid) between 1 and 500),

    title        text        not null check (length(title) between 1 and 300),
    url          text        not null check (url like 'http%'),
    excerpt      text,
    author       text,
    image_url    text,

    published_at timestamptz not null,
    fetched_at   timestamptz not null default now(),

    -- One row per article per publisher. The ingest upserts on this.
    unique (source_key, guid)
);

-- The feed is always "newest first", optionally filtered by publisher.
create index external_articles_published_idx
    on public.external_articles (published_at desc);
create index external_articles_source_idx
    on public.external_articles (source_key, published_at desc);

alter table public.external_articles enable row level security;

create policy "Members can read outside news"
    on public.external_articles for select
    using (private.is_member());

-- Deliberately no insert/update/delete policy. The only writer is the daily
-- ingest, which authenticates with the service role and bypasses RLS. Nothing
-- carrying the anon key can write here.
