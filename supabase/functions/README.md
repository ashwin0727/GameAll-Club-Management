# Edge Functions

## create-razorpay-order

Creates a GameAll payment order (facility-scoped, server-priced) and a matching
Razorpay **test-mode** order. See the comment block at the top of
`create-razorpay-order/index.ts` for the full flow.

### Where to set up the Razorpay test keys

1. Get your test keys from the Razorpay Dashboard: **Settings → API Keys**
   (make sure the dashboard is switched to **Test Mode**, top-left toggle).
   You'll get a Key ID (`rzp_test_...`) and a Key Secret — the secret is only
   shown once, save it somewhere safe.
2. Set them as **Supabase Edge Function secrets** — never in `.env.local`,
   never in any file committed to git, never anywhere the browser or the
   Flutter app can read them:

   ```bash
   supabase link --project-ref <your-project-ref>   # once, if not already linked
   supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxxxxxxxxxxxx
   supabase secrets set RAZORPAY_KEY_SECRET=<your test key secret>
   ```

   Or via the Supabase Dashboard: **Project Settings → Edge Functions →
   Secrets**, add both there instead of the CLI.

3. Deploy the function:

   ```bash
   supabase functions deploy create-razorpay-order
   ```

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are provided automatically to every
Edge Function by the Supabase platform — nothing to configure for those.

### What the client needs

Only `RAZORPAY_KEY_ID` is ever sent back to Flutter/Web (Razorpay Checkout
needs it to open the payment sheet) — it's returned in the function's JSON
response, not baked into client config. `RAZORPAY_KEY_SECRET` never leaves
this function.

### Verifying it's live

The function refuses to run at all unless `RAZORPAY_KEY_ID` starts with
`rzp_test_` — this phase is test-mode only by design, not by convention.
If you see `"Payments are not configured yet."`, the secrets above haven't
been set on this Supabase project yet. If you see `"Payments are only
available in test mode right now."`, a live (`rzp_live_...`) key was set by
mistake.

### Local development

```bash
supabase functions serve create-razorpay-order --env-file supabase/functions/.env.local
```

Create `supabase/functions/.env.local` (already gitignored — see
`.gitignore`) with the same two `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET`
values for local testing against the Supabase CLI's local stack.

## verify-razorpay-payment / razorpay-webhook / reconcile-razorpay-payment

Phase 4 — server-side verification, webhook handling, and reconciliation.
The client is never trusted as the final word on payment success; these
three functions are what actually decide `payment_orders.status`. See the
comment block at the top of each `index.ts`, and
`0019_payment_verification.sql`'s `apply_payment_verification` — the
shared, atomic, forward-only state-machine gate all three call into.

- **verify-razorpay-payment** — called by Flutter/Web right after Razorpay
  Checkout's own success callback. Re-derives the truth server-side
  (signature + a direct Razorpay API call) rather than trusting the
  client's claim. Uses the same `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET`
  secrets as `create-razorpay-order`.
- **reconcile-razorpay-payment** — a manual "check again" a client can call
  when a payment is stuck pending (lost callback, slow webhook). Same
  secrets as above.
- **razorpay-webhook** — the authoritative, Razorpay-triggered path.
  Needs one additional secret, **distinct from `RAZORPAY_KEY_SECRET`**:

  ```bash
  supabase secrets set RAZORPAY_WEBHOOK_SECRET=<a secret you choose>
  ```

  Set the exact same value in the Razorpay Dashboard: **Settings →
  Webhooks → Add New Webhook**:
  - URL: `https://<your-project-ref>.supabase.co/functions/v1/razorpay-webhook`
  - Secret: the same value you just set above
  - Active events: `payment.authorized`, `payment.captured`,
    `payment.failed`, `order.paid`, `refund.created`, `refund.processed`,
    `refund.failed` (Phase 6)

  This function also reads `SUPABASE_SERVICE_ROLE_KEY` — already provided
  automatically to every Edge Function, nothing to configure — because
  there is no signed-in user for Razorpay's server-to-server call to run
  as. It is the only function in this project that does.

Deploy all three the same way as `create-razorpay-order`:

```bash
supabase functions deploy verify-razorpay-payment
supabase functions deploy razorpay-webhook --no-verify-jwt
supabase functions deploy reconcile-razorpay-payment
```

`--no-verify-jwt` is required for `razorpay-webhook` — Razorpay's request
carries no Supabase auth header at all (it authenticates via the webhook
signature instead), so Supabase's default JWT gate would reject it before
the function ever runs.

## settle-payment

