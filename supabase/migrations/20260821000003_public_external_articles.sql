-- Let anyone with the anon key read syndicated headlines.
--
-- 20260821000002 gated these behind private.is_member(), copying the rule used
-- for league-authored content. That was wrong on both counts:
--
--   * It protects nothing. These rows are headlines and links from a public RSS
--     feed — anyone can read the same feed directly, without the app.
--   * It blocked the feature entirely, because the app has no signed-in user
--     yet, so is_member() is false and every read returned zero rows.
--
-- League-authored content (news_posts, recaps, polls) keeps its membership
-- requirement. This table is the exception because its contents are already
-- public by definition.
--
-- Writes are unaffected: there is still no insert/update/delete policy, so only
-- the daily ingest — which uses the service role — can add rows.

drop policy "Members can read outside news" on public.external_articles;

create policy "Anyone can read syndicated headlines"
    on public.external_articles for select
    using (true);
