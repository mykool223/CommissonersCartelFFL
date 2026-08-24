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
\echo '--- the invite list ---'
-- Runs before any `set role`, so these counts are what the tables hold rather
-- than what one role is allowed to see through RLS.
do $$
begin
    -- The rule the list exists for: signing up is not the same as being let in.
    perform assert(
        (select count(*) from public.profiles
          where id = '33333333-3333-3333-3333-333333333333') = 0,
        'an uninvited signup gets no profile, so is not a member'
    );
    perform assert(
        (select count(*) from public.profiles) = 2,
        'only invited addresses became members'
    );
    -- Using an invite should mark it, so the commissioner can see who has not
    -- signed in yet.
    perform assert(
        (select claimed_at is not null from public.league_invites
          where email = 'commish@example.com'),
        'a used invite is marked as claimed'
    );
    perform assert(
        (select count(*) from public.league_invites where email = 'outsider@example.com') = 0,
        'the outsider was never invited'
    );
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
    perform assert(as_user(outsider, 'select count(*) from public.league_messages') = 0,
                   'a signed-in non-member cannot read the league thread');
    perform assert(as_user(member, 'select count(*) from public.league_invites') = 0,
                   'an ordinary member cannot read the invite list');
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
\echo '--- creating polls ---'
do $$
declare
    member   constant text := '22222222-2222-2222-2222-222222222222';
    outsider constant text := '33333333-3333-3333-3333-333333333333';
    v_id     uuid;
begin
    -- Any member, not only a commissioner: the league wanted polls to come
    -- from anyone.
    perform set_config('request.jwt.claim.sub', member, true);
    select public.create_poll('Best waiver pickup?', array['A','B','C']) into v_id;
    perform assert(v_id is not null, 'an ordinary member can create a poll');
    perform assert(
        (select count(*) from public.poll_options where poll_id = v_id) = 3,
        'the options are created with it'
    );
    perform assert(
        (select created_by from public.polls where id = v_id) = member::uuid,
        'the author is taken from the session, not the client'
    );

    -- Blank boxes are normal in a form with a fixed number of fields.
    select public.create_poll('Two of three?', array['A','','B']) into v_id;
    perform assert(
        (select count(*) from public.poll_options where poll_id = v_id) = 2,
        'blank options are dropped rather than rejected'
    );

    perform assert(blocked($q$ select public.create_poll('One?', array['Only one']) $q$),
                   'a poll with one option is refused');
    perform assert(blocked($q$ select public.create_poll('', array['A','B']) $q$),
                   'a poll with no question is refused');
    perform assert(blocked($q$
        select public.create_poll('Past?', array['A','B'], now() - interval '1 hour') $q$),
        'a closing time in the past is refused');

    perform set_config('request.jwt.claim.sub', outsider, true);
    perform assert(blocked($q$ select public.create_poll('Sneaky?', array['A','B']) $q$),
                   'a non-member cannot create a poll');
end $$;

\echo ''
\echo '--- push notifications ---'
reset role;
set role authenticated;

do $$
declare
    member   constant text := '22222222-2222-2222-2222-222222222222';
    outsider constant text := '33333333-3333-3333-3333-333333333333';
    queued   int;
begin
    perform set_config('request.jwt.claim.sub', member, true);
    insert into public.device_tokens (token, user_id, environment)
    values ('token-member', member::uuid, 'production');

    perform assert((select count(*) from public.device_tokens) = 1,
                   'a member sees their own device token');
    -- Existing rows predate Android, so the default has to be iOS or every
    -- iPhone in the league silently stops being sent to.
    perform assert((select platform from public.device_tokens where token = 'token-member') = 'ios',
                   'a device registered without a platform is treated as iOS');
    perform assert(blocked($q$
        insert into public.device_tokens (token, user_id, platform)
        values ('bad', '22222222-2222-2222-2222-222222222222', 'windows-phone') $q$),
        'an unknown platform is refused');

    -- A device token is a push address. Another member holding it could
    -- send to that device, so the row must be invisible across users.
    perform set_config('request.jwt.claim.sub', outsider, true);
    perform assert((select count(*) from public.device_tokens) = 0,
                   'a member cannot see someone else''s device token');
    perform assert(blocked($q$
        insert into public.device_tokens (token, user_id)
        values ('stolen', '22222222-2222-2222-2222-222222222222') $q$),
        'a member cannot register a token against another user');
    perform assert(blocked($q$
        update public.notification_preferences set messages = false
        where user_id = '22222222-2222-2222-2222-222222222222' $q$)
        or (select count(*) from public.notification_preferences
             where user_id = '22222222-2222-2222-2222-222222222222'
               and messages = false) = 0,
        'a member cannot mute someone else''s notifications');

    -- With no push credentials in the vault, notify_push must return quietly
    -- rather than raising: a push outage cannot be allowed to reject a post.
    perform set_config('request.jwt.claim.sub', member, true);
    insert into public.league_messages (author_id, author_name, body)
    values (member::uuid, 'Member', 'Does an unconfigured push break posting?');
    perform assert((select count(*) from net.sent) = 0,
                   'no push is queued while push credentials are unset');
