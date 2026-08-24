-- @mentions in the league thread.
--
-- Matched in Postgres rather than in each app: the names live here, and two
-- client implementations of the same parsing rule would drift apart. A mention
-- notifies that person directly even if they are not watching the thread
-- closely — that is the whole point of typing someone's name.

alter table public.notification_preferences
    add column mentions boolean not null default true;

-- Everyone named in a body, by display name after an @.
--
-- Longest names first, so "@Michael Smith" does not merely match a member
-- called "Michael". Case-insensitive, because nobody capitalises reliably.
create or replace function private.mentioned_users(body text)
returns setof uuid
language sql
stable
set search_path = ''
as $$
    select p.id
      from public.profiles p
     where p.display_name is not null
       and length(p.display_name) > 1
       and position(lower('@' || p.display_name) in lower(body)) > 0
     order by length(p.display_name) desc;
$$;

create or replace function private.on_league_message_mentions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    author  text;
    target  uuid;
begin
    select coalesce(display_name, 'Someone') into author
      from public.profiles where id = new.author_id;

    for target in select * from private.mentioned_users(new.body) loop
        -- Mentioning yourself is not a notification.
        continue when target = new.author_id;

        perform private.notify_push(
            'mention',
            coalesce(author, 'Someone') || ' mentioned you',
            private.push_preview(new.body),
            null,
            target
        );
    end loop;
    return null;
end;
$$;

create trigger league_messages_mentions
    after insert on public.league_messages
    for each row execute function private.on_league_message_mentions();
