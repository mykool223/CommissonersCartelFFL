-- A daily cap on coach questions, per member.
--
-- Every question costs money. A cap is not about anybody behaving badly — it
-- is about a loop in a client, or a curious member at 2am, not quietly turning
-- into a bill nobody agreed to.

create table public.coach_usage (
    user_id uuid not null references auth.users (id) on delete cascade,
    day     date not null default current_date,
    asked   int  not null default 0,

    primary key (user_id, day)
);

alter table public.coach_usage enable row level security;

-- You can see your own usage, so the app can say "3 left today" rather than
-- refusing without explanation.
create policy "Members read their own coach usage" on public.coach_usage
    for select using (auth.uid() = user_id);

-- Only the function writes, using the service role.
