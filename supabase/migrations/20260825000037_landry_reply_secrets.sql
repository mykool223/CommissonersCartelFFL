-- Use the secrets that already exist.
--
-- The first version invented two new vault names, which were never set, so
-- the trigger returned quietly and Landry never answered. The push trigger
-- has held the function URL and the shared secret since August; the reply
-- endpoint sits beside the push one, so the URL is derivable from it.
create or replace function private.on_league_message_for_landry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    push_url text;
    secret   text;
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

    select decrypted_secret into push_url
      from vault.decrypted_secrets where name = 'push_function_url';
    select decrypted_secret into secret
      from vault.decrypted_secrets where name = 'push_service_key';

    -- Not configured yet. Stay silent rather than failing somebody's message.
    if push_url is null or secret is null then
        return new;
    end if;

    perform net.http_post(
        url := replace(push_url, '/functions/v1/push', '/functions/v1/landry-reply'),
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-cartel-secret', secret
        ),
        body := jsonb_build_object('message_id', new.id)
    );
    return new;
end;
$$;
