#!/bin/sh
set -e
curl -s -X POST "$EXPO_PUBLIC_SUPABASE_URL/functions/v1/auth-otp" \
  -H "apikey: $EXPO_PUBLIC_SUPABASE_ANON_KEY" -H "Content-Type: application/json" \
  -d '{"action":"request","phone":"0555123456"}' > /tmp/otp_req.json
cat /tmp/otp_req.json
echo
CODE=$(python3 -c "import json;print(json.load(open('/tmp/otp_req.json'))['dev_code'])")
curl -s -X POST "$EXPO_PUBLIC_SUPABASE_URL/functions/v1/auth-otp" \
  -H "apikey: $EXPO_PUBLIC_SUPABASE_ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"action\":\"verify\",\"phone\":\"0555123456\",\"code\":\"$CODE\"}" > /tmp/otp_ver.json
python3 -c "import json;d=json.load(open('/tmp/otp_ver.json'));print({k:('<set>' if k=='access_token' else v) for k,v in d.items()})"
