-- What was said to the coach, and what he said back.
--
-- Until now a conversation lived only in the app's memory: close the tab and
-- it was gone, and it never existed on your other phone at all. Members asked
-- to be able to look back at what he told them, which is fair — advice you
-- cannot re-read is advice you have to take on trust twice.
create table public.coach_messages (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users (id) on delete cascade,
    -- 'member' or 'coach', matching how the app draws each side.
    role       text not null check (role in ('member', 'coach')),
    content    text not null,
    created_at timestamptz not null default now()
);

create index coach_messages_user_idx
    on public.coach_messages (user_id, created_at);

alter table public.coach_messages enable row level security;

-- Your own conversation and nobody else's. A coach who tells one manager what
-- another asked him would not last the season.
create policy "Members read their own coach messages" on public.coach_messages
    for select using (auth.uid() = user_id);

-- Members can clear their own history. Nobody else can touch it, and the
-- function writes with the service role.
create policy "Members delete their own coach messages" on public.coach_messages
    for delete using (auth.uid() = user_id);
