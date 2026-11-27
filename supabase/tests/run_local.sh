#!/usr/bin/env bash
# Applies every migration in order, then behavioural tests, on a THROWAWAY Postgres.
# Usage: PSQL="psql -h /tmp/sock -p 55432 -U postgres -d postgres" supabase/tests/run_local.sh
# The database must be empty. Never point this at a real Supabase project.
set -euo pipefail
: "\${PSQL:?set PSQL to a psql command for a disposable empty database}"
HERE="$(cd "$(dirname "$0")" && pwd)"

run_sql() {
  local file="$1"
  local output
  if ! output=$($PSQL -v ON_ERROR_STOP=1 -q -f "$file" 2>&1); then
    printf '%s\n' "$output"
    return 1
  fi
  printf '%s\n' "$output" | grep -v -E 'NOTICE|WARNING|HINT' || true
}

run_sql "$HERE/local_stack_stub.sql"
for f in "$HERE"/../migrations/*.sql; do
  echo "== $(basename "$f")"
  run_sql "$f"
done

$PSQL -v ON_ERROR_STOP=1 -f "$HERE/stack_behavior.sql" 2>&1 | grep -E 'PASS|FAIL|ALL CHECKS|ERROR'
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/admin_deleted_guard_0014.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/support_sos_0011.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/delete_account_0013.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/delete_account_0015.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/delete_account_0016.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/push_devices_0017.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/push_environment_0019.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/push_devices_0019.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/admin_deleted_metrics_0018.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/admin_custom_permissions_0020.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/admin_delivery_management_0021.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/admin_permission_escalation_0024.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/admin_permission_escalation_0025.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/admin_profile_rls_0026.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
$PSQL -v ON_ERROR_STOP=1 -f "$HERE/admin_profile_read_permissions_0027.sql" 2>&1 | grep -E "PASS|FAIL|PASSED|ERROR"
