# Architecture

## The shape of it

```
SwiftUI views
     │  read state from
     ▼
@Observable view models        (one per screen, @MainActor)
     │  call protocols on
     ▼
AppEnvironment                 (dependency container)
     │  holds
     ├── any LeagueDataSource ──► ESPNClient      or  MockLeagueDataSource
     └── any ContentRepository ─► SupabaseContent  or  MockContentRepository
```

Two protocols, defined in `CartelCore/Services.swift`, are the only thing the
UI knows about:

- **`LeagueDataSource`** — league, managers, teams, matchups. Read-only. ESPN
  owns this data.
- **`ContentRepository`** — news, recaps, polls, votes. Read and write. We own
  this data.

Nothing in `App/` imports a concrete client. That's what makes the mock mode
work, and it's why the tests need no network.

## Why the split between ESPN and Supabase

ESPN already knows every score, roster and standing, and it recomputes them
correctly every week. Copying that into our own database would mean writing a
sync job and then debugging it every time it drifted. So we don't store any of
it — we read it live and cache for two minutes.

What ESPN has no concept of is a league that writes things: a weekly column, a
recap under a specific matchup, an argument settled by poll. That's the part
that needs a real database, and it's all Supabase holds.

The dividing line is ownership: **if ESPN computes it, we read it; if the league
writes it, we store it.**

## One ESPN request feeds every screen

`ESPNClient` is an actor. A single request with `view=mSettings&view=mTeam&
view=mMatchupScore` returns settings, teams, members and the full season
schedule in one payload, so all four protocol methods are served from it.

Two things fall out of that:

- **Concurrent callers share one request.** Five screens appearing at once
  produce one network call, not five, because the in-flight `Task` is stored
  and awaited rather than restarted.
- **The cache is per-payload, not per-endpoint.** A two-minute TTL keeps us
  well inside ESPN's rate limits. Pull-to-refresh calls `invalidateCache()`.

## Loading state

Every async screen uses `Loadable<Value>`: `idle`, `loading`, `loaded`,
`failed`. `LoadableView` renders the four-way switch once so no screen
reimplements it.

Two details that matter:

- Pull-to-refresh passes `showSpinner: false`, so refreshing keeps the current
  content on screen instead of flashing back to a spinner.
- A cancelled task returns `nil` from `loadState` and the state is left alone.
  Otherwise navigating away mid-load would blank the screen you came back to.

`loadState` returns a value rather than taking `inout` state, because passing an
actor-isolated stored property as `inout` to an `async` function is rejected
under Swift 6 concurrency — the call can suspend and let something else write
to the property mid-update.

## Errors

Everything funnels into `CartelError`, so views switch over one type. The
transport layer wraps `URLError` into `.transport`; ESPN 401/403 becomes
`.notAuthorized` rather than a bare status code, because the recovery step is
different — the user needs to fix credentials, not retry.

`ErrorStateView` maps each case to a title, an SF Symbol and a retry button.

## Concurrency

`CartelKit` builds clean under **full Swift 6 language mode**. Models are
`Sendable` value types; the two stateful types (`ESPNClient`,
`MockContentRepository`) are actors; view models are `@MainActor`.

The **app target** is also on full Swift 6 language mode, with
`SWIFT_STRICT_CONCURRENCY = complete`. It compiles with zero concurrency
warnings. Don't drop `SWIFT_VERSION` back to `5.0` for convenience — that
silently downgrades every data-race error to a warning.

## Testing strategy

Tests live in the package, not the app target, so they run in about two seconds
with no simulator.

The seam that makes this work is `HTTPTransport` — a protocol with exactly one
method. `URLSessionTransport` is the real one; `StubTransport` replays saved
JSON. `Tests/CartelESPNTests/Fixtures/league.json` is a realistic ESPN payload,
including the awkward parts: a team with the legacy `location` + `nickname`
naming, a team with no record at all, and a bye matchup with no away side.

`ESPNClient` also takes a `now:` closure, so cache expiry is tested by advancing
a fake clock rather than sleeping.

What is **not** covered: the SwiftUI views. There are no snapshot tests. Every
view has `#Preview` blocks including failure states
(`AppEnvironment.previewFailing()`), which is the practical substitute.

## Security

Three different kinds of value, treated three different ways:

| Value | Where it lives | Why |
|---|---|---|
| ESPN league id | `Config/Secrets.xcconfig` → Info.plist | Not secret; it's in the league URL |
| Supabase anon key | `Config/Secrets.xcconfig` → Info.plist | Public by design; RLS is the protection |
| ESPN session cookies | iOS Keychain, or Supabase secrets | Credentials for a real ESPN account |

The ESPN cookies are the only genuinely sensitive ones. Two options, both
supported:

1. **Keychain** — the commissioner pastes them into Settings. Simple, and they
   never leave the device.
2. **`espn-proxy` edge function** — the cookies live in Supabase's secret store
   and the app never sees them. Use `ESPNConfiguration.viaProxy(...)`. This is
   the better answer if the app is ever distributed beyond you.

Supabase row level security is written so the anon key alone gets you nothing:
you must be a signed-in member to read, and only commissioners can publish.

Poll results are protected at the database level, not just in the UI. Members
can select only their *own* row from `poll_votes`; tallies come from the
`security definer` function `polls_with_results`. Hiding results in the view
alone would be bypassable by anyone with the anon key and curl.

All writes to `poll_votes` go through `cast_vote()`, which enforces the closing
time and that the option belongs to the poll. No insert or update policy exists
on the table, so that path can't be skipped.

## Things deliberately not done

- **No `supabase-swift` dependency.** The app makes selects and two RPCs; plain
  `URLSession` against PostgREST covers it with zero dependency churn and a
  fast CI. If realtime poll updates become worth it, replace `SupabaseClient`
  and nothing above `SupabaseContentRepository` changes.
- **No offline persistence.** Two-minute caching, and that's it. Worth adding
  when there's a reason.
- **No architecture framework.** `@Observable` view models and protocols are
  enough at this size.
