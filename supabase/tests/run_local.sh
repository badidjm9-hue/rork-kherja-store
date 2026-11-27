#!/usr/bin/env bash
# Applies migrations 0001..N in order, then the behavioural tests, on a THROWAWAY Postgres.
# Usage: PSQL="psql -h /tmp/sock -p 55432 -U postgres -d postgres" supabase/tests/run_local.sh
# The database must be empty. Never point this at a real Supabase project.
set -euo pipefail
: "${PSQL:?set PSQL to a psql command for a disposable empty database}"
HERE="$(cd "$(dirname "$0")" && pwd)"
$PSQL -v ON_ERROR_STOP=1 -q -f "$HERE/local_stack_stub.sql" 2>&1 | grep -v -E 'NOTICE|WARNING|HINT' || true
for f in "$HERE"/../migrations/*.sql; do
  echo "== $(basename "$f")"; $PSQL -v ON_ERROR_STOP=1 -q -f "$f" 2>&1 | grep -v NOTICE || true
done
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/stack_behavior.sql" 2>&1 | grep -E 'PASS|FAIL|ALL CHECKS|ERROR' 
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/support_sos_0011.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/delete_account_0013.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
