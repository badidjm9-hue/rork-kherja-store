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
| Passenger settings | Profile fields, language, city, logout | Partial: help, privacy, saved places, notifications, and about screens are absent |
| Parcel delivery | Passenger create/quote/status/cancel; driver feed/claim/status | Phase 3 code exists; migration and client builds remain unverified |
| Driver account gate | Pending/rejected/suspended states | Implemented in code |
| Driver dashboard | Online state, requests feed, offer sheet, active ride | Implemented in code |
| Driver vehicle profile | Make/model/plate editing | Partial: vehicle type details and document upload/verification UI are absent |
| Driver earnings/history | Wallet/transactions and ride history | Implemented in code; payout/withdrawal workflow not approved |
| Admin | Login, overview, live map, rides, drivers, passengers, pricing, admins, audit | Core admin exists; dedicated vehicle, notification, reports, and admin-settings screens remain absent |

## Next interface work, in order

### Passenger
- Saved locations management and selection.
- Notifications list and notification preferences.
- Help/support center and About KHERJA.
- Privacy screen linked to owner-reviewed legal text.
- Full ride receipt and share action.
- Explicit location permission and location-search empty/error states.

### Driver
- Driver personal details and vehicle type selection.
- Document upload/review states (requires private Storage bucket and owner-approved retention policy before upload can be functional).
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
