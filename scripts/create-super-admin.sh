#!/bin/sh
# Creates (or promotes) the KHERJA ADMIN super admin.
# Usage: ADMIN_EMAIL=... ADMIN_PASSWORD=... rork env run -- sh scripts/create-super-admin.sh
# Needs EXPO_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. Never prints secrets.
set -e
URL="$EXPO_PUBLIC_SUPABASE_URL"
KEY="$SUPABASE_SERVICE_ROLE_KEY"
[ -n "$URL" ] && [ -n "$KEY" ] && [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASSWORD" ] || { echo "missing env"; exit 1; }

BODY=$(python3 -c 'import json,os;print(json.dumps({"email":os.environ["ADMIN_EMAIL"],"password":os.environ["ADMIN_PASSWORD"],"email_confirm":True}))')
RES=$(curl -s -X POST "$URL/auth/v1/admin/users" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d "$BODY")
USER_ID=$(printf %s "$RES" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("id",""))')

if [ -z "$USER_ID" ]; then
  # Already registered: find the user by email.
  USER_ID=$(curl -s "$URL/auth/v1/admin/users?per_page=1000" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" | python3 -c 'import json,sys,os;d=json.load(sys.stdin);e=os.environ["ADMIN_EMAIL"].lower();print(next((u["id"] for u in d.get("users",[]) if (u.get("email") or "").lower()==e),""))')
  [ -n "$USER_ID" ] || { echo "user creation failed: $(printf %s "$RES" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("msg") or d.get("message") or d.get("error_description") or "unknown")')"; exit 1; }
  echo "user already existed, promoting"
  # Set the password provided.
  P=$(python3 -c 'import json,os;print(json.dumps({"password":os.environ["ADMIN_PASSWORD"],"email_confirm":True}))')
  curl -s -o /dev/null -w "password update: %{http_code}\n" -X PUT "$URL/auth/v1/admin/users/$USER_ID" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d "$P"
else
  echo "user created"
fi

ROW=$(USER_ID="$USER_ID" python3 -c 'import json,os;print(json.dumps({"user_id":os.environ["USER_ID"],"role_code":"super_admin","display_name":"Super Admin","email":os.environ["ADMIN_EMAIL"],"active":True}))')
curl -s -w "\nadmin_users upsert: %{http_code}\n" -X POST "$URL/rest/v1/admin_users?on_conflict=user_id" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -H "Prefer: resolution=merge-duplicates,return=minimal" -d "$ROW"
