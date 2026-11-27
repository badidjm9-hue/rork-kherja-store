# KHERJA continuation: progress

Branch `feature/kherja-continue` (pushed to GitHub). Base: 00454e4.

| Phase | Status |
|---|---|
| Codemagic Android setup | done (on `codemagic/android-setup`) |
| Phase 1 audit and design comparison | done, accepted |
| Phase 2 login: OTP security, backend, Android, iOS, social phone linking, docs | code complete; mobile clients remain uncompiled and untested (see `docs/AUTH_SETUP.md`) |
| Phase 3 (parcel delivery) | implementation in progress on Android/iOS + additive Supabase migration 0008; not deployed or built/tested |
| Phases 4 to 9 (business, wallet, payments, campaign, extras, security) | not started |

## Commits on `feature/kherja-continue`

- `5e3d697` — `auth-otp`: production-safe OTP, password login, registration, reset, rate limits, migration 0005, initial backend tests
- `e102fe7` — Android login/register/forgot-password and Google/Apple OAuth PKCE
- `66375e2` — iOS login/register/forgot-password, native Apple and Google sign-in
- `2a87d6b` — authentication setup documentation
- `5384659` — hashed OTPs, social-account phone-link backend actions, migration 0006 database gate
- `c92f47f` — Android/iOS `link_request` and `link_verify` integration, migration 0007 `my_phone_verified()`, and updated authentication documentation

## Social-account phone verification

Both mobile clients call the `auth-otp` Edge Function with the signed-in user's bearer token:
1. `link_request` sends an SMS verification code to the requested phone.
2. `link_verify` validates the code and records the verified phone against the current account.
3. The clients call `my_phone_verified()` to determine whether the driver phone gate is satisfied.

Migration 0007 depends on 0006. Neither migration has been applied to a live Supabase project. The database triggers in 0006 remain the authoritative enforcement layer if the client RPC is unavailable.

## Verification status

- Backend Bun suite: 70 tests / 258 assertions passed in the reported environment.
- Migration SQL: exercised only against a disposable local Postgres setup with stand-in schemas.
- Android: not compiled or run; no APK or confirmed Codemagic result.
- iOS: not compiled or run; requires macOS/Xcode or CI.
- Live Supabase, SMS delivery, Google/Apple provider round trips, RTL/LTR device rendering, and design-fidelity comparison remain unverified.

## Owner decisions in force

Commission 15%/12% unapproved placeholders (admin-configurable); passenger payments cash only; Flexy/BaridiMob/Chargily for driver commission only; per-role navigation; illustrative screenshot prices; delivery 90/60 DZD/km with 350 DZD motorcycle minimum; splash variant undecided.

- Stabilization: OTP codes hashed; phone-link actions and database gate added; Codemagic workflow trigger remains scoped to `codemagic/android-setup`.


## Phase 3 — parcel delivery implementation (not released)

- Added `supabase/migrations/0008_delivery.sql` with a separate `delivery_orders` workflow; ride requests and rides are not repurposed.
- Server RPCs: `quote_delivery`, `create_delivery_order`, `open_delivery_feed`, `claim_delivery_order`, `update_delivery_status`, `cancel_delivery_order`, and `expire_delivery_orders`.
- Server-side pricing follows the recorded owner decision: car 90 DZD/km, motorcycle 60 DZD/km, motorcycle minimum 350 DZD; passenger payment is cash on delivery. No commission is charged or inferred in this phase.
- Driver feed is redacted: recipient name and phone are not returned until the driver claims the order. RLS exposes full rows only to the passenger owner or assigned driver.
- Orders expire after 15 minutes; a driver must be approved and online to see/claim orders. One active delivery per passenger and per driver is enforced by partial unique indexes.
- Android and iOS now have separate delivery tabs for passenger and driver roles, request creation, address search, server quote, driver claim, pickup/delivered transitions, passenger cancellation, and status refresh.
- The migration is additive and has **not** been applied to Supabase (local or production) in this work. No production data or secrets were changed.
- Android/iOS builds and device testing have **not** been run. SQL behavior, auth/RLS behavior, geocoding, and end-to-end delivery remain unverified. Review and test migration 0008 in a disposable Supabase project before any production rollout.


## UI completion pass — 2026-11-26

- Added a MapKit map preview to the iOS passenger home, showing the current pickup location and selected destination when available; added an Algiers fallback map region before location permission resolves.
- Android passenger home already renders its interactive map preview; this was confirmed in the current source.
- Added `docs/UI_COMPLETION_TRACKER.md` to record existing screen coverage, missing passenger/driver/admin interfaces, and build/E2E verification gates.
- This UI pass is code-only. Xcode/Gradle builds and device tests have not been run. No Supabase migration or production change was made.


## Additional settings UI pass — 2026-11-26

- Added Arabic/French help, privacy-information, and about panels to Android and iOS settings. These panels explain basic app flows and device permissions; they are not a substitute for owner-approved legal policy text or a configured support channel.
- Corrected the Android driver delivery tab to use the parcel/shipping icon.
- No native build or device test was run. No production backend, database, or storage configuration was changed.

