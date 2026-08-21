-- The two RPCs the iOS app calls.

-- Everything the polls screen needs in one round trip: the poll, its options,
-- the vote tally, and which option the caller picked.
--
-- security definer so it can count rows in poll_votes, which RLS otherwise
-- restricts to the caller's own vote.
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
                    select o.id,
                           o.label,
                           o.position,
                           count(v.voter_id) as vote_count
                    from public.poll_options o
                    left join public.poll_votes v on v.option_id = o.id
                    where o.poll_id = p.id
                    group by o.id, o.label, o.position
                ) as tallied
            ),
            '[]'::jsonb
        ) as options
    from public.polls p
    -- The definer rights above bypass RLS, so re-check membership explicitly.
    where p.season = p_season
      and public.is_member()
    order by p.created_at desc;
$$;

-- Records a vote, replacing any previous one on the same poll.
--
-- This is the only write path into poll_votes: RLS defines no insert or update
-- policy, so the closing-time and option-belongs-to-poll checks below cannot be
-- skipped by talking to PostgREST directly.
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

    if not public.is_member() then
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

-- PostgREST exposes functions to whichever role calls them; restrict to
-- signed-in users.
revoke execute on function public.polls_with_results(int) from anon;
revoke execute on function public.cast_vote(uuid, uuid) from anon;
grant execute on function public.polls_with_results(int) to authenticated;
grant execute on function public.cast_vote(uuid, uuid) to authenticated;
