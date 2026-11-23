#!/bin/sh
# Smoke test: server-side fare computation for the published pricing (car, noon, Alger and peak hour).
set -e
CFG=$(curl -s "$EXPO_PUBLIC_SUPABASE_URL/rest/v1/pricing_versions?status=eq.published&select=config" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | sed 's/^\[{"config":\(.*\)}\]$/\1/')
for d in 1 5 10 20; do
  for t in "2026-11-24T12:00:00+01:00" "2026-11-24T08:00:00+01:00"; do
    printf "%s km @ %s: " "$d" "$t"
    curl -s "$EXPO_PUBLIC_SUPABASE_URL/rest/v1/rpc/compute_fare" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "Content-Type: application/json" \
      -d "{\"c\":$CFG,\"p_distance\":$d,\"p_vehicle\":\"car\",\"p_city\":\"alger\",\"p_at\":\"$t\"}"
    echo
  done
done
