# Web ↔ Flutter parity audit

**Date:** 2026-09-03
**Method:** behavioral / capability parity — diff of every `supabase.rpc(...)` and
`functions.invoke(...)` call on each side, plus a route/screen and per-action
cross-check. Visual/styling differences are out of scope.
**Scope:** everything (no exclusions requested). Public unauthenticated flows are
listed but marked N/A — an admin client has no surface for them.

## Headline

The Flutter port is at capability parity across **auth, onboarding (facility /
sports / courts / hours / pricing), the owner dashboard, bookings grid + guest
booking wizard + guest bookings admin, guests, memberships (list / create /
detail / cancel / plans), membership sessions (batches / occurrences / capacity
/ guest slots / activity), refunds + settlement exceptions, and the entire
finance module (Phases 8–14)**. Every client-invoked edge function is wired.

The gaps below are the complete set of RPCs the web calls that Flutter does
not, resolved to the feature they belong to.

## Edge functions — full parity

Both clients invoke: `create-razorpay-order`, `verify-razorpay-payment`,
`reconcile-razorpay-payment`, `settle-payment`, `create-membership-subscription`,
`cancel-booking`, `cancel-membership`, `cancel-membership-slot`,
`create-razorpay-refund`, `send-booking-receipt`, `download-transaction-receipt`.
(`razorpay-webhook` is server-to-server.) **No gap.**

## RPC gaps

| # | RPC | Web surface | Flutter today | Severity |
|---|-----|-------------|---------------|----------|
| **G1** | `get_membership_revenue_timeseries` | `memberships/components/membership-revenue-trend.tsx` — a revenue trend chart on the Memberships page | Memberships page shows the "Revenue (this month)" KPI + change % only; no trend chart | Medium |
| **G2** | `set_facility_membership_access_days` | `memberships/components/membership-access-days-dialog.tsx` (opened from the Memberships page) sets which weekdays memberships grant access; `create-membership-page.tsx` seeds `defaultAccessDays` from it | No equivalent anywhere in Flutter | Medium |
| **G3** | `list_assignable_batches` | `memberships/components/court-time-slot-section.tsx` in the Create Membership flow — lets you attach the new member to an **existing** session batch, or define a fresh time slot | `create_membership_screen.dart` only supports defining a fresh custom time slot (`showTimePicker` for start/end); the "existing batch" path is absent | Medium |
| **G4** | `record_session_guest_payment` | `bookings/components/guest-booking-actions.tsx` — for a released membership seat (`source = 'SESSION'`), the only actions are **Record Payment** (this RPC) and Download Invoice; the COURT action set is hidden | `GuestBookingRow.fromJson` **ignores the `source` column**, so SESSION rows render with the full COURT action set (edit / reschedule / cancel / duplicate / delete) — none of which apply — and there is no session-payment path at all | **High — correctness** |
| **G5** | *(no RPC — client-side)* `buildBookingDocument` / `openPrintable` | "Download Invoice" in `guest-booking-actions.tsx` (both COURT and SESSION rows) builds a printable invoice/bill in the browser | No invoice/bill export from guest bookings | Low |

### Public flows — N/A (admin client has no surface)

`get_public_booking_facility`, `get_public_court_availability`,
`public_create_guest_booking`, `get_public_membership_signup_info`,
`get_public_signup_batches`, `public_start_membership_signup` — the public
booking flow (`/book/[facilityId]`) and public membership join
(`/join/[facilityId]`, `join-membership-form.tsx`). Intentionally absent from an
admin app. **Not gaps.**

## Fill order

1. **G4** (correctness) — parse `source`, gate the guest-bookings action set on
   it, add `recordSessionGuestPayment` + a Record Payment action for SESSION
   rows. Mirrors `guest-booking-actions.tsx`.
2. **G2** — membership access-days setting + seeding it into Create Membership.
3. **G3** — "attach to existing batch" option in Create Membership's time-slot step.
4. **G1** — membership revenue trend chart.
5. **G5** — guest-booking invoice export (low priority; needs a Flutter PDF/print story).

Each is a vertical slice (repo method → screen wiring → test), committed
independently, same working pattern as the finance rework.

## Testing

`cd mobile && flutter test` green + `dart analyze` clean per slice. Repo methods
get a source-contract + model-mapping test in the style of
`finance_*_test.dart`; pure logic (e.g. which actions a `source` allows) gets a
unit test.