## Driver profile and document workflow — 2026-11-26

- Android and iOS driver profiles now expose vehicle make, model, plate, and color. iOS saves the existing vehicle_color profile field with visible error handling.
- Added typed driver-document models and read APIs on both platforms for the existing driver_documents table.
- Added private Storage upload and submit_driver_document RPC wiring on Android and iOS. The UI lists the five required document types and reflects pending, approved, and rejected review states, including rejection reasons.
- The existing migration 0003_driver_documents.sql defines the private bucket, Storage policies, table/RLS, upload RPC, and admin review flow. This work did not apply or deploy that migration; verify its presence in the target Supabase project before attempting uploads.
- Current client pickers accept images only (JPEG output on iOS; JPEG/PNG/HEIC image selection on Android). PDF selection and document preview/download are not included yet.
- No Xcode or Gradle build, device upload, RLS test, or admin review E2E was run. Treat this implementation as source-complete but not build-verified.

## Feature-branch verification — 2026-11-26

- On `feature/kherja-ui-completion`, admin routes now load on demand; the built entry bundle fell from 1.27 MB to 616 KB (gzip: 361 KB to 183 KB). A Vite warning remains because the shared entry chunk is still over 500 KB. Added three unit tests for pricing-version classification and configuration helpers.
- Admin verification: production build passed; 3 unit tests passed; ESLint reported 0 errors and 11 existing warnings. The browser-test command found no browser test files.
- Updated admin dependencies, moved React Router to patched v7, and removed the unused direct Zod dependency. `bun audit` reports no known vulnerabilities.
- Applied migrations 0001–0008 in order to a disposable PostgreSQL 16 database with local stand-ins for Supabase Auth and Storage. Verified phone gating, delivery quote minimum, duplicate-order rejection, participant RLS, redacted driver feed, claim, and valid/invalid status transitions.
- That database test exposed an ambiguous `status` reference in `open_delivery_feed()`, which is fixed by qualifying the expiry-update columns. No production database, secrets, or Edge Functions were changed.
- Android/iOS builds remain unverified: this environment has no Android SDK/JDK or Xcode. The TypeScript project check exceeded the available command timeout. No screen-reference images were present in the repository for visual comparison.


## Admin completion pass — integrated onto `feature/kherja-ui-completion`

| Item | Status |
|---|---|
| Admin: driver document review (private-bucket signed links, approve/reject with reason, audit via `admin_review_document`) | done; admin typecheck/build/lint pass; not exercised against a live Supabase |
| Admin: Deliveries page (status filters, search, pagination, 15 s refresh) + `deliveries.read` permission | done, same verification; requires migration 0009 |
| Admin: driver "phone verified" badge via `admin_driver_phone_status()` | done; requires migration 0009 |
| Migration 0009 (additive, **not applied**) | applies and re-applies cleanly on throwaway Postgres 16 with stand-in `auth`/permission schema; RLS and RPC permission checks pass |
| Codemagic: debug APK + iOS simulator workflows trigger on this branch | configured; first debug build reached `generateConfig` and stopped because `EXPO_PUBLIC_SUPABASE_URL` / `EXPO_PUBLIC_SUPABASE_ANON_KEY` are not set in Codemagic |

## Integration verification — `feature/kherja-integrated` (2026-11-26)

Executed in this environment, with results:

| Check | Result |
|---|---|
| `bun install --frozen-lockfile` (admin) after rewriting 117 lockfile URLs from `package-firewall.replit.internal` to `registry.npmjs.org` (only the URL prefix changed; versions and integrity hashes untouched; every URL matches `<name>/-/<basename>-<version>.tgz`) | passed, 120 packages |
| Admin `tsc --noEmit` (includes the new files) | passed |
| Admin `vite build` | passed (entry chunk still ~617 kB, Vite size warning remains) |
| Admin unit tests (`vitest run`): pricing (3) + labels (5) | 8 passed, 0 failed; no browser tests exist |
| Admin `eslint` | 0 errors, 11 pre-existing warnings |
| Backend `bun test` (auth-otp) | 70 passed, 0 failed |
| Migrations 0001-0009 applied in order on a fresh throwaway PostgreSQL 16 with stand-in `auth`/`storage` objects (`supabase/tests/local_stack_stub.sql`) | all applied without errors |
| Behavioural SQL suite `supabase/tests/stack_behavior.sql` (run via `supabase/tests/run_local.sh`): phone gate, document upload/submit/review + audit, admin permissions (0009), delivery create/feed/claim/status with recipient-data privacy | 41 checks passed |

Not executed / not verified: Android build, iOS build, any device or simulator test, RTL/LTR visual check, comparison with the owner's design references (none in the repository), real Supabase behaviour (stand-ins are not Supabase), Edge Function deployment, SMS, Google/Apple sign-in, push notifications, and the first Codemagic run (stopped earlier because `EXPO_PUBLIC_SUPABASE_URL` / `EXPO_PUBLIC_SUPABASE_ANON_KEY` are not set in Codemagic).


## Support/SOS completion continuation — 2026-11-26

