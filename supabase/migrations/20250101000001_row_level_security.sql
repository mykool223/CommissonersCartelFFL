-- Row level security.
--
-- The app ships with the anon key, which is public by design — these policies
-- are the only thing protecting the data. Default posture: you must be a signed
-- in league member to read anything, and only commissioners can publish.

create or replace function public.is_member()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select exists (select 1 from public.profiles p where p.id = auth.uid());
$$;

create or replace function public.is_commissioner()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.is_commissioner
    );
$$;

alter table public.profiles     enable row level security;
alter table public.news_posts   enable row level security;
alter table public.recaps       enable row level security;
alter table public.polls        enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes   enable row level security;

-- Profiles ------------------------------------------------------------------

create policy "Members can see the roster"
    on public.profiles for select
    using (public.is_member());

create policy "Members can edit their own profile"
    on public.profiles for update
    using (id = auth.uid())
    with check (id = auth.uid());

-- Deliberately no INSERT policy: profiles are created by the
-- on_auth_user_created trigger, never by the client.

-- News and recaps -----------------------------------------------------------

create policy "Members can read the news"
    on public.news_posts for select
    using (public.is_member());

create policy "Commissioners can publish news"
    on public.news_posts for all
    using (public.is_commissioner())
    with check (public.is_commissioner());

create policy "Members can read recaps"
    on public.recaps for select
    using (public.is_member());

create policy "Commissioners can publish recaps"
    on public.recaps for all
    using (public.is_commissioner())
    with check (public.is_commissioner());

-- Polls ---------------------------------------------------------------------

create policy "Members can read polls"
    on public.polls for select
    using (public.is_member());

-- Any member can start a poll, not just the commissioner.
create policy "Members can create polls"
    on public.polls for insert
    with check (public.is_member() and created_by = auth.uid());

create policy "Authors and commissioners can change a poll"
    on public.polls for update
    using (created_by = auth.uid() or public.is_commissioner())
    with check (created_by = auth.uid() or public.is_commissioner());

create policy "Authors and commissioners can delete a poll"
    on public.polls for delete
    using (created_by = auth.uid() or public.is_commissioner());

create policy "Members can read poll options"
    on public.poll_options for select
    using (public.is_member());

create policy "Poll authors can manage their options"
    on public.poll_options for all
    using (
        exists (
            select 1 from public.polls p
            where p.id = poll_id
              and (p.created_by = auth.uid() or public.is_commissioner())
        )
    )
    with check (
        exists (
            select 1 from public.polls p
            where p.id = poll_id
              and (p.created_by = auth.uid() or public.is_commissioner())
        )
    );

-- Votes ---------------------------------------------------------------------

-- Members can read ONLY their own vote. Tallies come from
-- polls_with_results(), which is security definer — that is what keeps results
-- hidden until you have voted, rather than merely hiding them in the UI where
-- anyone with the anon key could read around it.
create policy "Members can see their own vote"
    on public.poll_votes for select
    using (voter_id = auth.uid());

-- Writes go through cast_vote(), which also enforces the closing time. No
-- direct insert/update/delete policy is defined, so the client cannot bypass it.
