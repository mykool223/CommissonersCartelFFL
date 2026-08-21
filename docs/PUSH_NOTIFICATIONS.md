# Push notifications

Members are notified when someone posts in the league thread, when league news
is published, and when a new poll opens.

Nothing is sent from a phone. A database trigger fires on insert, so a post
notifies the league whether it came from the app or from a hand-written SQL
statement.

```
insert into league_messages / news_posts / polls
        │
        ▼  after-insert trigger
private.notify_push()          reads the URL + shared secret from Vault
        │
        ▼  pg_net (fire and forget — a push failure never rolls back the post)
supabase/functions/push        signs an APNs JWT, fans out to every device
        │
        ▼
api.push.apple.com
```

## What has to exist

| Piece | Where | Status |
|---|---|---|
| `device_tokens`, `notification_preferences` | migration `20260821000011` | deployed |
| `push` edge function | `supabase/functions/push` | deployed |
| `PUSH_SECRET` | function secret + Vault `push_service_key` | set |
| `push_function_url` | Vault | set |
| `aps-environment` entitlement | `Resources/CommissionersCartel.entitlements` | in the next build |
| **APNs key** | `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` | **not set — see below** |

Until the APNs key is set the chain runs end to end and delivers nothing: the
function has no credential to authenticate to Apple with.

## Creating the APNs key

One key covers every app on the account and never expires. Apple allows two at
a time, so if two already exist, reuse one rather than revoking.

1. <https://developer.apple.com/account/resources/authkeys/list> → **+**
2. Name it (e.g. `Cartel Push`), tick **Apple Push Notifications service (APNs)**,
   Continue, Register.
3. **Download** the `.p8`. It can only be downloaded once.
4. Note the **Key ID** on that page, and the **Team ID** from the top right of
   the developer site.

Then, from the repo root:

```sh
supabase secrets set \
  APNS_KEY_ID=ABCD123456 \
  APNS_TEAM_ID=EFGH789012 \
  APNS_BUNDLE_ID=com.commissionerscartel.app \
  APNS_PRIVATE_KEY="$(cat ~/Downloads/AuthKey_ABCD123456.p8)"
```

Keep the `.p8` somewhere safe and out of the repo; `supabase secrets` is the
only copy the server needs.

## Sandbox versus production

A token minted by an Xcode build only works against
`api.sandbox.push.apple.com`; a TestFlight or App Store token only works
against `api.push.apple.com`. Sending to the wrong host returns
`BadDeviceToken`.

The app records which environment its token came from (`PushEnvironment.current`
— `sandbox` under `DEBUG`, `production` otherwise) and the function sends to the
matching host. A token Apple reports as `410 Gone` or `BadDeviceToken` is
deleted, so dead rows do not accumulate.

## Preferences

`notification_preferences` holds three booleans. **An absent row means every
kind is on** — a member who never opens Settings stays subscribed. Only an
explicit `false` mutes.

Authors are never notified about their own posts: the trigger passes the author
id as `exclude_user`.

## Checking it without posting anything

`private.notify_push` can be called directly, which exercises Vault, pg_net and
the function without writing a post anyone will see:

```sql
select private.notify_push('news', 'Connectivity check', 'Ignore me.', null);
-- then, a few seconds later:
select status_code, content from net._http_response order by id desc limit 1;
```

`{"sent":0,"pruned":0,"failed":0}` with no devices registered means the whole
chain is healthy.
