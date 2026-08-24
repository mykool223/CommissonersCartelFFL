# The Cartel, on Android

Kotlin and Jetpack Compose, talking to the same Supabase project and the same
`espn-proxy` edge function as the iOS app. No server-side difference between
the two clients.

## Running it

```sh
cp secrets.properties.example secrets.properties   # then fill in
./gradlew assembleDebug
```

Or open the `android/` folder in Android Studio.

The build succeeds **without** `secrets.properties` — the app then says it is
unconfigured rather than failing to launch, so a fresh clone runs. CI builds in
exactly that state on purpose.

## What is here

| Tab | State |
|---|---|
| News | League news and player news |
| Matchups | Fixtures for the current week, plus live NFL scores |
| Polls | Vote and create |
| Members | Roster by division, bios, and the league thread |
| Settings | Sign-in, notification preferences |

## Things that will trip you up

**The Kotlin plugin is deliberately absent.** AGP 9 has Kotlin support built in
and fails the build if `org.jetbrains.kotlin.android` is also applied. Every
tutorial still tells you to add it.

**No ESPN credentials live here.** The proxy holds `espn_s2` and `SWID`
server-side, so unlike iOS there is nothing to paste into Settings and the
private league works on a fresh install.

**Firebase is optional.** The `google-services` plugin is applied only when
`app/google-services.json` exists, because it fails the build outright when it
does not. Push is inert until then; everything else works.

**`Config.currentSeason()` duplicates `Season.current()` from CartelCore.** The
two have to agree or the platforms show different content from one database.
ESPN rolls over in June. There is a test.

## Distribution

Google Play is $25 once, against Apple's $99 a year — and for a twelve-person
league an APK can simply be handed out: no store, no review, and none of
TestFlight's 90-day expiry.

```sh
./gradlew assembleRelease   # needs a signing config first
```