Phase 5 — payment settlement & business confirmation. Settlement (confirm
the booking / activate the membership) normally already happens
automatically: `apply_payment_verification` calls the `settle_payment`
Postgres function inline, in the same transaction, the instant a payment
genuinely reaches CAPTURED (see `0021_payment_settlement.sql`). This
function exists only as a manual retry path for the rare case where that
inline settlement hit a transient failure — a payment order stuck at
CAPTURED. It's fully idempotent, and needs no Razorpay secrets at all (it
never calls Razorpay — just re-runs the settlement RPC). Deploy the same
way:

```bash
supabase functions deploy settle-payment
```

## Cancellation, Refund & Payment Recovery — Phase 6

Cancelling a paid booking/guest-slot (or membership) and refunding it never
happens client-side (spec §"Core Principle") — four new Edge Functions:

- **cancel-booking** — cancels a `bookings` row (member or ad-hoc guest
  booking), releases court availability (free — the existing exclusion
  constraint already excludes cancelled rows), and if the booking was paid,
  requests a cancellation-policy-derived refund and submits it to Razorpay
  in the same call.
- **cancel-membership-slot** — the same flow for a released-capacity guest
  booking (`membership_session_bookings` row).
- **cancel-membership** — membership cancellation; the refund amount (if
  any) is an explicit owner/manager decision, never policy/time-derived
  (spec §14/§15).
- **create-razorpay-refund** — the owner's manual "Initiate Refund" entry
  point: a partial/manual refund on any settled payment, or resolving a
  SETTLEMENT_EXCEPTION with a full refund (spec §16).

All four share `_shared/submit-refund.ts`'s "take a REQUESTED refund row to
Razorpay" step, and all four funnel eligibility/over-refund/concurrency
protection through the `request_refund` Postgres function
(`0023_cancellation_refunds.sql`) — never a second refund-writing path.

`razorpay-webhook` now also handles `refund.created`, `refund.processed`,
and `refund.failed` (via `apply_refund_webhook`) — the only path that ever
marks a refund `PROCESSED` and updates `payment_orders.status` to
`REFUNDED`/`PARTIALLY_REFUNDED`; a client "Check Again" cannot resolve a
refund the way it can a payment (there is no refund-reconciliation
equivalent — refund state is webhook-driven only, spec §22).

No new secrets: refunds reuse `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET`, and
`refund.*` webhook events are covered by the existing
`RAZORPAY_WEBHOOK_SECRET`-verified endpoint.

```bash
supabase functions deploy cancel-booking
supabase functions deploy cancel-membership-slot
supabase functions deploy cancel-membership
supabase functions deploy create-razorpay-refund
supabase functions deploy razorpay-webhook --no-verify-jwt
```

## Finance & Revenue Management — Phase 7

**No new Edge Functions.** Finance is a reporting layer over the existing
`payments` / `refunds` / `settlement_exceptions` records — it never talks to
Razorpay, so there is nothing that needs a secret and nothing to deploy
here. All aggregation lives in Postgres (`0024_finance.sql`) as RLS-scoped,
explicitly authorization-checked RPCs the clients call directly:

- `get_finance_summary` — gross / refunds / net + transaction and
  payment-outcome counts for a date range
- `get_revenue_breakdown` — revenue by source (membership / member booking /
  guest booking), plus included-membership usage as a count, never revenue
- `get_revenue_trend` — daily/weekly/monthly buckets for the chart
- `list_finance_transactions` / `count_finance_transactions` /
  `get_finance_transaction` — server-side filtered, searched, paginated
  transaction reads over `finance_transactions_view`

Every date preset ("Today", "This Week", …) resolves to real timestamps in
the **facility's own configured timezone** via `resolve_finance_date_range`
— the clients never compute date boundaries themselves.

`list_refunds` and `list_settlement_exceptions` (Phase 6) gained optional
status/source/date-range filter parameters in this migration; every existing
caller keeps working unchanged since the new parameters all default to "no
filter".

### Running the shared-logic unit tests

```bash
cd supabase/functions
deno test --allow-net _shared/razorpay.test.ts _shared/settlement.test.ts _shared/refunds.test.ts _shared/finance.test.ts
```

No live Supabase or Razorpay connection needed — signature verification,
status mapping, the payment/refund state-machine transitions, cancellation-
policy percent calculation, refundable-amount/over-refund math, revenue
aggregation (gross/refund/net, revenue-by-source classification, duplicate
protection), and the settlement routing/exception-reason logic are all pure
functions; Razorpay HTTP calls are tested against a mocked `fetch`.