# Getting the app to the league

Two platforms, two very different routes. Neither needs the other.

## Android

**Build the APK:**

```sh
cd android && ./gradlew assembleRelease
```

It lands at `android/app/build/outputs/apk/release/app-release.apk`, about
3.6 MB.

**Send it to the four Android members.** Email, Drive, AirDrop-equivalent —
anything. They tap it, Android asks them to allow installs from that app once,
and it installs. No store, no review, no expiry.

Do **not** put the APK in the GitHub repo: it is public, and the APK contains
the Supabase anon key. Row level security means that key cannot read league
data without a signed-in member, but the ESPN proxy currently accepts it (see
issue #15), so there is no reason to publish it.

**Updates** are the weak point: every new version has to be sent round again,
and `versionCode` in `android/app/build.gradle.kts` must go up or the install
is refused as a downgrade. If that becomes tiresome, Google Play's closed
testing track is $25 once and updates arrive on their own.

### The signing key

Lives at `~/.cartel/cartel-release.jks`, deliberately outside the repo, with
its password in `~/.cartel/keystore.properties`.

**Back both up somewhere safe.** Android identifies an app by its signature: a
build signed with a different key is a different app to the phone, so losing
this key means every member has to uninstall and reinstall to take an update —
and on Google Play it means you can never update the listing at all.

Release builds work without it; they just come out unsigned and will not
install.

## iOS

`./Scripts/archive.sh` builds, signs, and uploads to App Store Connect. It
refuses to upload if the push entitlement is missing, because that failure is
otherwise invisible until nobody gets a notification.

Then, in App Store Connect:

1. TestFlight → wait for the build to finish processing
2. Your external group → **Builds** → **+** → pick the new build
3. Fill in "What to Test"
4. Submit for Beta App Review — usually under a day

Testers update from the TestFlight app once it is approved.

**Builds expire 90 days after upload.** `.github/workflows/testflight-expiry.yml`
reads `.testflight/last-upload.json` and warns before that happens, because the
alternative is eleven people finding out at once.

## What the league sees on first launch

Signed out, they get league news, player news, matchups, standings and the
roster. Signing in — Settings → email → 6-digit code — unlocks polls and the
league thread, and only addresses on the invite list get a profile.

Tell them to check the junk folder for the sign-in email. Without a domain
there is no SPF record, so it frequently lands there.
