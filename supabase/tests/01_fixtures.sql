-- Two league members (one commissioner) and one outsider who signed up but was
-- never added to the league.

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema public to anon;

-- Two of the three are on the roster. The third signs up anyway, which is the
-- case the invite list exists to handle.
insert into public.league_invites (email, note) values
    ('commish@example.com', 'Commish'),
    ('member@example.com', 'Member');

insert into auth.users (id, email) values
    ('11111111-1111-1111-1111-111111111111', 'commish@example.com'),
    ('22222222-2222-2222-2222-222222222222', 'member@example.com'),
    ('33333333-3333-3333-3333-333333333333', 'outsider@example.com');

-- No profile is deleted here: the outsider never gets one, because the trigger
-- only creates profiles for invited addresses.

update public.profiles set is_commissioner = true
 where id = '11111111-1111-1111-1111-111111111111';

insert into public.news_posts (title, body, author_name, season)
values ('Week 1', 'Body', 'Commish', 2026);

with p as (
    insert into public.polls (id, question, season, created_by, created_by_name, closes_at)
    values ('aaaaaaaa-0000-0000-0000-000000000001', 'Who wins?', 2026,
            '11111111-1111-1111-1111-111111111111', 'Commish', now() + interval '1 day')
    returning id
)
insert into public.poll_options (id, poll_id, label, position)
select v.id, p.id, v.label, v.pos
from p, (values
    ('bbbbbbbb-0000-0000-0000-000000000001'::uuid, 'Bears', 0),
    ('bbbbbbbb-0000-0000-0000-000000000002'::uuid, 'Trap Game', 1)
) as v(id, label, pos);

-- A poll that has already closed, with an option that belongs only to it.
insert into public.polls (id, question, season, created_by, created_by_name, closes_at)
values ('aaaaaaaa-0000-0000-0000-000000000002', 'Closed one', 2026,
        '11111111-1111-1111-1111-111111111111', 'Commish', now() - interval '1 hour');

insert into public.poll_options (id, poll_id, label, position)
values ('bbbbbbbb-0000-0000-0000-000000000009',
        'aaaaaaaa-0000-0000-0000-000000000002', 'Too late', 0);
