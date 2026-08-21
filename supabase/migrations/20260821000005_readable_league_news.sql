-- Let the app read league posts without a signed-in member.
--
-- WHY THIS EXISTS, AND HOW TO UNDO IT
--
-- news_posts and recaps require private.is_member() to read. That is the right
-- long-term rule, but there is no sign-in yet (#2), so is_member() is false for
-- everyone and the League news tab shows "No posts yet" no matter what the
-- commissioner publishes. The feature is unusable until auth lands.
--
-- This trades a little privacy for a working screen in the meantime. What it
-- actually exposes: anyone holding the anon key — which ships inside the app
-- binary, though not in this repo — can read league posts and recaps. Not
-- polls, not votes, not profiles; those keep their membership requirement.
--
-- To undo, once sign-in exists:
--
--   drop policy "Anyone can read league news" on public.news_posts;
--   drop policy "Anyone can read recaps openly" on public.recaps;
--   create policy "Members can read the news"
--       on public.news_posts for select using (private.is_member());
--   create policy "Members can read recaps"
--       on public.recaps for select using (private.is_member());
--
-- Writing is unaffected: publishing still requires a commissioner.

drop policy "Members can read the news" on public.news_posts;
create policy "Anyone can read league news"
    on public.news_posts for select
    using (true);

drop policy "Members can read recaps" on public.recaps;
create policy "Anyone can read recaps openly"
    on public.recaps for select
    using (true);
