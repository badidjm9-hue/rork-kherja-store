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

## Next interface work, in order

### Passenger
- Saved locations management and selection.
- Notifications list and notification preferences.
- Help/support center and About KHERJA.
- Privacy screen linked to owner-reviewed legal text.
- Full ride receipt and share action.
- Explicit location permission and location-search empty/error states.

### Driver
- Driver personal details and vehicle category/type selection (requires a separately approved persisted field).
- Driver document review workflow is wired to the existing private driver-documents bucket, driver_documents table, and submit_driver_document RPC defined in migration 0003; verify that migration is applied to the target Supabase project before testing uploads. The client pickers now accept images and PDF files; actual device upload and preview verification remain pending.
- Driver verification details and resubmission state.
- Dedicated notification, help, and settings screens.
- Earnings breakdown and withdrawal request only after commission/payout rules are approved.

### Admin
- Vehicle management.
- Notification management.
- Reports and exports.
- Admin settings and operational configuration.
- Driver document review, with least-privilege access and audit trail.

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
