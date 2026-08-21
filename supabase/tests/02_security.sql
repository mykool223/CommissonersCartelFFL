-- Asserts the security properties the app relies on. Any failure raises, and
-- psql runs with ON_ERROR_STOP=1, so the script exits non-zero.
--
-- These are the claims worth testing because they are enforced in Postgres
-- rather than in the UI: if any of them regress, the app looks fine and the
-- data is wrong.

create or replace function assert(condition boolean, description text)
returns void language plpgsql as $$
begin
    if condition then
        raise notice '  ok   %', description;
    else
        raise exception 'FAILED: %', description;
    end if;
end $$;


-- Runs `body` as `role_name` impersonating `user_id`, returning a bigint.
create or replace function as_user(user_id text, query text)
returns bigint language plpgsql as $$
declare result bigint;
begin
    perform set_config('request.jwt.claim.sub', user_id, true);
    execute query into result;
    return result;
end $$;

-- Returns true when `stmt` raises, false when it succeeds.
create or replace function blocked(stmt text)
returns boolean language plpgsql as $$
begin
    execute stmt;
    return false;
exception when others then
    return true;
end $$;

\echo ''
\echo '--- visibility ---'
set role authenticated;

do $$
declare
    outsider constant text := '33333333-3333-3333-3333-333333333333';
    member   constant text := '22222222-2222-2222-2222-222222222222';
begin
    -- League news and recaps are deliberately readable without membership
    -- (see 20260821000005) because there is no sign-in yet and the tab would
    -- otherwise always be empty. Polls, votes and profiles are NOT, and this
    -- asserts that the exception stayed narrow.
    perform assert(as_user(outsider, 'select count(*) from public.news_posts') = 1,
                   'league news is readable without membership (deliberate)');
    perform assert(as_user(outsider, 'select count(*) from public.polls') = 0,
                   'a signed-in non-member still sees no polls');
    perform assert(as_user(outsider, 'select count(*) from public.profiles') = 0,
                   'a signed-in non-member still sees no member list');
    perform assert(as_user(outsider, 'select count(*) from public.poll_votes') = 0,
                   'a signed-in non-member still sees no votes');
    perform assert(as_user(member, 'select count(*) from public.news_posts') = 1,
                   'a member sees the news');
    perform assert(as_user(member, 'select count(*) from public.polls') = 2,
                   'a member sees the polls');
end $$;

\echo ''
\echo '--- voting ---'
do $$
declare
    member   constant text := '22222222-2222-2222-2222-222222222222';
    commish  constant text := '11111111-1111-1111-1111-111111111111';
    poll     constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
    opt_a    constant uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
    opt_b    constant uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
    total    bigint;
    mine     uuid;
begin
    perform set_config('request.jwt.claim.sub', member, true);

    perform public.cast_vote(poll, opt_a);
    select sum((o->>'vote_count')::int) into total
      from public.polls_with_results(2026) p, jsonb_array_elements(p.options) o
     where p.id = poll;
    perform assert(total = 1, 'a vote is counted');

    -- The property that matters: re-voting must not inflate the tally.
    perform public.cast_vote(poll, opt_a);
    select sum((o->>'vote_count')::int) into total
      from public.polls_with_results(2026) p, jsonb_array_elements(p.options) o
     where p.id = poll;
    perform assert(total = 1, 'voting twice for the same option does not double-count');

    perform public.cast_vote(poll, opt_b);
    select sum((o->>'vote_count')::int) into total
      from public.polls_with_results(2026) p, jsonb_array_elements(p.options) o
     where p.id = poll;
    perform assert(total = 1, 'changing your vote moves it rather than adding one');

    select my_vote_option_id into mine from public.polls_with_results(2026) where id = poll;
    perform assert(mine = opt_b, 'the poll reports which option you picked');

    perform set_config('request.jwt.claim.sub', commish, true);
    perform public.cast_vote(poll, opt_a);
    select sum((o->>'vote_count')::int) into total
      from public.polls_with_results(2026) p, jsonb_array_elements(p.options) o
     where p.id = poll;
    perform assert(total = 2, 'a second member''s vote counts separately');

    -- Results stay hidden until you vote *because of this*, not because the UI
    -- hides them. Anyone with the anon key could otherwise read around it.
    perform assert(
        (select count(*) from public.poll_votes) = 1,
        'a member can read only their own vote row'
    );
end $$;

\echo ''
\echo '--- writes that must be refused ---'
do $$
declare member constant text := '22222222-2222-2222-2222-222222222222';
begin
    perform set_config('request.jwt.claim.sub', member, true);

    perform assert(blocked($q$
        select public.cast_vote('aaaaaaaa-0000-0000-0000-000000000002',
                                'bbbbbbbb-0000-0000-0000-000000000009') $q$),
        'voting on a closed poll is refused');

    perform assert(blocked($q$
        select public.cast_vote('aaaaaaaa-0000-0000-0000-000000000001',
                                'bbbbbbbb-0000-0000-0000-000000000009') $q$),
        'voting for an option from a different poll is refused');

    -- No insert policy exists on poll_votes, so cast_vote cannot be bypassed.
    perform assert(blocked($q$
        insert into public.poll_votes (poll_id, option_id, voter_id)
        values ('aaaaaaaa-0000-0000-0000-000000000002',
                'bbbbbbbb-0000-0000-0000-000000000009',
                '22222222-2222-2222-2222-222222222222') $q$),
        'writing to poll_votes directly is refused');

    -- Reading league news is open; writing it is emphatically not.
    perform assert(blocked($q$
        insert into public.news_posts (title, body, author_name, season)
        values ('Sneaky', 'Body', 'Member', 2026) $q$),
        'a non-commissioner cannot publish news');
end $$;

\echo ''
\echo '--- anon (the key shipped in the app) ---'
reset role;
set role anon;

do $$
begin
    -- Regression guard. `revoke ... from anon` is a silent no-op: Postgres
    -- grants EXECUTE to PUBLIC by default and every role inherits from it, so
    -- the revoke has to name PUBLIC.
    perform assert(blocked('select public.polls_with_results(2026)'),
                   'anon cannot execute polls_with_results');
    perform assert(blocked($q$
        select public.cast_vote('aaaaaaaa-0000-0000-0000-000000000001',
                                'bbbbbbbb-0000-0000-0000-000000000001') $q$),
        'anon cannot execute cast_vote');
    -- anon can read league news by design now; it must still not write.
    perform assert((select count(*) from public.news_posts) = 1,
                   'anon can read league news (deliberate)');
    perform assert(blocked($q$
        insert into public.news_posts (title, body, author_name, season)
        values ('anon post', 'Body', 'anon', 2026) $q$),
        'anon cannot publish news');
end $$;

reset role;
\echo ''
\echo 'All database security expectations held.'
