-- What Landry has already told each manager.
--
-- He does his rounds a few times a week and writes to whoever has something
-- worth hearing. Without a record he would say the same thing every run: the
-- best available receiver does not stop being the best available receiver
-- because he mentioned it on Tuesday.
--
-- Keyed on the subject rather than the message, so "sign Rico Dowdle" is one
-- note however he phrases it.
create table public.landry_notes (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users (id) on delete cascade,
    -- 'waiver', 'trade', 'injury'.
    kind       text not null,
    -- The player or the counterparty — whatever makes this advice distinct.
    subject    text not null,
    season     int  not null,
    week       int  not null,
    sent_at    timestamptz not null default now(),

    unique (user_id, kind, subject, season, week)
);

alter table public.landry_notes enable row level security;

-- A member can see what they were told and why, which makes "why did I get
-- that?" answerable.
create policy "Members read their own notes from Landry" on public.landry_notes
    for select using (auth.uid() = user_id);
