# KHERJA continuation: progress

Branch `feature/kherja-continue` (local only, not pushed). Base: 00454e4.

| Phase | Status |
|---|---|
| Codemagic Android setup | done (on `codemagic/android-setup`) |
| Phase 1 audit and design comparison | done, accepted |
| Phase 2 login: OTP security, backend, Android, iOS, docs | code complete, client code unverified (see docs/AUTH_SETUP.md section 5) |
| Phases 3 to 9 (delivery, business, wallet, payments, campaign, extras, security) | not started, by instruction login comes first |

## Commits
- 5e3d697 auth-otp: production-safe OTP, password login, register, reset, rate limits, migration 0005, 62 tests
- e102fe7 Android login/register/forgot, Google/Apple via Supabase OAuth PKCE
- 66375e2 iOS login/register/forgot, native Apple and Google

## Owner decisions in force
Commission 15%/12% unapproved placeholders (admin-configurable); passenger payments cash only; Flexy/BaridiMob/Chargily for driver commission only; per-role navigation; illustrative screenshot prices; delivery 90/60 DZD/km with 350 DZD motorcycle minimum; splash variant undecided.
