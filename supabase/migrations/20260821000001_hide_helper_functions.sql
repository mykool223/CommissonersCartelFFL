-- Take the helper functions out of the PostgREST-exposed API surface.
--
-- Supabase exposes every function in `public` as an RPC endpoint. That means
-- `is_member()`, `is_commissioner()` and — worse — the `handle_new_user()`
-- trigger function were all callable over HTTP. Supabase's own database linter
-- flags this (lints 0028 and 0029).
--
-- Nothing here was exploitable: the is_* helpers only report on the caller, and
-- handle_new_user references `new`, so calling it outside a trigger just errors.
-- But a trigger function has no business being an HTTP endpoint, and helpers
-- belong behind the API rather than on it.
--
-- The fix is a schema move, not a revoke. Policies are evaluated as the calling
-- role, so `authenticated` still needs EXECUTE on these — revoking it would
-- break every policy. PostgREST only exposes `public`, so a function in
-- `private` stays callable from inside policies while disappearing from the API.

create schema if not exists private;

-- Both roles need to reach the schema for policy evaluation to work.
grant usage on schema private to anon, authenticated;

create or replace function private.is_member()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select exists (select 1 from public.profiles p where p.id = auth.uid());
$$;

create or replace function private.is_commissioner()
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

grant execute on function private.is_member() to anon, authenticated;
grant execute on function private.is_commissioner() to anon, authenticated;

-- Repoint every policy that referenced the public helpers.

drop policy "Members can see the roster" on public.profiles;
create policy "Members can see the roster"
    on public.profiles for select
    using (private.is_member());

drop policy "Members can read the news" on public.news_posts;
create policy "Members can read the news"
    on public.news_posts for select
    using (private.is_member());

drop policy "Commissioners can publish news" on public.news_posts;
create policy "Commissioners can publish news"
    on public.news_posts for all
    using (private.is_commissioner())
    with check (private.is_commissioner());

drop policy "Members can read recaps" on public.recaps;
create policy "Members can read recaps"
    on public.recaps for select
    using (private.is_member());

drop policy "Commissioners can publish recaps" on public.recaps;
create policy "Commissioners can publish recaps"
    on public.recaps for all
    using (private.is_commissioner())
    with check (private.is_commissioner());

drop policy "Members can read polls" on public.polls;
create policy "Members can read polls"
    on public.polls for select
    using (private.is_member());

drop policy "Members can create polls" on public.polls;
create policy "Members can create polls"
    on public.polls for insert
    with check (private.is_member() and created_by = auth.uid());

drop policy "Authors and commissioners can change a poll" on public.polls;
create policy "Authors and commissioners can change a poll"
    on public.polls for update
    using (created_by = auth.uid() or private.is_commissioner())
    with check (created_by = auth.uid() or private.is_commissioner());

drop policy "Authors and commissioners can delete a poll" on public.polls;
create policy "Authors and commissioners can delete a poll"
    on public.polls for delete
    using (created_by = auth.uid() or private.is_commissioner());

drop policy "Members can read poll options" on public.poll_options;
create policy "Members can read poll options"
    on public.poll_options for select
    using (private.is_member());

drop policy "Poll authors can manage their options" on public.poll_options;
create policy "Poll authors can manage their options"
    on public.poll_options for all
    using (
        exists (
            select 1 from public.polls p
            where p.id = poll_id
              and (p.created_by = auth.uid() or private.is_commissioner())
        )
    )
    with check (
        exists (
            select 1 from public.polls p
            where p.id = poll_id
              and (p.created_by = auth.uid() or private.is_commissioner())
        )
    );

-- polls_with_results re-checks membership itself, since security definer
-- bypasses RLS.
create or replace function public.polls_with_results(p_season int)
returns table (
    id                uuid,
    question          text,
    season            int,
    week              int,
    created_by_name   text,
    created_at        timestamptz,
    closes_at         timestamptz,
    my_vote_option_id uuid,
    options           jsonb
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select
        p.id,
        p.question,
        p.season,
        p.week,
        p.created_by_name,
        p.created_at,
        p.closes_at,
        (
            select v.option_id
            from public.poll_votes v
            where v.poll_id = p.id and v.voter_id = auth.uid()
        ) as my_vote_option_id,
        coalesce(
            (
                select jsonb_agg(
                    jsonb_build_object(
                        'id', tallied.id,
                        'label', tallied.label,
                        'vote_count', tallied.vote_count
                    )
                    order by tallied.position, tallied.label
                )
                from (
                    select o.id, o.label, o.position, count(v.voter_id) as vote_count
                    from public.poll_options o
                    left join public.poll_votes v on v.option_id = o.id
                    where o.poll_id = p.id
                    group by o.id, o.label, o.position
                ) as tallied
            ),
            '[]'::jsonb
        ) as options
    from public.polls p
    where p.season = p_season
      and private.is_member()
    order by p.created_at desc;
$$;

-- Recreating the function resets its ACL to the defaults, so re-apply the
-- restriction from 20260821000000.
revoke execute on function public.polls_with_results(int) from public, anon;
grant execute on function public.polls_with_results(int) to authenticated;

-- cast_vote also referenced the public helper.
create or replace function public.cast_vote(p_poll_id uuid, p_option_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_closes_at timestamptz;
    v_exists    boolean;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to vote' using errcode = '42501';
    end if;

    if not private.is_member() then
        raise exception 'Only league members can vote' using errcode = '42501';
    end if;

    select closes_at into v_closes_at from public.polls where id = p_poll_id;
    if not found then
        raise exception 'That poll no longer exists' using errcode = '22023';
    end if;

    if v_closes_at is not null and now() >= v_closes_at then
        raise exception 'This poll is closed' using errcode = '22023';
    end if;

    select exists (
        select 1 from public.poll_options
        where id = p_option_id and poll_id = p_poll_id
    ) into v_exists;

    if not v_exists then
        raise exception 'That option is not on this poll' using errcode = '22023';
    end if;

    insert into public.poll_votes (poll_id, option_id, voter_id)
    values (p_poll_id, p_option_id, auth.uid())
    on conflict (poll_id, voter_id) do update
        set option_id  = excluded.option_id,
            created_at = now();
end;
$$;

revoke execute on function public.cast_vote(uuid, uuid) from public, anon;
grant execute on function public.cast_vote(uuid, uuid) to authenticated;

-- The old public helpers are now unreferenced.
drop function if exists public.is_member();
drop function if exists public.is_commissioner();

-- handle_new_user is fired by a trigger on auth.users and runs as its owner.
-- It never needs to be callable by a client, and should never have been an
-- HTTP endpoint.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
