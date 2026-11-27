# KHERJA UI completion tracker

This tracker is based on the existing Android, iOS, and admin source tree plus the owner-approved screen inventory. It is a working implementation checklist, not a claim that every item is finished.

## Design contract

- Primary blue: `#075BFF`
- Burgundy: `#85003F`
- White: `#FFFFFF`
- Canvas: `#F7F8FC`
- Light blue: `#EEF3FF`
- Light burgundy: `#F9EDF3`
- Ink: `#151A2D`; muted text: `#777E91`; borders: `#E8EAF1`
- Arabic must be native RTL; French must be native LTR.
- Keep passenger, driver, and admin navigation separate.
- Never replace the supplied KJ logo or introduce green/purple as brand colors.
- No invented live driver identities, ratings, prices, or operational data.

## Existing screen coverage found in source

| Area | Existing implementation | Current assessment |
|---|---|---|
| Shared entry/auth | Splash, language, role, phone OTP, password/social auth, profile completion | Implemented in code; native builds still need verification |
| Passenger ride request | Home, pickup/destination search, car/motorcycle, server quote, proposed fare | Implemented; iOS home map preview added in this branch |
| Passenger negotiation | Offers and negotiation sheet, accept/counteroffer flow | Implemented in code; end-to-end state transitions need verification |
| Passenger active ride | Ride tracking, driver details/actions, completion state | Implemented in code; live GPS freshness and device behavior unverified |
| Passenger history | Filters and ride details | Implemented in code |
| Passenger wallet | Transaction history and balance summary | Implemented in code; actual payment/withdrawal flows are not approved |
| Passenger settings | Profile, language, city, logout, saved places, notifications/preferences, help/privacy/about, and support/SOS are present in Android and iOS source | Implemented in source; native builds and device verification pending |
| Parcel delivery | Passenger create/quote/status/cancel; driver feed/claim/status | Phase 3 code exists; migration and client builds remain unverified |
| Driver account gate | Pending/rejected/suspended states | Implemented in code |
| Driver dashboard | Online state, requests feed, offer sheet, active ride | Implemented in code |
| Driver vehicle profile | Make/model/plate/color editing, vehicle category management, driver documents, and support/SOS are present in Android and iOS source | Implemented in source; native builds and end-to-end Storage/RPC verification pending |
| Driver earnings/history | Wallet/transactions and ride history | Implemented in code; payout/withdrawal workflow not approved |
| Admin | Login, overview, live map, rides, drivers, passengers, pricing, admins, audit, vehicles, notifications, reports, settings, and Support/SOS | Screens and role-gated actions are present in source; typecheck/build and live-backend verification pending |

## Remaining development before verification

### Passenger
- Saved places management/selection, notification inbox/preferences, help/about/privacy information, and ride receipt/share are already present in Android and iOS source.
- Location denial now has Settings/retry guidance on Android and a Settings action on iOS; iOS saved-place loading errors are surfaced. Remaining: finish address-search empty/error review and compare the full passenger journey against approved designs.
- Official privacy/terms wording and a verified support contact still require owner approval; current informational panels are not legal policy documents.

### Driver
- Profile details (make/model/plate/color), ride/delivery flows, notification/help/settings access, wallet/history, and document review status are present in source.
- Driver document upload accepts JPEG/PNG/HEIC/PDF on both Android and iOS; the private Storage bucket already permits PDF. Real uploads and signed preview/download still need device verification.
- Vehicle category/type model needs an owner decision before adding or changing a persisted field.
- Withdrawal/payout workflow must wait for approved commission, payout provider and settlement rules.

### Admin
- Overview, live map, rides, drivers, passengers, pricing, admins, audit, vehicles, notifications, reports/CSV export, settings and Support/SOS are present in source.
- Deleted-account filtering, terminal-state protection, deleted/staff metric exclusions and broadcast suppression are implemented in Admin source/SQL.
- Remaining: finish secondary-query loading/error/empty-state review and compare the full Admin workflow against the live schema after migrations are approved.

### Backend integrations
- Auth account deletion is implemented in code; profile anonymisation, private Storage API cleanup and Auth identity removal are sequenced with retry-safe partial states. Migrations 0015–0016 and the updated auth-otp Edge Function are not deployed.
- Push registration and FCM/APNs delivery are implemented in code; migration 0017, Edge Function deployment, webhook and provider credentials are not configured.
- Migration 0018 prevents deleted profiles from receiving new notifications and excludes deleted/staff profiles from customer metrics/broadcasts; it is not deployed.
- SMS OTP provider/dev-mode setup is still deferred until the development scope is complete.

