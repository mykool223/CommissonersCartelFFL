# Roadmap

Rough order, most useful first. Nothing here is committed to a date.

## Next: sign-in

Everything else is blocked on this. Today the app talks to Supabase with the
anon key and no session, which means **row level security returns nothing** —
that's why the News and Polls tabs run on mock data until you're authenticated.

The plan:

- Magic-link email auth (a 12-person league doesn't need passwords)
- A `SupabaseAuth` type wrapping the GoTrue REST endpoints, matching how
  `SupabaseClient` already wraps PostgREST
- Store the refresh token in the Keychain — `KeychainStore` already exists
- Feed the access token into `SupabaseClient`'s existing `accessToken` closure,
  which is already threaded through and used on every request

The client seam is already in place; this is mostly the auth flow and a sign-in
screen.

## Then: writing content from the app

The app is read-only today — posts and polls are created in the Supabase SQL
editor, which is fine for the commissioner and no good for anyone else.

- Compose a news post (commissioner only)
- Create a poll with options
- Write a recap from a matchup, pre-filled with the two team names
- `ContentRepository` grows write methods; RLS already allows all of this

## Push notifications

The obvious moments: a new post, a poll opening, a poll about to close, and
Sunday's final scores.

Needs an Apple Developer account, APNs keys, and a Supabase edge function
triggered on insert. Worth doing once people actually use the app.

## Smaller things worth doing

- **Standings tab** — the data is already fetched and `TeamRecord` already
  sorts correctly. It's a view.
- **Weekly awards** — highest score, biggest blowout, closest game, worst
  start/sit. All computable from `[Matchup]` with no new data.
- **Rosters** — add `view=mRoster` to `ESPNClient.views` and a `Player` model.
- **Head-to-head history** — needs multi-season fetching; ESPN uses a different
  path (`/leagueHistory/{id}?seasonId=`) for past seasons.
- **Comments on posts** — a table, a policy, and a view.
- **Poll results by member** — currently deliberately hidden. Would need the
  RLS policy on `poll_votes` relaxed, which is a league decision more than a
  technical one.

## Known gaps

- **No snapshot tests.** Views are covered only by `#Preview`, including
  failure states via `AppEnvironment.previewFailing()`.
- **App target is Swift 5 language mode.** `CartelKit` is fully Swift 6. To
  finish: set `SWIFT_VERSION: "6.0"` in `project.yml` and fix the warnings
  that `SWIFT_STRICT_CONCURRENCY = complete` is already surfacing.
- **No offline persistence.** Two-minute in-memory cache and nothing else.
- **ESPN client is unproven against a live league.** It's tested thoroughly
  against a realistic fixture, but fixtures only cover the shapes we thought
  of. Expect to touch `ESPNDTOs.swift` the first time you point it at your
  real league.
- **No app icon.** `AppIcon.appiconset` is an empty placeholder.
