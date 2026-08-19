#!/usr/bin/env bash
# Prove the security and retention rules are enforced by the database.
#
# Spins up a throwaway Postgres, stands in for the bits of Supabase the schema
# touches (auth.uid, auth.jwt, storage), applies every migration in order, and
# runs each suite in its OWN database. Isolation is not tidiness: the suites all
# seed the same fixture user ids, so sharing a database made suite 2 abort on a
# duplicate key and report nothing at all — which the runner then read as
# success. Hence the assertion-count guard below too.
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

fails=0
for suite in "$HERE"/0[1-9]_*.sql; do
  db="t$(basename "$suite" .sql | tr -cd '[:alnum:]')"
  createdb -h "$D" -p 55432 -U postgres "$db"
  PSQL="psql -h $D -p 55432 -U postgres -d $db -q -v ON_ERROR_STOP=1"

  $PSQL -f "$HERE/00_supabase_harness.sql" >/dev/null 2>&1
  for f in "$HERE"/../migrations/*.sql; do
    $PSQL -f "$f" >/dev/null 2>&1 || { echo "MIGRATION FAILED: $(basename "$f")"; exit 1; }
  done
  # Supabase grants these by default; RLS is what restricts. Mirrors 0015.
  $PSQL -c "grant usage on schema public to authenticated;
            grant all on all tables in schema public to authenticated;
            revoke insert,update,delete on public.user_roles from authenticated;" >/dev/null

  echo "── $(basename "$suite") ──"
  raw=$($PSQL -f "$suite" 2>&1 || true)
  out=$(echo "$raw" | grep -E "PASS|FAIL" || true)
  echo "$out" | sed 's/^psql:[^ ]* NOTICE:  //'

  n=$(echo "$out" | grep -c PASS || true)
  if [ -z "$out" ] || [ "$n" -eq 0 ]; then
    echo "  NO ASSERTIONS RAN — the suite aborted. Last error:"
    echo "$raw" | grep -i error | head -3 | sed 's/^/    /'
    fails=1
  fi
  echo "$out" | grep -q FAIL && fails=1
  echo
done

if [ "$fails" -ne 0 ]; then echo "SUITE FAILED"; exit 1; fi
echo "All checks passed."
