# Contributing

It's a league app — keep it simple.

## Setup

Xcode 16 or later.

```bash
open CommissionersCartel.xcodeproj
```

⌘R runs on sample data with no configuration.

## Branches

- **`dev`** — the default branch, and where work lands. Feature branches merge
  here, and PRs target it automatically.
- **`main`** — stable. Merge `dev` into it when the app is in a state you'd be
  happy to install on your phone and leave there.

```bash
git switch dev && git pull
git switch -c fix-bye-week-crash
# ... work ...
git push -u origin fix-bye-week-crash
gh pr create            # targets dev automatically
```

The two branches are protected differently on purpose:

| | `dev` | `main` |
|---|---|---|
| Force-push / delete | blocked | blocked |
| CI must be green | no — it runs and reports | **yes** |

`dev` is allowed to be briefly broken; that's what it's for. `main` is not.
Both rules can be bypassed by a repo admin, so a direct push still works — you
just get a `Bypassed rule violations` warning in the push output telling you
that you did it.

## Before you open a PR

```bash
./Scripts/test-package.sh     # the shared package's tests
swiftlint                     # optional: brew install swiftlint
```

Build and actually open the screens you changed, in both light and dark mode.

## The one rule that will bite you

**Edit `project.yml`, never the `.xcodeproj` directly.**

The project file is committed so the repo opens without extra tooling, but it's
generated. After changing the spec:

```bash
./Scripts/generate.sh
```

and commit the result. CI fails a PR where the two have drifted.

## Where things go

| Change | Where |
|---|---|
| New screen | `App/CommissionersCartel/Features/<Name>/` |
| Shared component | `App/CommissionersCartel/DesignSystem/` |
| Model or protocol | `Packages/CartelKit/Sources/CartelCore/` |
| ESPN parsing | `Packages/CartelKit/Sources/CartelESPN/` |
| Database change | a new file in `supabase/migrations/` |

Logic worth testing belongs in `CartelKit`, not the app target — that's what
keeps the test suite running in seconds without a simulator.

Never edit an existing migration that's been applied. Add a new one.

## Style

Match what's already there. A few conventions worth stating:

- Views depend on `LeagueDataSource` / `ContentRepository`, never on `ESPNClient`
  or `SupabaseClient` directly.
- Comments explain *why*, not *what*. If a line handles a quirk — ESPN's naming
  change, a bye week with no away side — say so.
- Every ESPN payload field is optional until proven otherwise.
- New screens get a `#Preview`, and an error preview if they can fail.

## Secrets

`Config/Secrets.xcconfig` is gitignored. If you're adding a new configuration
value, add it to `Secrets.example.xcconfig` too, with a comment on where to find
it.

Never commit ESPN cookies. They're credentials for a real ESPN account.
