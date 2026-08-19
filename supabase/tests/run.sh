#!/usr/bin/env bash
# Prove that roles are enforced by the database, not by the browser.
#
# Spins up a throwaway Postgres, stands in for the bits of Supabase the schema
# touches (auth.uid, auth.jwt, storage), applies every migration in order, then
# runs an attack suite: an attacker who has edited their own user_metadata must
# see nothing, while a genuine nurse and admin must still see everything.
#
# Needs postgresql-17 client + server binaries. Touches nothing outside /tmp.
#
#   ./supabase/tests/run.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN=${PG_BIN:-/usr/lib/postgresql/17/bin}
D=$(mktemp -d /tmp/stoma-pgtest.XXXXXX)
cleanup(){ "$BIN/pg_ctl" -D "$D/data" stop >/dev/null 2>&1 || true; rm -rf "$D"; }
trap cleanup EXIT

mkdir -p "$D/data"
"$BIN/initdb" -D "$D/data" -U postgres --auth=trust >/dev/null
"$BIN/pg_ctl" -D "$D/data" -l "$D/log" -o "-p 55432 -k $D -c listen_addresses=''" start >/dev/null
sleep 2
PSQL="psql -h $D -p 55432 -U postgres -q -v ON_ERROR_STOP=1"

$PSQL -f "$HERE/00_supabase_harness.sql" >/dev/null 2>&1
for f in "$HERE"/../migrations/*.sql; do
  $PSQL -f "$f" >/dev/null 2>&1 || { echo "MIGRATION FAILED: $(basename "$f")"; exit 1; }
done
# Supabase grants these by default; RLS is what restricts. The revoke mirrors 0015.
$PSQL -c "grant usage on schema public to authenticated;
          grant all on all tables in schema public to authenticated;
          revoke insert,update,delete on public.user_roles from authenticated;" >/dev/null

out=$($PSQL -f "$HERE/01_role_enforcement.sql" 2>&1 | grep -E "PASS|FAIL" || true)
echo "$out" | sed 's/^psql:[^ ]* NOTICE:  //'
if echo "$out" | grep -q FAIL; then
  echo; echo "SUITE FAILED"; exit 1
fi
echo; echo "All checks passed."
