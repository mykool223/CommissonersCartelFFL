-- The league's message thread, and letting members claim their ESPN team.

create table public.league_messages (
    id          uuid primary key default gen_random_uuid(),
    author_id   uuid        not null references public.profiles (id) on delete cascade,
    -- Denormalised so a message keeps its name if the account is deleted.
    author_name text        not null,
    body        text        not null check (length(trim(body)) between 1 and 2000),
    created_at  timestamptz not null default now()
);

create index league_messages_created_idx on public.league_messages (created_at desc);

alter table public.league_messages enable row level security;

-- Unlike league news, the thread is members-only. News is broadcast; this is
-- a conversation, and it should not be readable by anyone holding the anon key.
create policy "Members can read the thread"
    on public.league_messages for select
    using (private.is_member());

-- You post as yourself. author_id = auth.uid() is what stops one member
-- posting under another's name.
create policy "Members can post"
    on public.league_messages for insert
    with check (private.is_member() and author_id = auth.uid());

create policy "Authors and commissioners can delete a message"
    on public.league_messages for delete
    using (author_id = auth.uid() or private.is_commissioner());

-- No update policy: an edited message with no trace is worse than none, and
-- nobody needs to rewrite history in a fantasy league.

-- Let a signed-in member claim their own ESPN team.
--
-- ESPN exposes no email addresses, so the app cannot work out that a given
-- account belongs to a given team. The member picks it once from the real
-- roster; this is the only field they may set on themselves.
create or replace function public.claim_espn_team(p_swid text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then
        raise exception 'You must be signed in' using errcode = '42501';
    end if;

    if p_swid is null or length(trim(p_swid)) = 0 then
        raise exception 'That is not a valid team' using errcode = '22023';
    end if;

    -- One ESPN member per account. Taking a team someone already claimed would
    -- silently reassign it.
    if exists (
        select 1 from public.profiles
        where espn_swid = p_swid and id <> auth.uid()
    ) then
        raise exception 'Another member has already claimed that team'
            using errcode = '23505';
    end if;

    update public.profiles
       set espn_swid = p_swid
     where id = auth.uid();
end;
$$;

revoke execute on function public.claim_espn_team(text) from public, anon;
grant execute on function public.claim_espn_team(text) to authenticated;
