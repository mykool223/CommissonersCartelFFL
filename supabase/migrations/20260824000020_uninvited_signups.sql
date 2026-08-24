-- Tells the commissioner when somebody signs in with an address that is not on
-- the invite list.
--
-- Two people did exactly that and sat locked out with no explanation: sign-in
-- succeeded, then nothing worked and nothing said why. Silence is the worst
-- possible behaviour here — the person cannot fix it and the commissioner does
-- not know to.

create table public.uninvited_signups (
    id         uuid primary key default gen_random_uuid(),
    email      text not null,
    user_id    uuid references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    resolved   boolean not null default false,

    unique (email)
);

alter table public.uninvited_signups enable row level security;

-- Commissioners only: it is a list of email addresses.
create policy "Commissioners read uninvited signups" on public.uninvited_signups
    for select using (private.is_commissioner());

create policy "Commissioners resolve uninvited signups" on public.uninvited_signups
    for update using (private.is_commissioner()) with check (private.is_commissioner());

-- Pushes to every commissioner, one at a time.
create or replace function private.notify_commissioners(title text, body text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    target uuid;
begin
    for target in select id from public.profiles where is_commissioner loop
        perform private.notify_push('news', title, body, null, target);
    end loop;
end;
$$;

revoke execute on function private.notify_commissioners(text, text) from public;
revoke execute on function private.notify_commissioners(text, text) from anon, authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_email text := lower(trim(coalesce(new.email, '')));
    v_note  text;
begin
    select note into v_note
      from public.league_invites
     where email = v_email;

    if not found then
        -- Not on the roster. The auth user exists but has no profile, so every
        -- members-only policy returns nothing — which is correct, but used to
        -- happen in complete silence.
        insert into public.uninvited_signups (email, user_id)
        values (v_email, new.id)
        on conflict (email) do nothing;

        perform private.notify_commissioners(
            'Someone is locked out',
            v_email || ' signed in but is not on the league list.'
        );
        return new;
    end if;

    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(
            nullif(trim(coalesce(v_note, '')), ''),
            new.raw_user_meta_data ->> 'display_name',
            split_part(v_email, '@', 1),
            'New member'
        )
    )
    on conflict (id) do nothing;

    update public.league_invites
       set claimed_at = now()
     where email = v_email and claimed_at is null;

    return new;
end;
$$;
