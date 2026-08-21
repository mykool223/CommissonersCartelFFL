# Supabase setup

Supabase stores everything the league writes: news posts, matchup recaps, polls
and votes. It does **not** store scores, rosters or standings — those are read
live from ESPN.

## Cost

The free tier is genuinely enough, and it stays free. As of August 2026:

| | Free | What this league needs |
|---|---|---|
| Database | 500 MB | Text posts and votes. Thousands of seasons' worth. |
| Egress | 5 GB/month | Twelve people checking a few times a day is a rounding error. |
| Monthly active users | 50,000 | Twelve. |
| Projects | 2 active | One. |

Paid ("Pro") starts at **$25/month** and buys headroom this league will never
need. Don't.

**The one catch: free projects pause after 1 week of inactivity.** That matters
here more than it would for most apps, because a fantasy league is seasonal —
heavy use September to January, then silence. Left alone the project pauses in
February, and whoever opens the app in September finds it dead until someone
restores it by hand from the dashboard.

`.github/workflows/keep-supabase-awake.yml` handles it: one query a week, which
counts as activity. It runs on Ubuntu so it costs nothing, and it no-ops
quietly until you add the two secrets. To turn it on, go to **Settings →
Secrets and variables → Actions** in GitHub and add:

- `SUPABASE_URL` — the full `https://…supabase.co` URL
- `SUPABASE_ANON_KEY` — the same anon key the app uses

## Check it before you deploy it

The schema is tested. Run this before touching your real project:

```bash
brew install postgresql@17     # once
./Scripts/test-database.sh
```

It spins up a throwaway Postgres, applies every migration, and asserts the
security properties the app depends on — that non-members see nothing, that
re-voting cannot inflate a tally, that `anon` cannot reach the RPCs. No account
and no network needed. CI runs the same script on every push.

## 1. Create the project

