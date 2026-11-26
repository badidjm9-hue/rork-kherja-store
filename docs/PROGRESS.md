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
