-- News about players on your own roster, as it lands.
--
-- The lineup guard already warns about a starter who cannot play, but only on
-- Sunday morning and only once they are already in the lineup. News that
-- breaks on a Wednesday — a practice report, a season-ending knee — reached
-- nobody until they happened to open the app.
--
-- This is the difference between a league that finds out and a league that
-- finds out on Sunday.
alter table public.notification_preferences
    add column roster_news boolean not null default true;

-- One alert per member per story, so a re-run of the ingest does not tell
-- somebody twice about the same knee.
create table public.roster_news_alerts (
    user_id  uuid not null references auth.users (id) on delete cascade,
    news_id  uuid not null references public.player_news (id) on delete cascade,
    sent_at  timestamptz not null default now(),

    primary key (user_id, news_id)
);

alter table public.roster_news_alerts enable row level security;

-- Only the job writes, with the service role. Members can see what they were
-- told, which makes "why did I get that?" answerable.
create policy "Members read their own roster news alerts"
    on public.roster_news_alerts
    for select using (auth.uid() = user_id);