- Current integrated branch HEAD at start of this pass: `48b075e`.
- Source inspection confirms Android support/SOS is reachable from shared settings for rider and driver; iOS saved places, notifications/preferences, driver vehicles, receipts, and support/SOS are wired into Settings and ride history; Admin Support/SOS is permission-gated and has ticket/SOS status actions.
- Added migration 0012 for support staff notifications on new tickets/SOS, user notifications when ticket/SOS status changes, and per-user transaction locking for the SOS rate limit.
- Added SQL behavioral checks for the notification lifecycle. These have not been executed in this environment; migration 0012 has not been applied to any Supabase project.
- Native builds and device testing remain unverified. Admin typecheck/lint/build remain unverified here because dependencies cannot be installed.

## Verification of integrated head (executed, 2026-11-27)

Run on `feature/kherja-integrated` at 7fb6476 (migrations 0001-0012 on a throwaway PG16, never a real Supabase):

- SQL: 136 PASS lines, `ALL CHECKS PASSED` (stack_behavior incl. 0010) and `SUPPORT/SOS 0011 PASSED`.
- Admin: `bun install --frozen-lockfile` ok, `tsc -p tsconfig.app.json` 0 errors, vitest 12/12, eslint 0 errors (11 warnings), `vite build` ok.
- Edge function: `bun test` 70 pass / 0 fail.
- Static: every localisation key used on Android and iOS is defined (fr + ar); only intentional `app_tagline_ar` is fr-only.

Not executed (environment cannot): Android/iOS builds, device/simulator runs, RTL visual check, design comparison against reference images (none supplied), real Supabase, SMS, Google/Apple sign-in, push delivery, Codemagic (needs EXPO_PUBLIC_SUPABASE_URL / EXPO_PUBLIC_SUPABASE_ANON_KEY).

## Phase 1 – account deletion + iOS presence parity (not yet run on a device)
- `supabase/migrations/0013_delete_account.sql` (NOT applied to any Supabase project): `delete_my_account()` anonymises and closes the profile (`account_status='deleted'`), removes saved places, notifications, vehicles, driver documents rows and verified phone, keeps ride/wallet/message history. Refuses while a request/ride/delivery is active. Local PG16 tests: `supabase/tests/delete_account_0013.sql` (13 checks, all PASS on a disposable database).
- Android + iOS: "Supprimer mon compte / حذف حسابي" with a confirmation dialog in Settings; on success the user is signed out; a session whose profile is `deleted` is signed out with a notice.
- Known limitation: the Supabase Auth identity is not removed (needs an Edge Function deploy), so the phone number stays registered to the closed account.
- iOS driver presence now also calls `ping_location` (same as Android).
- Not built or run on Android/iOS in this environment.

## Phase 2 – suspended passengers
- Suspended passenger accounts previously got no gate (every action failed with "Account suspended"). Android now wraps the passenger tabs in `DriverGate(driverRules = false)`; iOS shows `DriverStatusView(.suspended, showSignOut: true)` instead of the tab bar. Not built or run on a device here.

## Phase 3 – admin account-state and detail-query handling

- Admin passenger/driver lists now include a dedicated deleted-account filter and count, and render deleted accounts as deleted rather than active.
- Deleted profiles no longer expose driver approval, suspension, or reactivation actions in the Admin UI.
- Added migration 0014 to make deleted accounts terminal in `admin_set_account_status`; privileged account-status changes cannot reactivate a deleted profile. Migration 0014 is committed only and has NOT been applied to Supabase.
- Restored the historical migration 0002 unchanged; the new guard lives in additive migration 0014.
- Admin person-detail panels now render errors from the ride-history and driver-phone-verification queries instead of silently omitting those sections.
- No builds or tests were run in this development pass. Supabase TEST and deployed Edge Functions were not changed.
- Admin overview custom date ranges now validate missing/reversed dates, disable the invalid query, and show a bilingual inline message instead of producing an invalid timestamp/query key.

## Phase 4 – authenticated account deletion path (code only; not deployed)

- Android and iOS now call the authenticated `auth-otp` `delete_account` action. The Edge Function resolves the user from the verified bearer token, calls the idempotent profile-anonymisation RPC using that user's JWT, then deletes only that Auth identity using the service role.
- Active trips block deletion before Auth removal. If Auth deletion fails after profile anonymisation, the endpoint returns an explicit retryable partial-state response; the RPC is idempotent for retry.
- A schema review found `profiles.id → auth.users.id ON DELETE CASCADE`; migration 0015 removes that FK so deleting the Auth identity cannot cascade-delete the anonymised profile and retained ride/wallet/message history.
- Migration 0015 also replaces `delete_my_account()` to remove private driver-document Storage objects before deleting their metadata.
- Handler tests and a disposable-Postgres migration test are being added. Migration 0015 and Edge Function code are not applied/deployed to Supabase. Native builds remain unrun.
- Follow-up migration 0016 converts remaining nullable foreign keys to `auth.users` (creator, reviewer, publisher, and audit actors) to `ON DELETE SET NULL`, while keeping cascade only for identity-owned rows. This prevents historical audit/admin metadata from blocking Auth deletion.
