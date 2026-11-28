# Demo accounts (TEST environment only)

| Role | Phone (sign-in) | Password |
|---|---|---|
| Passenger demo | `0500000001` | not stored here — held by the project owner |
| Driver demo | `0500000002` | not stored here — held by the project owner |

This repository is public, so passwords are never committed. Sign in with **phone number + password**.

- Project: the Supabase test project `kherja-test`. Production must never contain these accounts.
- Create or reset them with `supabase/seed/demo_accounts.sql` (instructions in the file header).
- Builds must point `EXPO_PUBLIC_SUPABASE_URL` / `EXPO_PUBLIC_SUPABASE_ANON_KEY` at the test project.
- Role limits are enforced by the database (RLS, RPC checks and the driver-approval workflow), not by the UI.
- Remove them before any test data is promoted: delete both users in Supabase Auth.
