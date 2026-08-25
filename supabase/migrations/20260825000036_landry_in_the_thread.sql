-- Landry answers when the thread calls him.
--
-- Mentioning him by name in the league thread gets a reply, posted under his
-- own account so it is a message like any other: readable by members only,
-- deletable by the commissioner, and attributable.
--
-- Deliberately public rather than a private chat. A coach who settles an
-- argument about whether a trade was fair should do it in front of everybody,
-- which is where the argument is.
create table public.landry_replies (
    message_id  uuid primary key references public.league_messages (id) on delete cascade,
    replied_at  timestamptz not null default now()
);

alter table public.landry_replies enable row level security;

-- His account, so the trigger and the function agree on who he is.
create or replace function private.landry_id()
returns uuid
language sql
immutable
set search_path = ''
as $$
    select '582f8eb1-d3c1-42c3-b14d-810c7e5d19fc'::uuid;
$$;

-- Fires the reply. The edge function does the talking; this only decides
-- whether he was addressed.
create or replace function private.on_league_message_for_landry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    project text;
    secret  text;
begin
    -- Never answer himself. Without this, one reply mentioning a name would
    -- start a conversation with no end.
    if new.author_id = private.landry_id() then
        return new;
    end if;

    if position('@landry' in lower(new.body)) = 0
       and position('@coach landry' in lower(new.body)) = 0 then
        return new;
    end if;

    select decrypted_secret into project
      from vault.decrypted_secrets where name = 'project_url';
    select decrypted_secret into secret
      from vault.decrypted_secrets where name = 'push_secret';
    if project is null or secret is null then
        return new;
    end if;

    perform net.http_post(
        url := project || '/functions/v1/landry-reply',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-cartel-secret', secret
        ),
        body := jsonb_build_object('message_id', new.id)
    );
    return new;
end;
$$;

create trigger league_message_for_landry
    after insert on public.league_messages
    for each row execute function private.on_league_message_for_landry();