1. Sign up at [supabase.com](https://supabase.com) and create a project.
2. **Project Settings → API** gives you two values:
   - **Project URL** — `https://abcdefghijkl.supabase.co`
   - **anon / public key** — a long JWT

Put them in `Config/Secrets.xcconfig`:

```
SUPABASE_HOST = abcdefghijkl.supabase.co
SUPABASE_ANON_KEY = eyJhbGciOi...
```

Note the host has **no `https://`**. An xcconfig treats `//` as the start of a
comment, so the scheme would be silently eaten. `AppConfiguration` adds it back.

> The anon key is meant to be public — it identifies the project, it doesn't
> grant access. Row level security is what protects the data. Never put the
> **service role** key in the app; it bypasses RLS entirely.

## 2. Apply the schema

Install the CLI and push the migrations:

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref <your-project-ref>
supabase db push
```

That creates six tables, the row level security policies, and two functions.

Prefer clicking? Paste each file in `supabase/migrations/` into the SQL Editor
in order. They're numbered.

## 3. Make yourself a member

Every policy requires a row in `public.profiles`. That row is created
automatically when someone signs up, by the `on_auth_user_created` trigger.

Sign up through the app (or **Authentication → Users → Add user** in the
dashboard), then promote yourself in the SQL Editor:

```sql
update public.profiles
set is_commissioner = true,
    display_name    = 'Michael Smith',
    espn_swid       = '{YOUR-ESPN-SWID}'
where id = (select id from auth.users where email = 'you@example.com');
```

`espn_swid` links your Supabase account to your ESPN member record, so the app
can tell which team is yours. Find it in the Members tab or in the raw ESPN
payload.

Without a profile row you'll get empty screens rather than errors — that's RLS
working as intended.

## 4. Publish something

```sql
insert into public.news_posts (title, body, author_name, week, season, published_at)
values (
    'Week 1 is live',
    E'Good luck everyone.\n\nSet your lineups.',
    'Michael Smith',
    1,
    2025,
    now()
);
```

Pull to refresh the News tab.

A poll needs two statements — the poll, then its options:

```sql
with new_poll as (
    insert into public.polls (question, season, week, created_by_name, closes_at)
    values ('Who wins it all?', 2025, 11, 'Michael Smith', now() + interval '3 days')
    returning id
)
insert into public.poll_options (poll_id, label, position)
select new_poll.id, label, position
from new_poll,
     (values ('Bear Necessities', 0), ('Trap Game', 1), ('Anyone else', 2))
         as options(label, position);
```

## The schema

| Table | Holds |
|---|---|
| `profiles` | One row per member, mirroring `auth.users`. Carries `is_commissioner` and `espn_swid`. |
| `news_posts` | Commissioner posts. Indexed on `(season, published_at desc)`. |
| `recaps` | Written recaps, optionally tied to an ESPN `matchup_id`. |
| `polls` | The question, season, week and closing time. |
| `poll_options` | Choices, ordered by `position`. |
| `poll_votes` | One row per member per poll. |

Two constraints do real work:

- `poll_votes` is keyed on `(poll_id, voter_id)` — **one vote per person per
  poll**. Changing your mind is an UPDATE, not a second row, so a tally can't be
  inflated by re-voting.
- `poll_votes` has a composite foreign key on `(option_id, poll_id)`, which
  makes voting for an option that belongs to a *different* poll impossible at
  the database level.

## How access control works

Every table has RLS enabled. The rules:

- **Reading anything requires a profile row.** Not signed in, or signed in
  without a profile, means you see nothing.
- **Only commissioners publish** news and recaps.
- **Any member can start a poll**; authors and commissioners can edit or delete
  their own.
- **Members can read only their own vote.**

That last one is the subtle one. Poll tallies come from
`polls_with_results()`, a `security definer` function. If members could select
freely from `poll_votes`, "results hidden until you vote" would be a UI
convention that anyone with the anon key and curl could read straight past.

Similarly, `poll_votes` has **no insert or update policy at all**. Every write
goes through `cast_vote()`, which checks that the poll exists, isn't closed, and
that the option belongs to it. There's no path around those checks.

## The two functions

**`polls_with_results(p_season int)`** returns each poll with its options, vote
counts, and which option you picked — one round trip instead of three queries
that would still race each other.

**`cast_vote(p_poll_id uuid, p_option_id uuid)`** records a vote, replacing any
previous one via `on conflict ... do update`.

Both are restricted to the `authenticated` role; `anon` has execute revoked.

## Local development

```bash
supabase start          # local Postgres + Studio on :54323
supabase db reset       # apply migrations/ then seed.sql
```

Point the app at `127.0.0.1:54321` and use the local anon key that
`supabase start` prints.

## The ESPN proxy function

`supabase/functions/espn-proxy` is optional, and only relevant for a **private**
ESPN league. It holds the ESPN cookies as server-side secrets so they never ship
in the app binary.

```bash
supabase secrets set ESPN_S2='...' ESPN_SWID='{...}'
supabase functions deploy espn-proxy
```

See [ESPN_API.md](ESPN_API.md) for when this is worth doing.

## A bug this testing already caught

The migrations originally ended with:

```sql
revoke execute on function public.polls_with_results(int) from anon;
```

That line does nothing. Postgres grants `EXECUTE` on new functions to `PUBLIC`
by default, and every role inherits from `PUBLIC` — so `anon` kept the grant
and the revoke was silently a no-op. It has to name `PUBLIC`:

```sql
revoke execute on function public.polls_with_results(int) from public;
```

It was never exploitable, because both functions also guard themselves
internally. But the defence-in-depth layer the comment claimed simply was not
there. `Scripts/test-database.sh` now asserts it, so it cannot come back.

## Troubleshooting

**Empty screens, no error.** Almost always a missing `profiles` row — RLS
returns zero rows rather than an error. Check step 3.

**401 / "Can't reach your league".** The anon key is wrong or truncated, or
you're not signed in and the policy requires it.

**`permission denied for function`.** The migration in
`20250101000002_functions.sql` revokes execute from `anon`. You need to be
signed in.

**Posts don't appear.** Check `season` matches what the app is asking for. The
app derives the season from today's date, rolling over in March — so in January
2026 it asks for the 2025 season.
