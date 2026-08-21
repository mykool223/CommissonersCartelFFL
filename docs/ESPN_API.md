# Connecting to ESPN

ESPN has **no official public fantasy API**. The endpoint this app uses is the
one their own web client calls. It works well, it's read-only, and it's used by
most third-party fantasy tools — but it is undocumented and can change without
warning. Plan for that (see [When it breaks](#when-it-breaks)).

## Find your league id

Open your league on the web. The URL looks like:

```
https://fantasy.espn.com/football/league?leagueId=1234567&seasonId=2025
                                                  ^^^^^^^
```

Put that in `Config/Secrets.xcconfig`:

```
ESPN_LEAGUE_ID = 1234567
```

Rebuild. If your league is **public**, you're finished — the Matchups and
Members tabs will show real data.

## Private leagues

Most leagues are private, which means requests need two cookies from a logged-in
ESPN account: `espn_s2` and `SWID`.

**These are session credentials for a real ESPN account, not an API key.**
Anyone holding them can act as that account. Treat them like a password.

### Getting the cookies

1. Sign in to ESPN in a desktop browser.
2. Open developer tools (⌥⌘I in Safari or Chrome).
3. **Application** (Chrome) or **Storage** (Safari) → Cookies → `espn.com`.
4. Copy the values of `espn_s2` and `SWID`.

`SWID` looks like `{1A2B3C4D-...}` — braces included. The app adds them if you
leave them off.

### Option 1: Keychain (simplest)

Open **Settings** in the app, paste both values, tap **Save credentials**. They
go into the iOS Keychain and never leave the device.

Good for a personal build. The weakness: the cookies are on-device, so this
doesn't scale to distributing the app to your whole league.

### Option 2: The proxy function (better)

`supabase/functions/espn-proxy` holds the cookies server-side. The app sends its
Supabase token; the function attaches the ESPN cookies and forwards the request.
The cookies are never in the app binary.

```bash
supabase secrets set ESPN_S2='...' ESPN_SWID='{...}'
supabase functions deploy espn-proxy
```

Then build the client with `ESPNConfiguration.viaProxy(...)` instead of passing
credentials directly. The proxy preserves ESPN's exact path shape, so only the
base URL changes.

The function only forwards paths matching the league endpoint and only accepts
known `view` parameters — otherwise it would be an open relay to any ESPN URL a
caller chose.

### Cookies expire

`espn_s2` is a session cookie and will eventually stop working. The symptom is
every ESPN-backed screen showing "This league is private. Add your ESPN
credentials in Settings." Repeat the steps above to refresh it.

## The endpoint

```
GET https://lm-api-reads.fantasy.espn.com
    /apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{leagueId}
    ?view=mSettings&view=mTeam&view=mMatchupScore
```

Two things that are easy to get wrong:

- **`view` must be repeated**, not comma-joined. `?view=mTeam&view=mSettings`
  returns everything; `?view=mTeam,mSettings` returns a partial payload with no
  error.
- **Use `lm-api-reads.fantasy.espn.com`.** The older `fantasy.espn.com` host
  still works but is slower and rate-limited harder.

Useful views:

| View | Contains |
|---|---|
| `mSettings` | League name, scoring, schedule length |
| `mTeam` | Team names, logos, owners, records |
| `mMatchupScore` | Weekly scores (light) |
| `mMatchup` | Weekly scores plus per-player detail (heavy) |
| `mRoster` | Current rosters |
| `mStandings` | Standings |
| `mBoxscore` | Full box score for a scoring period |

The app requests the first three. Adding a view means editing
`ESPNClient.views` and extending `ESPNLeagueResponse`.

## Payload quirks the client already handles

These are the ones that bit us, all covered by tests against
`Tests/CartelESPNTests/Fixtures/league.json`:

- **Team names changed shape.** Seasons from roughly 2023 return a single
  `name`. Older seasons split it into `location` + `nickname`. Both are mapped;
  a team with neither falls back to `Team {id}`.
- **Owners are sometimes `owners[]`, sometimes `primaryOwner`.** Co-owned teams
  have several. The mapper checks both.
- **Bye matchups have no `away` side.** Odd-numbered leagues produce these.
  `Matchup.away` is optional for exactly this reason.
- **`winner` is `"UNDECIDED"` until a game is final.** Don't infer a winner from
  scores alone — an in-progress game has real points on both sides.
- **`currentMatchupPeriod` runs past the season end.** Clamp it.
- **Almost every field can be missing.** Every DTO property is optional and
  mapping happens in one place, `ESPNMapper`.

## Rate limiting

ESPN doesn't publish limits, but aggressive polling gets you throttled. The
client caches each payload for two minutes and coalesces concurrent callers into
a single request. Raise `ESPNConfiguration.cacheTTL` if you add polling.

## When it breaks

ESPN changes this payload occasionally. The failure shows up as
`CartelError.decoding` — "ESPN's payload didn't match what we expected."

To debug:

1. Fetch the raw payload yourself:
   ```bash
   curl -s 'https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/2025/segments/0/leagues/1234567?view=mTeam' \
     -H 'Cookie: espn_s2=...; SWID={...}' | python3 -m json.tool | head -60
   ```
2. Compare against `ESPNLeagueResponse` in `Sources/CartelESPN/ESPNDTOs.swift`.
3. Update the DTO and `ESPNMapper`, and add the new shape to the fixture so the
   regression is covered.

Because everything is behind `LeagueDataSource`, a breaking ESPN change touches
two files and no UI code.
