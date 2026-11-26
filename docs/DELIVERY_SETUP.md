# KHERJA parcel delivery — Phase 3

## Scope

This is a separate parcel-delivery workflow. It does not reuse or mutate passenger ride requests, ride offers, or ride records.

## Price and payment decision

- Car: 90 DZD per trusted kilometre.
- Motorcycle: 60 DZD per trusted kilometre, minimum 350 DZD.
- Price is calculated on the server and rounded to the nearest 10 DZD.
- Cash on delivery only for this phase.
- No delivery commission is charged until the owner approves a delivery-specific commission policy.

The server recalculates trusted distance from coordinates; client-supplied distance is not accepted as authoritative.

## Passenger flow

1. Use the device's current location as pickup.
2. Search and choose a destination.
3. Enter package description, recipient name and phone, and optional note.
4. Request a server quote and create the delivery order.
5. Follow the order state; cancel while it is still unassigned.

## Driver flow

1. Driver must have an active account, approved driver status, and be online.
2. The feed returns only open orders and deliberately excludes recipient contact details.
3. Driver claims an order atomically; recipient contact details become visible only to the assigned driver.
4. Driver advances status from accepted to picked_up, then delivered.

A driver cannot claim while already handling an active ride or delivery. Database indexes prevent multiple active delivery jobs for the same driver or passenger.

## Backend

Migration: `supabase/migrations/0008_delivery.sql`

RPCs:
- `quote_delivery`
- `create_delivery_order`
- `open_delivery_feed`
- `claim_delivery_order`
- `update_delivery_status`
- `cancel_delivery_order`

Open orders expire after 15 minutes. The driver feed marks stale open orders expired before returning current requests.

## Deployment and verification

- Migration 0008 is committed but has **not** been applied to Supabase.
- Do not apply it to production without explicit owner approval.
- First apply it to a disposable Supabase project after the existing migrations 0001–0007.
- Verify RLS with passenger A, passenger B, approved online driver, offline driver, unapproved driver, and a different assigned driver.
- Verify concurrent claims, duplicate active requests, expiry, cancellation, invalid status transitions, quote calculations, and recipient phone redaction.
- Android and iOS have not been compiled or device-tested in this implementation pass. Complete platform builds and end-to-end tests before release.
