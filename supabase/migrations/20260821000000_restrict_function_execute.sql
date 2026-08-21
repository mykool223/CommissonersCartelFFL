-- Take EXECUTE on the two RPCs away from anon.
--
-- There are two independent default grants in play, and revoking either one
-- alone leaves the other standing:
--
--   1. Postgres grants EXECUTE on a new function to PUBLIC, and every role
--      inherits from PUBLIC. So `revoke ... from anon` alone is a no-op.
--   2. Supabase additionally runs `alter default privileges in schema public
--      grant execute on functions to anon, authenticated, service_role`. So
--      `revoke ... from public` alone leaves an explicit `anon=X` grant behind.
--
-- Both were verified against a live project: after the revoke from PUBLIC in
-- 20250101000002, the ACL still read
--   postgres=X | anon=X | authenticated=X | service_role=X
--
-- Naming both is what actually closes it. Scripts/test-database.sh asserts the
-- result, and supabase/tests/00_supabase_stub.sql now reproduces Supabase's
-- default privileges so this cannot pass locally while failing in production.
--
-- service_role keeps its grant on purpose: that key is the admin path and
-- bypasses row level security by design.

revoke execute on function public.polls_with_results(int) from public, anon;
revoke execute on function public.cast_vote(uuid, uuid) from public, anon;

grant execute on function public.polls_with_results(int) to authenticated;
grant execute on function public.cast_vote(uuid, uuid) to authenticated;