end $$;

-- Now with credentials present, so the trigger path itself is exercised.
reset role;
insert into vault.decrypted_secrets (name, decrypted_secret)
values ('push_function_url', 'https://example.test/functions/v1/push'),
       ('push_service_key',  'test-key');

set role authenticated;
do $$
declare
    member constant text := '22222222-2222-2222-2222-222222222222';
    sent   jsonb;
begin
    perform set_config('request.jwt.claim.sub', member, true);
    insert into public.league_messages (author_id, author_name, body)
    values (member::uuid, 'Member', 'Second message');

    perform assert((select count(*) from net.sent) = 1,
                   'posting a message queues exactly one push');

    select body into sent from net.sent order by id desc limit 1;
    perform assert(sent ->> 'kind' = 'messages',
                   'the queued push is tagged as a message');
    -- The author must not be notified about their own post.
    perform assert(sent ->> 'exclude_user' = member,
                   'the author is excluded from their own notification');
    perform assert(sent ->> 'body' = 'Second message',
                   'the message body is carried through to the notification');
end $$;

reset role;
delete from vault.decrypted_secrets;
delete from net.sent;

\echo ''
\echo '--- mentions ---'
reset role;

do $$
declare
    found int;
begin
    -- Second Member exists from the direct messages fixture below; create it
    -- here too so the two sections do not depend on each other's order.
    insert into auth.users (id, email)
    values ('44444444-4444-4444-4444-444444444444', 'second@example.com')
    on conflict do nothing;
    insert into public.profiles (id, display_name)
    values ('44444444-4444-4444-4444-444444444444', 'Second Member')
    on conflict do nothing;

    select count(*) into found
      from private.mentioned_users('hey @Second Member, look at this');
    perform assert(found = 1, 'a name after @ is recognised');

    select count(*) into found
      from private.mentioned_users('HEY @second member!!');
    perform assert(found = 1, 'matching ignores case');

    select count(*) into found
      from private.mentioned_users('Second Member said something');
    perform assert(found = 0, 'a name without an @ is not a mention');

    select count(*) into found from private.mentioned_users('nobody here');
    perform assert(found = 0, 'an ordinary message mentions nobody');
end $$;

\echo ''
\echo '--- direct messages ---'
reset role;

-- The second party to the conversation, created before any impersonation:
-- auth.users is not writable from a restricted role.
insert into auth.users (id, email)
values ('44444444-4444-4444-4444-444444444444', 'second@example.com')
on conflict do nothing;
insert into public.profiles (id, display_name)
values ('44444444-4444-4444-4444-444444444444', 'Second Member')
on conflict do nothing;

set role authenticated;

do $$
declare
    member   constant text := '22222222-2222-2222-2222-222222222222';
    outsider constant text := '33333333-3333-3333-3333-333333333333';
    other    constant uuid := '44444444-4444-4444-4444-444444444444';
begin
    perform set_config('request.jwt.claim.sub', member, true);
    insert into public.direct_messages (recipient_id, body) values (other, 'Just between us.');

    perform assert((select count(*) from public.direct_messages) = 1,
                   'the sender sees their own message');

    -- The whole point of the table.
    perform set_config('request.jwt.claim.sub', outsider, true);
    perform assert((select count(*) from public.direct_messages) = 0,
                   'a third member cannot read someone else''s conversation');

    perform assert(blocked($q$
        insert into public.direct_messages (sender_id, recipient_id, body)
        values ('22222222-2222-2222-2222-222222222222',
                '22222222-2222-2222-2222-222222222222', 'forged') $q$),
        'a member cannot send a message as somebody else');

    perform set_config('request.jwt.claim.sub', member, true);
    perform assert(blocked($q$
        insert into public.direct_messages (recipient_id, body)
        values ('22222222-2222-2222-2222-222222222222', 'talking to myself') $q$),
        'a member cannot message themselves');

    perform assert(blocked($q$
        update public.direct_messages set body = 'I never said that' $q$)
        or (select count(*) from public.direct_messages
             where body = 'I never said that') = 0,
        'a sender cannot edit a message after sending it');
end $$;

reset role;
delete from public.direct_messages;

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
