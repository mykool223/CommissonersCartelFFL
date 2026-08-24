# Roadmap

Rough order, most useful first. Nothing here is committed to a date.

## Next: an Android app

Four or more of the twelve are on Android, which is too many to leave out.

**Nothing server-side has to change.** The 15 migrations, row level security,
the invite allowlist, magic-link auth, the ESPN proxy, the push trigger, the
bios and the polls are all plain Postgres and HTTP. An Android client talks to
the identical backend. The groundwork that *was* needed is already done:
`device_tokens.platform` exists and `supabase/functions/push` sends through
Firebase as well as APNs.

What has to be built, in Kotlin and Jetpack Compose:

- The five tabs (News, Matchups, Polls, Members, Settings), member detail, the
  league thread, poll voting and creation
- Supabase's official Kotlin SDK replaces most of `CartelSupabase` by hand
- An ESPN client — a port of `CartelESPN`, keeping the quirks it documents:
  SVG logos that will not decode, `playoffSeed = 0` meaning "no seed yet",
  timestamps that arrive without seconds
- `EncryptedSharedPreferences` where iOS uses the Keychain
- An intent filter for the magic-link callback
- Firebase Cloud Messaging registration, writing `platform = 'android'`

It is a rewrite of the client, not a redesign: every product decision is
already made and every backend contract is already fixed.

**Distribution is easier than iOS.** Google Play is $25 once rather than $99 a
year, and for twelve people an APK can be handed out directly — no store, no
review, and none of TestFlight's 90-day expiry.

**Prerequisites:** Android Studio, and a Firebase project for push (both free).
See [PUSH_NOTIFICATIONS.md](PUSH_NOTIFICATIONS.md#android).

## Done

- **Sign-in** — magic link plus a 6-digit code, sessions in the Keychain,
  restricted to an invite list of league email addresses
- **Writing content from the app** — members create polls; the league thread
  is read/write. Composing news posts from the app is still open (issue #6)
- **Push notifications** — league messages, news and polls, fired by database
  triggers so a hand-written insert notifies everyone too. Needs an APNs key
  before anything is delivered
- **Weekly awards, NFL scores, team bios, divisions, team logos**

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
- **No offline persistence.** Two-minute in-memory cache and nothing else.
- **ESPN client is unproven against a live league.** It's tested thoroughly
  against a realistic fixture, but fixtures only cover the shapes we thought
  of. Expect to touch `ESPNDTOs.swift` the first time you point it at your
  real league.
- **The crest is used at a single size.** iOS 18 supports dark and tinted
  icon variants; only the standard one is provided. A version of the artwork
  with a transparent background would also let the crest sit on a light
  surface without its black field.
