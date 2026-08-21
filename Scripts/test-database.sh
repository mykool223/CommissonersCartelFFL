#!/usr/bin/env bash
#
# Applies supabase/migrations/ to a throwaway Postgres and asserts the security
# properties the app depends on — that non-members see nothing, that re-voting
# cannot inflate a tally, and that anon cannot reach the RPCs.
#
# Uses a local Postgres, not Supabase, so it needs no account and no network.
# The parts of Supabase the schema depends on (the auth schema, auth.uid(), the
# anon/authenticated roles) are stubbed in tests/00_supabase_stub.sql.
#
#   ./Scripts/test-database.sh
#
# Set DATABASE_URL to run against an existing server instead (CI does this).
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -n "${DATABASE_URL:-}" ]; then
  psql_run() { psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q "$@"; }
  echo "==> Using DATABASE_URL"
else
  for candidate in /opt/homebrew/opt/postgresql@17/bin /opt/homebrew/opt/postgresql@16/bin /usr/local/opt/postgresql@17/bin; do
    [ -d "$candidate" ] && PATH="$candidate:$PATH"
  done
  command -v initdb >/dev/null 2>&1 || {
    echo "Postgres not found. Install it with:  brew install postgresql@17" >&2
    exit 1
  }

  PORT="${PGPORT:-55432}"
  DATA="$(mktemp -d)/pgdata"
  # Short socket dir on purpose: the Unix socket path has a 103-byte limit and
  # a temp dir nested under a long path blows straight through it.
  SOCKET="$(mktemp -d /tmp/pgc.XXXXXX)"

  cleanup() { pg_ctl -D "$DATA" stop -m immediate >/dev/null 2>&1 || true; }
  trap cleanup EXIT

  echo "==> Starting a throwaway Postgres on :$PORT"
  initdb -D "$DATA" -U postgres --auth=trust >/dev/null
  pg_ctl -D "$DATA" -o "-p $PORT -k $SOCKET" -l "$DATA/server.log" start >/dev/null
  for _ in $(seq 1 30); do
    pg_isready -h "$SOCKET" -p "$PORT" >/dev/null 2>&1 && break
    sleep 1
  done
  createdb -h "$SOCKET" -p "$PORT" -U postgres cartel
  psql_run() { psql -h "$SOCKET" -p "$PORT" -U postgres -d cartel -v ON_ERROR_STOP=1 -q "$@"; }
fi

echo "==> Stubbing the Supabase-provided pieces"
psql_run -f supabase/tests/00_supabase_stub.sql

echo "==> Applying migrations"
for migration in supabase/migrations/*.sql; do
  psql_run -f "$migration"
  echo "    applied $(basename "$migration")"
done

echo "==> Loading fixtures"
psql_run -f supabase/tests/01_fixtures.sql

echo "==> Checking security expectations"
psql_run -f supabase/tests/02_security.sql

echo ""
echo "Database checks passed."
