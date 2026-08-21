-- Push notifications for new chat messages, league news, and polls.
--
-- Flow: a row lands in league_messages / news_posts / polls, an after-insert
-- trigger fires, and private.notify_push queues an HTTP call to the `push`
-- edge function via pg_net. The edge function does the APNs work, because
-- signing a JWT with an ES256 key is not something to attempt in plpgsql.
--
-- pg_net is deliberately fire-and-forget: a failed or slow push must never
-- roll back the message that triggered it.

-- pg_net installs into its own `net` schema. Guarded because the throwaway
-- Postgres used by Scripts/test-database.sh has no pg_net to install; that
-- harness supplies a net.http_post stub instead.
do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_net') then
        create extension if not exists pg_net;
    end if;
end
$$;

-- One row per device, not per user: people have a phone and an iPad, and a
-- reinstall issues a fresh token while the old one keeps working until APNs
-- reports it gone.
create table public.device_tokens (
    token       text primary key,
    user_id     uuid not null references auth.users (id) on delete cascade,
    environment text not null default 'production'
                     check (environment in ('sandbox', 'production')),
    updated_at  timestamptz not null default now()
);

create index device_tokens_user_id_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- A token identifies a device, so it is only ever the owner's business.
create policy "Members manage their own device tokens" on public.device_tokens
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Absent row means "notify me about everything". Storing the default rather
-- than requiring a row keeps a member who never opens Settings subscribed.
create table public.notification_preferences (
    user_id  uuid primary key references auth.users (id) on delete cascade,
    messages boolean not null default true,
    news     boolean not null default true,
    polls    boolean not null default true
);

alter table public.notification_preferences enable row level security;

create policy "Members manage their own notification preferences"
    on public.notification_preferences
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Queues one call to the push edge function.
--
-- `exclude_user` keeps the author's own phone quiet: posting a message and
-- then being notified about it reads as a bug.
create or replace function private.notify_push(
    kind         text,
    title        text,
    body         text,
    exclude_user uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    fn_url  text;
    fn_key  text;
begin
    select decrypted_secret into fn_url
      from vault.decrypted_secrets where name = 'push_function_url';
    select decrypted_secret into fn_key
      from vault.decrypted_secrets where name = 'push_service_key';

    -- Secrets absent means push is not configured yet. Stay silent rather
    -- than failing the insert that triggered us.
    if fn_url is null or fn_key is null then
        return;
    end if;

    perform net.http_post(
        url     := fn_url,
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || fn_key
        ),
        body    := jsonb_build_object(
            'kind',         kind,
            'title',        title,
            'body',         body,
            'exclude_user', exclude_user
        ),
        timeout_milliseconds := 5000
    );
end;
$$;

revoke execute on function private.notify_push(text, text, text, uuid) from public;
revoke execute on function private.notify_push(text, text, text, uuid) from anon, authenticated;

-- Trims a notification body to something a lock screen will actually show.
create or replace function private.push_preview(raw text, limit_chars int default 140)
returns text
language sql
immutable
set search_path = ''
as $$
    select case
        when length(raw) <= limit_chars then raw
        else left(raw, limit_chars - 1) || '…'
    end;
$$;

create or replace function private.on_league_message_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    author text;
begin
    select coalesce(display_name, 'Someone') into author
      from public.profiles where id = new.author_id;

    perform private.notify_push(
        'messages',
        coalesce(author, 'Someone'),
        private.push_preview(new.body),
        new.author_id
    );
    return null;
end;
$$;

create trigger league_messages_notify
    after insert on public.league_messages
    for each row execute function private.on_league_message_insert();

create or replace function private.on_news_post_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform private.notify_push(
        'news',
        'League news',
        private.push_preview(new.title),
        new.author_id
    );
    return null;
end;
$$;

create trigger news_posts_notify
    after insert on public.news_posts
    for each row execute function private.on_news_post_insert();

create or replace function private.on_poll_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform private.notify_push(
        'polls',
        'New poll',
        private.push_preview(new.question),
        new.created_by
    );
    return null;
end;
$$;

create trigger polls_notify
    after insert on public.polls
    for each row execute function private.on_poll_insert();
