-- Local development seed data. Applied by `supabase db reset`.
--
-- Deliberately does NOT create auth users — sign up through the app so the
-- on_auth_user_created trigger runs. After signing up, promote yourself:
--
--   update public.profiles set is_commissioner = true where id = auth.uid();
--
-- The rows below have no author_id, which is allowed: author_name carries the
-- byline so content survives an account being deleted.

insert into public.news_posts (title, body, author_name, week, season, published_at)
values
    (
        'Week 10 Power Rankings',
        E'Bear Necessities moved to 8-2 and now holds the league''s best point differential by more than eighty points.\n\nThe interesting race is for the last two playoff spots.',
        'The Commissioner',
        10,
        2025,
        now() - interval '2 days'
    ),
    (
        'Reminder: Playoff Seeding Tiebreakers',
        E'Head-to-head record comes first, then total points for, then points against.',
        'The Commissioner',
        null,
        2025,
        now() - interval '9 days'
    );

insert into public.recaps (season, week, matchup_id, headline, body, author_name)
values (
    2025,
    10,
    1001,
    'Bears survive a scare',
    'Up thirteen with one player left, Bear Necessities watched Trap Game''s tight end put up nineteen in the fourth quarter.',
    'The Commissioner'
);

-- A poll with options, wired up in one statement so the ids stay consistent.
with new_poll as (
    insert into public.polls (question, season, week, created_by_name, closes_at)
    values ('Who wins it all this year?', 2025, 11, 'The Commissioner', now() + interval '3 days')
    returning id
)
insert into public.poll_options (poll_id, label, position)
select new_poll.id, label, position
from new_poll,
     (values ('Bear Necessities', 0), ('Trap Game', 1), ('Kickin'' It', 2), ('Literally anyone else', 3))
         as options(label, position);
