# KHERJA authentication: setup and status

Nothing in this document has been applied to a live Supabase project. Every step below is for the owner to perform deliberately.

## 1. Edge function secrets (`auth-otp`)

| Secret | Production | Development |
|---|---|---|
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE` | **required** | optional |
| `KHERJA_ENV` | leave **unset** (anything but the exact string `development` is production) | `development` |
| `OTP_HASH_SECRET` | **required**, random server-only value of at least 32 characters | same requirement |

Generate a value locally and set it only in the intended Supabase project (never commit it):

```sh
supabase secrets set OTP_HASH_SECRET="$(openssl rand -hex 32)"
```
| `ALLOW_DEV_OTP` | leave **unset** | `true` |

- `dev_code` is returned only when `KHERJA_ENV=development` AND `ALLOW_DEV_OTP=true` AND the SMS was not delivered. Both are server secrets; no request field or header can enable it.
- Production without a working Twilio configuration answers `503 Service SMS indisponible`, discards the code, and returns no code.
- **Breaking change for your current dev setup:** before this fix, the code was returned whenever Twilio was unset. To keep testing without SMS, set the two development secrets on your DEV project only.

```
supabase secrets set KHERJA_ENV=development ALLOW_DEV_OTP=true   # dev project only
supabase secrets unset KHERJA_ENV ALLOW_DEV_OTP                  # production
```

## 2. Database migrations

`0005_password_auth.sql` creates the attempt log. `0006_auth_security_hardening.sql` adds hashed IP identifiers, atomic rate-limit reservation/finalization RPCs, one-time OTP consumption, and replaces the plaintext `otp_codes.code` column with `code_hash`. The RPCs execute with invoker rights and are granted only to `service_role`. Applying 0006 intentionally deletes any outstanding OTP rows because their old plaintext values cannot be converted into keyed hashes. Review both migrations and apply them in order using your normal migration process. Neither migration has been applied to a live project.

Passwords are never stored by KHERJA code. They are passed to Supabase Auth (GoTrue), which stores a bcrypt hash in `auth.users`. New passwords require at least 8 characters and are capped at 72 UTF-8 bytes to respect bcrypt's input limit; Android and iOS apply the same client-side check. The function never logs bodies, passwords or codes.

## 3. Supabase dashboard

Authentication → URL Configuration → **Redirect URLs**: add `kherja://auth-callback`.

### Google
1. Google Cloud Console → APIs & Services → OAuth consent screen: configure the app.
2. Credentials → Create OAuth client ID → type **Web application**. Authorized redirect URI: `https://<PROJECT_REF>.supabase.co/auth/v1/callback`.
3. Supabase → Authentication → Providers → Google: enable, paste the Client ID and Client Secret.

Both apps use this web flow through Supabase (PKCE, system browser), so no Android/iOS-specific Google client is needed.

### Apple
Apple Developer account (paid) required.
1. Identifiers → App ID `app.rork.h04xk59ettzrqz7c6l4wp` (the current bundle ID / Android applicationId) → enable **Sign in with Apple**.
2. Identifiers → Services IDs → create one (for example `app.kherja.signin`) → enable Sign in with Apple → Configure: Domain `<PROJECT_REF>.supabase.co`, Return URL `https://<PROJECT_REF>.supabase.co/auth/v1/callback`.
3. Keys → create a key with Sign in with Apple, linked to the App ID. Download the `.p8` once. Note the Key ID and your Team ID.
4. Supabase → Providers → Apple: enable.
   - Client IDs: `app.rork.h04xk59ettzrqz7c6l4wp,<services id>` (bundle ID for native iOS, Services ID for the web flow used by Android).
   - Secret Key: a JWT you generate from Team ID, Key ID, Services ID and the `.p8` (Supabase documents the generator). **It expires after at most 6 months; calendar a rotation.**
5. Xcode → target KHERJA → Signing & Capabilities → **+ Capability → Sign in with Apple**. This creates the entitlements file and build setting. I did not edit `project.pbxproj` by hand. Without this capability, the iOS Apple button fails.

## 4. How each platform signs in

| | Password | Register / reset | Google | Apple |
|---|---|---|---|---|
| Android | `auth-otp` action `login` | SMS code + password (`purpose` register/reset) | Supabase OAuth PKCE in the system browser, return via `kherja://auth-callback` | same web flow (needs the Services ID) |
| iOS | same | same | `ASWebAuthenticationSession` PKCE, same redirect | native `ASAuthorizationController` → Supabase `id_token` grant with a SHA-256 nonce |

The original passwordless SMS login (`verify` with only phone and code) is unchanged and is reachable from the login screen ("Se connecter avec un code SMS").

## 5. Verification status

**Current test inventory:** the updated branch contains 55 Bun test cases across `handler.test.ts` (43) and `policy.test.ts` (12), including OTP hash-at-rest, handler-level concurrent requests, IP-wide caps, missing trusted IP/secret, one-time OTP use, and the bcrypt UTF-8 byte boundary. An earlier auth baseline was recorded as 62 tests / 232 assertions, but that was a different test set and is not a passing result for this branch. The updated branch has NOT been executed successfully. A GitHub Actions workflow was added at `.github/workflows/auth-otp-tests.yml`. Runs were created for the branch, but the latest run failed before any job steps were reported (runner ID 0, no step summaries, and the connector could not retrieve logs). This is an infrastructure/startup failure signal, not evidence that the Bun tests passed or failed. The failed job was re-queued once; check the run in GitHub Actions. Until a job actually executes and reports a result, treat the test suite as unverified. Run `bun test supabase/functions/auth-otp` locally as an independent check.
- production never returns a verification code: 8 environment combinations, hostile body fields and headers, code absent from logs;
- dev flag matrix, secure 503 in production without Twilio;
- OTP request limit (3 per 5 min per phone; 20 per 5 min per IP), verify/password lockout (5 failures per 15 min per phone; 30 per 15 min per IP);
- legacy OTP compatibility, register, reset, password login without account enumeration;
- password rules, and passwords absent from responses and logs;
- mutation checks: deliberately breaking the policy makes the tests fail.

**Important test boundary:** the new concurrency tests exercise the handler against an in-memory fake store. They do not prove PostgreSQL advisory-lock behavior. Before production, run a database integration test that fires concurrent calls to `reserve_auth_attempt` for one phone and one IP and verifies that no more than the configured limit is reserved.

**Written but NOT verified (no Android SDK, Swift toolchain, device or live Supabase in this environment):**
- all Android Kotlin and iOS Swift code (compilation, layout, RTL, visual fidelity to the reference);
- the real Supabase wiring in `index.ts` (user lookup, `generateLink` session minting, password grant);
- Google and Apple round trips, Apple nonce handling, the deep link, "remember me" across launches;
- the Apple logo vector path (typed from memory), to be compared visually with Apple's official artwork.

First real check: build both apps on Codemagic/Xcode, then run the flows on a development Supabase project.

## 6. Open decisions for the owner

1. **Phone linking for social accounts.** Google/Apple users have no phone number, which matters for driver payouts, Flexy lookup and support. Accounts are never auto-linked by e-mail (unsafe). A "add your phone" step after social sign-in is the proposed fix.
2. **Terms and privacy.** The register screen shows the consent text but there are no legal pages to link yet.
3. **Trusted IP header:** the function currently requires `cf-connecting-ip`. Supabase's current API-gateway log reference lists this as a captured request header, but that alone does not prove the header reaches this function in the target project. Verify it with a temporary development-only echo/test before enabling this function; the handler intentionally does not trust a client-supplied `x-forwarded-for` fallback.
4. **Splash variant** A/B/C is still waiting for your choice.