## Verification gates

- Android: run Gradle unit tests and assemble the debug APK; resolve all compile errors.
- iOS: run Xcode build and tests on macOS/CI; resolve all compile errors.
- Backend: test migrations and RLS against disposable Supabase only.
- E2E: passenger request → driver offer → passenger acceptance → driver arrival/start/complete → history/receipt.
- E2E delivery: passenger create → driver claim → pickup → delivered → privacy checks.
- RTL/LTR: verify Arabic and French on real device/simulator.
- Visual QA: compare every implemented screen against the approved design assets available in the project library.
- Production: no migration, function deployment, secret change, or data mutation without explicit owner approval.

## Change log

- 2026-11-26: Added a native iOS passenger-home map preview using the existing MapKit route component, with pickup/destination pins and a useful Algiers fallback region while location permission resolves. This has not yet been compiled in Xcode.
- 2026-11-26: Added Arabic/French help, privacy-information, and about panels to Android and iOS settings. These are informational panels only; official legal copy and a support contact still need owner approval.
- 2026-11-26: Corrected the Android driver delivery-tab icon to use the parcel/shipping symbol.
- 2026-11-26: Migration 0011 (support tickets, SOS alerts, support contact RPC, staff permissions support.read/manage) with behavioural tests; local throwaway Postgres only (132 PASS lines, 0 FAIL across the full suite).
- 2026-11-26: iOS parity (uncompiled): saved places, notifications + preferences, driver vehicles, ride receipt with share, support + SOS (ExtrasViews.swift, ExtrasData.swift, ExtrasStrings.swift), wired into Settings and ride detail.
- 2026-11-26: iOS passenger home had no address picker (`pickSheet` was never presented and `pickup`/`destination` were never assigned), so a ride could not be requested. Added AddressPicker.swift (saved places, current location, Apple Maps search) and a default pickup from GPS. Uncompiled and untested.
- Still open: native Android/iOS compilation and device testing; admin typecheck/lint/build on an environment with installable dependencies; real Supabase migration verification and push-provider delivery. Support/SOS screens and admin ticket/SOS management are now present in source.


## Support/SOS integration pass — 2026-11-26

- Verified Android Support/SOS is reachable from the shared Settings screen for both rider and driver roles and calls migration 0011 APIs.
- Verified iOS saved places, notification preferences/inbox, driver vehicles, ride receipt, and Support/SOS views are wired through Settings and ride history.
- Verified the Admin Support page is routed behind `support.read` and its status actions call the permission-checked migration 0011 RPCs.
- Added migration 0012 to send in-app notifications to support staff for new tickets/SOS alerts and to ticket/SOS owners when statuses change.
- Migration 0012 also serializes concurrent SOS submissions per user so the 3-per-10-minute limit cannot be bypassed by simultaneous requests.
- Added behavioral SQL checks for staff/user notifications. Migration 0012 remains unapplied; no live Supabase project was changed.
- Native compilation, admin package checks, and device-level RTL/LTR verification remain pending because this environment has no repository checkout, Xcode/Android SDK, or installable admin dependencies.


## Development updates — 2026-11-27

- Added authenticated account deletion through auth-otp, with profile anonymisation before Auth identity removal and FK changes to preserve ride/wallet/audit history (migrations 0015–0016).
- Added Admin terminal deleted-account protection test for migration 0014.
- Added push-device registration RPCs and FCM/APNs webhook delivery implementation (migration 0017), plus native token registration/permission handling scaffolding. Provider setup remains owner-dependent.
- Added PDF selection/upload for driver documents on Android and iOS; no Storage schema change was needed because migration 0003 already permits PDF.
- Added Admin deleted-account metrics, staff/deleted broadcast exclusion, and notification suppression (migration 0018).
- These changes are source-only. No Supabase deployment, provider secret changes, native builds, or final tests were performed.

## Development updates — 2026-11-27

- Completed authenticated account deletion path with retry-safe private Storage cleanup and Auth identity removal; backend changes remain code-only.
- Added private push-device registration, FCM/APNs delivery, invalid-token cleanup, and native permission/token handling. Provider credentials, entitlements and webhook are not configured.
- Added PDF driver document uploads on Android/iOS and improved passenger location-permission error guidance.
- Added deleted-account metrics/broadcast suppression, Admin secondary-query errors, and live-map loading/empty-state refinements.
