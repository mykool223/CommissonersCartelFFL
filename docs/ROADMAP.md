# Roadmap

Rough order, most useful first. Nothing here is committed to a date.

## Android

Built and working against the live league: News (league and player), Matchups
with NFL scores, Polls (vote and create), Members by division with bios and the
league thread, and Settings with sign-in and notification preferences.

Nothing server-side had to change — the same migrations, the same row level
security, the same proxy.

Left to do:

- **Push** needs a Firebase project; the client and the server are both ready
  and inert until `google-services.json` exists. See
  [PUSH_NOTIFICATIONS.md](PUSH_NOTIFICATIONS.md#android).
- **Sign-in is unverified end to end.** The flow is written and compiles, but
  testing it means sending a real email to a real member, so it has not been
  exercised.
- **Weekly awards and recaps** are not ported yet.
- **Release signing** is not set up, so there is a debug APK and no release one.

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
