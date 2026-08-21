# Sending sign-in emails

The app signs people in with a magic link, so email has to actually work. This
is the one piece of setup that will silently ruin sign-in if skipped: Supabase's
built-in mailer is throttled to a handful of messages an hour and is explicitly
not meant for real use. Twelve people signing in on draft night would not all
get a link.

## Why not Outlook, Gmail or iCloud directly

**You cannot use a personal Outlook.com account as the SMTP server.** Microsoft
retired basic authentication for personal accounts, so SMTP now requires OAuth2,
and Supabase's SMTP settings only take host, port, username and password. There
is no way to connect them.

An **alias does not help**: an Outlook alias is the same account with another
address attached, so it inherits the same restriction.

Gmail and iCloud are the same story for different reasons — app passwords are
being wound down, consumer mailboxes rate-limit hard, and transactional mail
from a personal address lands in spam. If the account ever gets locked for
looking like a bot, sign-in breaks for the whole league.

## What to use instead

A transactional email service does the sending; your own address is still what
the league sees in the From line.

**Brevo**, because it verifies a single *email address* rather than requiring
you to own a domain — 300 emails a day, free, no card.

1. Sign up at [brevo.com](https://www.brevo.com).
2. **Senders, Domains & Dedicated IPs → Senders → Add a sender.** Use whatever
   address you want the league to see — an alias like
   `commissionerscartel@outlook.com` reads better than a personal one. Brevo
   emails a confirmation link; an alias delivers to your normal inbox.
3. **SMTP & API → SMTP.** Copy the **SMTP key**. This is not your account
   password, and it only sends mail — it cannot read anything.
4. Apply it:

   ```bash
   export SUPABASE_AUTH_SMTP_USER='your-brevo-login'
   export SUPABASE_AUTH_SMTP_PASS='the-smtp-key'
   export SUPABASE_AUTH_SMTP_FROM='commissionerscartel@outlook.com'
   supabase config push
   ```

Nothing in the app changes. Supabase starts relaying through Brevo, and the
rate limit in `config.toml` goes up accordingly.

## Checking it works

Send yourself a link from the app's sign-in screen. If it arrives, it works for
everyone. If it does not, Brevo's **Transactional → Logs** shows every attempt
and why it failed — far more useful than Supabase's side, which only reports
that it handed the message off.

## Alternatives

Mailjet and SendGrid also verify a single sender address. Resend is good but
wants a domain, which makes it the wrong fit here.
