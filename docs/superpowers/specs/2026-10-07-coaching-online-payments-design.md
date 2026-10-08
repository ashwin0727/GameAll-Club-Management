# Coaching enrollment — Razorpay online payments (design)

Date: 2026-10-07 · Branch: `feat/coaching-management` · Migration: `0110_coaching_online_billing.sql`

## Goal
In *Add Student → Payment*, besides Offline / Pay Later, a staff member can collect through Razorpay:

- **One-time program** → a Razorpay **Payment Link** for the full enrollment fee; the enrollment is
  marked paid when the `payment_link.paid` webhook arrives.
- **Monthly program** → a Razorpay **Subscription** (UPI AutoPay mandate approved once) that charges
  the per-month fee every month until the program end date.

## Decisions (approved)
- `coaching_programs.fee_type` = `ONE_TIME` (default) | `MONTHLY`. For MONTHLY, `default_price_minor` is the
  **per-month** fee, and the program must have a start and end date.
- Enrollment snapshots `fee_type` and `billing_cycles` (BEFORE INSERT trigger — no change to
  `create_coaching_enrollment`'s signature). `billing_cycles = full months between enrollment start and
  program end + 1` (min 1). Enrollment `price_minor` stays the **total obligation** = per-cycle × cycles, so
  Pending Payments / Finance / receipts are unchanged.
- Tax and early-bird discount apply **per cycle**: cycle fee = (price − discount) + tax.
- Offline / Pay Later stay available for monthly programs, but are locked once a link/subscription exists.
  The program's existing `payment_mode` (OFFLINE | ONLINE | BOTH) is honoured: the online option is hidden
  for OFFLINE programs, the offline options are hidden for ONLINE programs.
- The student is enrolled immediately; payment status follows the webhook.

## Components
1. **DB (0110)**: `fee_type` columns + cycles trigger; `coaching_enrollment_billing` (1 row / enrollment, kind
   PAYMENT_LINK | SUBSCRIPTION, status, Razorpay ids, short_url, charge_count); RPCs
   `set_coaching_program_fee_type`, `get_coaching_billing_context` (user, permission-checked, used by the edge
   function), `record_coaching_enrollment_billing`, `mark_coaching_billing_cancelled`,
   `apply_coaching_billing_webhook` + `record_coaching_gateway_payment` (service role only, idempotent on
   `razorpay_payment_id`; the latter inserts a normal `payments` row with `coaching_enrollment_id`).
2. **Edge functions**: `create-coaching-enrollment-billing` and `cancel-coaching-enrollment-billing` (both run under
   the caller's JWT; amount always read server-side). `razorpay-webhook` gains `payment_link.paid|expired|cancelled`
   and routes `subscription.*` to coaching when the subscription belongs to an enrollment (else membership path).
3. **Web**: Fee Type in the program wizard + program edit; Payment step third option; enrollment details billing
   card; cancelling an enrollment cancels live billing.
4. **Flutter**: same, in the mobile coaching module.

## Out of scope
Refund of gateway payments (existing refund flow applies), changing a subscription's amount after creation,
public self-enrolment links.

## Deploy notes (user-run)
Apply 0110; deploy `create-coaching-enrollment-billing`, `cancel-coaching-enrollment-billing`, `razorpay-webhook`;
add `payment_link.paid`, `payment_link.expired`, `payment_link.cancelled` to the Razorpay webhook events; Payment
Links + Subscriptions must be enabled on the Razorpay account.
