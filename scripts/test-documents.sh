#!/bin/sh
# Smoke test: driver-documents bucket is private and the RPCs exist.
# Usage: rork env run -- sh scripts/test-documents.sh
URL="$EXPO_PUBLIC_SUPABASE_URL"; KEY="$SUPABASE_SERVICE_ROLE_KEY"
echo "bucket:"; curl -s "$URL/storage/v1/bucket/driver-documents" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(" public=",d.get("public")," limit=",d.get("file_size_limit"))'
echo "anon submit (must fail):"; curl -s -X POST "$URL/rest/v1/rpc/submit_driver_document" -H "apikey: $EXPO_PUBLIC_SUPABASE_ANON_KEY" -H "Content-Type: application/json" -d '{"p_type":"license","p_path":"x/y.jpg"}'; echo
echo "anon review (must fail):"; curl -s -X POST "$URL/rest/v1/rpc/admin_review_document" -H "apikey: $EXPO_PUBLIC_SUPABASE_ANON_KEY" -H "Content-Type: application/json" -d '{"p_id":"00000000-0000-0000-0000-000000000000","p_status":"approved"}'; echo
