-- Posting a message.
--
-- A function rather than a plain insert so the author is taken from the
-- session and the profile, never from the client. The RLS policy already
-- requires author_id = auth.uid(), but author_name is free text — without this
-- a member could post under someone else's name.

create or replace function public.post_league_message(p_body text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_name text;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to post' using errcode = '42501';
    end if;

    select display_name into v_name from public.profiles where id = auth.uid();
    if v_name is null then
        raise exception 'Only league members can post' using errcode = '42501';
    end if;

    if length(trim(coalesce(p_body, ''))) = 0 then
        raise exception 'Message is empty' using errcode = '22023';
    end if;

    insert into public.league_messages (author_id, author_name, body)
    values (auth.uid(), v_name, trim(p_body));
end;
$$;

revoke execute on function public.post_league_message(text) from public, anon;
grant execute on function public.post_league_message(text) to authenticated;
