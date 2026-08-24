-- One-to-one messages between league members.
--
-- Visible to the two people in the conversation and nobody else. That is
-- enforced in Postgres rather than in the app: a member reading somebody
-- else's messages must be impossible, not merely un-navigable.
--
-- The service role can still read every row, as it can for every table here.
-- There is no way around that short of end-to-end encryption, which is not
-- what a twelve-person fantasy league needs.

create table public.direct_messages (
    id           uuid primary key default gen_random_uuid(),
    -- Defaulted from the session so a client never states who it is.
    sender_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
    recipient_id uuid not null references auth.users (id) on delete cascade,
    body         text not null check (length(btrim(body)) between 1 and 2000),
    read_at      timestamptz,
    created_at   timestamptz not null default now(),

    -- Talking to yourself is not a feature.
    check (sender_id <> recipient_id)
);

create index direct_messages_pair_idx
    on public.direct_messages (sender_id, recipient_id, created_at desc);
create index direct_messages_inbox_idx
    on public.direct_messages (recipient_id, created_at desc);

alter table public.direct_messages enable row level security;

create policy "Read your own conversations" on public.direct_messages
    for select using (auth.uid() = sender_id or auth.uid() = recipient_id);

-- Both ends must be league members: an invited-but-unclaimed account should
-- not be able to message the league.
create policy "Send as yourself, to a member" on public.direct_messages
    for insert with check (
        auth.uid() = sender_id
        and private.is_member()
        and exists (select 1 from public.profiles where id = recipient_id)
    );

-- Unsend your own, within reason. No update policy: editing a sent message
-- after somebody has read it is a way to win arguments dishonestly.
create policy "Delete your own messages" on public.direct_messages
    for delete using (auth.uid() = sender_id);

-- Marking as read is the one field the recipient may change.
create policy "Mark your own received messages read" on public.direct_messages
    for update using (auth.uid() = recipient_id) with check (auth.uid() = recipient_id);

alter table public.notification_preferences
    add column direct boolean not null default true;

-- notify_push gains a recipient, so a DM reaches one person.
--
-- The old four-argument version has to go first: leaving it in place makes an
-- existing four-argument call ambiguous between it and the new one's defaults,
-- and every existing trigger calls it with four.
drop function if exists private.notify_push(text, text, text, uuid);

create or replace function private.notify_push(
    kind         text,
    title        text,
    body         text,
    exclude_user uuid default null,
    only_user    uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    fn_url text;
    fn_key text;
begin
    select decrypted_secret into fn_url
      from vault.decrypted_secrets where name = 'push_function_url';
    select decrypted_secret into fn_key
      from vault.decrypted_secrets where name = 'push_service_key';

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
            'exclude_user', exclude_user,
            'only_user',    only_user
        ),
        timeout_milliseconds := 5000
    );
end;
$$;

revoke execute on function private.notify_push(text, text, text, uuid, uuid) from public;
revoke execute on function private.notify_push(text, text, text, uuid, uuid) from anon, authenticated;

create or replace function private.on_direct_message_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    sender text;
begin
    select coalesce(display_name, 'Someone') into sender
      from public.profiles where id = new.sender_id;

    perform private.notify_push(
        'direct',
        coalesce(sender, 'Someone'),
        private.push_preview(new.body),
        null,
        new.recipient_id
    );
    return null;
end;
$$;

create trigger direct_messages_notify
    after insert on public.direct_messages
    for each row execute function private.on_direct_message_insert();
