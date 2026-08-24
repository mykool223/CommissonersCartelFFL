-- Reactions on league thread messages.
--
-- Deliberately not a like count: a thumbs-down on somebody's terrible trade
-- take is the entire point, and a single positive reaction would miss it.

create table public.message_reactions (
    message_id uuid not null references public.league_messages (id) on delete cascade,
    -- Defaulted from the session, so a client never states who it is. The
    -- insert policy checks the same thing, which makes claiming to be someone
    -- else impossible rather than merely discouraged.
    user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
    emoji      text not null check (emoji in ('👍', '👎', '😂', '🔥', '💀')),
    created_at timestamptz not null default now(),

    -- One of each emoji per person per message. Tapping again removes it.
    primary key (message_id, user_id, emoji)
);

create index message_reactions_message_idx on public.message_reactions (message_id);

alter table public.message_reactions enable row level security;

-- Members see every reaction: who reacted is the interesting part, and the
-- thread is already members-only.
create policy "Members read reactions" on public.message_reactions
    for select using (private.is_member());

-- You may only add and remove your own.
create policy "Members add their own reactions" on public.message_reactions
    for insert with check (auth.uid() = user_id and private.is_member());

create policy "Members remove their own reactions" on public.message_reactions
    for delete using (auth.uid() = user_id);
