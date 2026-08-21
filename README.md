# Commissioners Cartel

[![CI](https://github.com/mykool223/CommissonersCartelFFL/actions/workflows/ci.yml/badge.svg)](https://github.com/mykool223/CommissonersCartelFFL/actions/workflows/ci.yml)

An iOS app for our fantasy football league — weekly news, matchup recaps,
league polls, and who's who.

Rosters and scores come from ESPN. Everything the league writes itself — posts,
recaps, polls, votes — lives in Supabase.

> **It runs before you configure anything.** With no ESPN league id and no
> Supabase project, the app boots on realistic sample data and every screen
> works. Wire up the real backends when you're ready.

## Getting started

You need **Xcode 16 or later**. (Command Line Tools alone can build the shared
package, but not the app.)

```bash
git clone https://github.com/mykool223/CommissonersCartelFFL.git
cd CommissonersCartelFFL
open CommissionersCartel.xcodeproj
```

Press **⌘R**. That's it — the app runs on sample data.

To connect the real league:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# fill in your ESPN league id and Supabase project details
```

Then see [docs/ESPN_API.md](docs/ESPN_API.md) and
[docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md).

## Layout

```
App/CommissionersCartel/     The iOS app — SwiftUI only
  App/                       Entry point, DI container, config, Keychain
  Features/                  One folder per tab: News, Matchups, Polls, Members, Settings
  DesignSystem/              Shared components, theme, formatters
  Resources/                 Assets and Info.plist

Packages/CartelKit/          Local Swift package — all the logic worth testing
  Sources/CartelCore/          Models, service protocols, mock data
  Sources/CartelESPN/          ESPN fantasy API client
  Sources/CartelSupabase/      PostgREST client and content repository
  Tests/                       56 tests, no network required

supabase/
  migrations/                Schema, row level security, RPCs
  functions/espn-proxy/      Edge function that keeps ESPN cookies server-side
  seed.sql                   Local development data

Config/                      Build settings and secrets (xcconfig)
Scripts/                     generate.sh, test-package.sh
docs/                        Architecture and setup guides
project.yml                  Source of truth for the Xcode project
```

### Why the logic lives in a package

Anything worth testing sits in `CartelKit` rather than the app target, so it
builds and tests in about two seconds from the command line with no simulator
and no Xcode. The app target is deliberately thin: SwiftUI views and view models
that call protocols.

That split is also what lets every screen run on mock data. Views depend on
`LeagueDataSource` and `ContentRepository`, never on ESPN or Supabase directly.

## Common tasks

| Task | Command |
|---|---|
| Run the shared package's tests | `./Scripts/test-package.sh` |
| Check the database schema and its security rules | `./Scripts/test-database.sh` |
| Regenerate the Xcode project | `./Scripts/generate.sh` |
| Apply database migrations | `supabase db push` |
| Preview the news ingest without writing | `DRY_RUN=1 ./Scripts/ingest_news.py` |
| Deploy the ESPN proxy | `supabase functions deploy espn-proxy` |
| Lint | `swiftlint` |

Work happens on `dev`; `main` is the stable branch. See
[CONTRIBUTING.md](CONTRIBUTING.md#branches).

**Edit `project.yml`, not the `.xcodeproj`.** The project file is committed so
the repo opens without extra tooling, but it's generated. CI fails a PR where
the two have drifted.

## Testing

```bash
./Scripts/test-package.sh
```

The script exists because `swift test` can't find swift-testing when only
Command Line Tools are installed — it adds the framework search paths by hand.
With full Xcode, plain `swift test` and ⌘U both work.

To run the package tests inside Xcode, add them once via **Product → Scheme →
Edit Scheme → Test → +**. They aren't wired in by default because the
XcodeGen key that does it crashes the current release (see the note in
`project.yml`).

## Status

Everything below is built and working against sample data. The ESPN and
Supabase clients are fully implemented and unit-tested, but have only been
exercised against fixtures — you'll be the first to point them at a real
league.

- [x] News feed and post detail
- [x] Weekly matchups with inline recaps
- [x] Polls with optimistic voting
- [x] League members and manager detail
- [x] Settings with Keychain-stored ESPN credentials
- [x] League crest as the app icon, and brand gold throughout
- [x] Launch screen — native, so there's no white flash before the crest
- [x] "Around the league" — daily headlines from The Fantasy Footballers' RSS feed
- [ ] Writing posts and polls from inside the app (read-only today)
- [ ] Sign-in — see [docs/ROADMAP.md](docs/ROADMAP.md)
- [ ] Push notifications

See [docs/ROADMAP.md](docs/ROADMAP.md) for what's next and why.

## A note for visitors

This is a private league's app, built for one specific ESPN league. It's public
because the ESPN and Supabase plumbing may be useful to someone doing the same
thing — `Packages/CartelKit` is self-contained and has no ties to this league.

Issues and PRs are welcome but this isn't a supported project, so no promises
on response time.

## License

MIT — see [LICENSE](LICENSE).
