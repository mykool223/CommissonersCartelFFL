-- Creating a poll in one statement.
--
-- The RLS policies already let any member create a poll and its options, but a
-- poll and its options are two inserts. Done from the client, a failure between
-- them leaves a poll with no options — which renders as an unanswerable
-- question nobody can delete except its author.
--
-- Doing both here makes it atomic, and takes created_by from the session rather
-- than trusting the client with it.

-- The season rule lives in one place rather than being passed in by the client,
-- which could disagree with what the app is asking for.
create or replace function public.current_season()
returns int
language sql
stable
as $$
    select case
        when extract(month from now() at time zone 'America/Chicago') < 3
            then extract(year from now() at time zone 'America/Chicago')::int - 1
        else extract(year from now() at time zone 'America/Chicago')::int
    end;
$$;

create or replace function public.create_poll(
    p_question  text,
    p_options   text[],
    p_closes_at timestamptz default null,
    p_week      int default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_name    text;
    v_poll_id uuid;
    v_option  text;
    v_index   int := 0;
    v_kept    text[] := '{}';
begin
    if auth.uid() is null then
        raise exception 'You must be signed in' using errcode = '42501';
    end if;

    select display_name into v_name from public.profiles where id = auth.uid();
    if v_name is null then
        raise exception 'Only league members can create polls' using errcode = '42501';
    end if;

    if length(trim(coalesce(p_question, ''))) = 0 then
        raise exception 'The question is empty' using errcode = '22023';
    end if;

    -- Drop blanks before counting, so three boxes with one left empty is a
    -- valid two-option poll rather than an error.
    foreach v_option in array coalesce(p_options, '{}')
    loop
        if length(trim(coalesce(v_option, ''))) > 0 then
            v_kept := array_append(v_kept, trim(v_option));
        end if;
    end loop;

    if array_length(v_kept, 1) is null or array_length(v_kept, 1) < 2 then
        raise exception 'A poll needs at least two options' using errcode = '22023';
    end if;

    if array_length(v_kept, 1) > 8 then
        raise exception 'A poll can have at most eight options' using errcode = '22023';
    end if;

    if p_closes_at is not null and p_closes_at <= now() then
        raise exception 'The closing time is already past' using errcode = '22023';
    end if;

    insert into public.polls (question, season, week, created_by, created_by_name, closes_at)
    values (
        trim(p_question),
        public.current_season(),
        p_week,
        auth.uid(),
        v_name,
        p_closes_at
    )
    returning id into v_poll_id;

    foreach v_option in array v_kept
    loop
        insert into public.poll_options (poll_id, label, position)
        values (v_poll_id, left(v_option, 120), v_index);
        v_index := v_index + 1;
    end loop;

    return v_poll_id;
end;
$$;

revoke execute on function public.create_poll(text, text[], timestamptz, int) from public, anon;
grant execute on function public.create_poll(text, text[], timestamptz, int) to authenticated;
