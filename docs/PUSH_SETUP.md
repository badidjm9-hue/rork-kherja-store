# Push notifications setup

This repository now contains the server-side push registration and delivery path. It is not active until the owner configures provider credentials and a Supabase Database Webhook.

## Supabase migrations

Apply migrations 0017 and earlier to the TEST project only after reviewing the full migration chain. Migration 0017 creates private `push_devices` storage, authenticated register/unregister RPCs, and removes device tokens when a profile is deleted. No client can directly read device tokens.

## Edge Function

Deploy `push-notifications` only after setting these function secrets in Supabase TEST:

- `PUSH_WEBHOOK_SECRET`: a long random webhook secret.
- `FCM_SERVICE_ACCOUNT_JSON`: Firebase service-account JSON with Firebase Cloud Messaging send permission.
- `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`.
- `APNS_USE_SANDBOX=true` for development/TestFlight sandbox delivery; use production APNs only for production-signed apps.

Do not put provider secrets in the mobile apps or Git.

## Database Webhook

Create a Database Webhook for `public.notifications`, event `INSERT`, targeting the deployed `push-notifications` Edge Function. Add header `x-kherja-push-secret` with the exact value of `PUSH_WEBHOOK_SECRET`.

The webhook sends the notification title/body already generated in the recipient's language. It looks up registered devices through the service role and sends Android via FCM HTTP v1 and iOS via APNs token authentication.

## Remaining client/provider setup

- Android now includes the Firebase Messaging service, Android 13+ permission request, token persistence, registration/unregistration RPC calls, and notification display. It still needs the owner's Firebase project and `android-kherja/app/google-services.json` to initialize Firebase.
- iOS now requests notification permission after sign-in, registers with APNs, caches the device token, and registers/unregisters it through Supabase. It still needs the Apple Push Notifications capability and a provisioning profile with the `aps-environment` entitlement.
- No credentials are present in the repository. No migration or function has been deployed and no push has been sent.
