# KHERJA continuation: progress

Branch `feature/kherja-continue` (pushed to GitHub). Base: 00454e4.

| Phase | Status |
|---|---|
| Codemagic Android setup | done (on `codemagic/android-setup`) |
| Phase 1 audit and design comparison | done, accepted |
| Phase 2 login: OTP security, backend, Android, iOS, social phone linking, docs | code complete; mobile clients remain uncompiled and untested (see `docs/AUTH_SETUP.md`) |
| Phases 3 to 9 (delivery, business, wallet, payments, campaign, extras, security) | not started; login comes first |

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
