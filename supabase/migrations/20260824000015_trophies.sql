-- The trophy case.
--
-- ESPN has no history for this league — it was created for 2026, and every
-- previous season returns 404 — so there is nothing to import. Trophies are
-- earned from here on and accumulate.

create table public.trophies (
    id           uuid primary key default gen_random_uuid(),
    season       int  not null check (season between 2000 and 2100),
    -- Null for a season-long award; set for a weekly one.
    week         int,
    espn_team_id int  not null,
    kind         text not null,
    title        text not null check (length(title) between 1 and 60),
    detail       text check (length(detail) <= 200),
    awarded_at   timestamptz not null default now(),

    -- One of each kind per week, so re-running the job cannot award twice.
    unique (season, week, kind)
);

create index trophies_team_idx on public.trophies (season, espn_team_id);

alter table public.trophies enable row level security;

create policy "Anyone can read trophies" on public.trophies
    for select using (true);

-- Awarded only by the weekly job, which uses the service role key.

create or replace function private.on_trophy_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform private.notify_push(
        'news',
        'Trophy awarded',
        private.push_preview(new.title || coalesce(' — ' || new.detail, '')),
        null
    );
    return null;
end;
$$;

create trigger trophies_notify
    after insert on public.trophies
    for each row execute function private.on_trophy_insert();
