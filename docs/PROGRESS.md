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
