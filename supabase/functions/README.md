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
    `payment.failed`, `order.paid`

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

### Running the shared-logic unit tests

```bash
cd supabase/functions
deno test --allow-net _shared/razorpay.test.ts
```

No live Supabase or Razorpay connection needed — signature verification,
status mapping, and the state-machine transitions are pure functions;
Razorpay HTTP calls are tested against a mocked `fetch`.