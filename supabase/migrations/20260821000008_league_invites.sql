-- Only people on the roster become members.
--
-- Before this, signing up with any email created a profile, and being a member
-- was simply "has a profile row" — so anyone who got hold of the app could sign
-- in and read the league thread. Distribution was the only thing keeping people
-- out, which is not the same as a rule.
--
-- Now the trigger checks an invite list first. Someone not on it can still
-- authenticate — Supabase will happily create the auth user — but gets no
-- profile, so private.is_member() is false and every members-only policy
-- returns nothing. The app tells them to ask the commissioner.

create table public.league_invites (
    -- Stored lowercased; the trigger lowercases before comparing, so
    -- Devon@Example.com and devon@example.com are the same person.
    email      text primary key
               check (email = lower(email) and position('@' in email) > 1),
    -- Who this is, for the commissioner's own reference.
    note       text,
    invited_by uuid references public.profiles (id) on delete set null,
    created_at timestamptz not null default now(),
    -- Set when the invite is used, so it is obvious who has not signed in yet.
    claimed_at timestamptz
);

alter table public.league_invites enable row level security;

-- Only the commissioner sees or edits the roster. It is a list of the league's
-- email addresses; nobody else needs it.
create policy "Commissioners manage the invite list"
    on public.league_invites for all
    using (private.is_commissioner())
    with check (private.is_commissioner());

-- Replaces the version from the initial schema.
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
        -- Not on the roster. The auth user exists but has no profile, so they
        -- are not a member and every members-only policy returns nothing.
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

-- Anyone who is already a member was let in before this rule existed; record
-- them so the list reflects reality rather than only future signups.
insert into public.league_invites (email, note, claimed_at)
select lower(u.email), p.display_name, now()
  from auth.users u
  join public.profiles p on p.id = u.id
 where u.email is not null
on conflict (email) do nothing;
