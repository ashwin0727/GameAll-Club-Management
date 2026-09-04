# P1 Transaction Hardening — Design & Plan

**Goal:** Close the four P1 findings from the 2026-09-04 core-transaction audit: refund
double-submit, uncaptured Razorpay payments, public-booking abuse, and the absence of a
DB integration test harness.

**Spec source:** the audit report (this conversation). No behaviour changes beyond the four
fixes; nothing is rebuilt for style.

## Global constraints

- Migrations are additive. Next numbers: `0064`, `0065`. The user applies migrations and
  deploys edge functions themselves.
- Edge functions: Deno, `jsr:@supabase/supabase-js@2`, pure logic in `_shared/` stays
  Supabase/Deno-free so `deno test` can cover it.
- Money is in minor units (paise) on the payment/refund path.
- Public booking is **web only** — `mobile/` has no public booking flow.
- All new RPCs that anon calls are `SECURITY DEFINER` with `set search_path = public` and an
  explicit check where they touch privileged data.

---

## Part 1 — Refund submission race

**Defect:** `_shared/submit-refund.ts` reads `get_refund`, checks `status === "REQUESTED"` in
JS, then calls Razorpay. Two concurrent edge invocations both pass → two real refunds.

**Fix:** atomic claim in Postgres before the Razorpay call.

### Migration `0064_refund_submission_claim.sql`

```sql
-- claim_refund_for_submission: CAS REQUESTED -> PROCESSING. The caller that
-- gets a row back owns the Razorpay Refund API call; every other concurrent
-- caller gets NULL and must not call Razorpay.
create function claim_refund_for_submission(p_refund_id uuid) returns refunds
language plpgsql as $$
declare result refunds;
begin
  update refunds set status = 'PROCESSING'
    where id = p_refund_id and status = 'REQUESTED'
    returning * into result;
  return result;  -- NULL row when not claimed
end;
$$;
grant execute on function claim_refund_for_submission(uuid) to authenticated;

-- set_refund_razorpay_id: attach the id once, never overwrite.
create function set_refund_razorpay_id(p_refund_id uuid, p_razorpay_refund_id text) returns refunds
language plpgsql as $$
declare result refunds;
begin
  update refunds set razorpay_refund_id = coalesce(razorpay_refund_id, p_razorpay_refund_id)
    where id = p_refund_id
    returning * into result;
  return result;
end;
$$;
grant execute on function set_refund_razorpay_id(uuid, text) to authenticated;
```

### `_shared/submit-refund.ts` rewrite

```
load refund via get_refund
if status !== "REQUESTED" -> return { refundId, status }          // already handled
claimed = rpc claim_refund_for_submission(refundId)
if !claimed?.id -> return { refundId, status: (re-read).status }   // lost the race, do NOT call Razorpay
try:
  rzp = createRazorpayRefund(...)
  updated = rpc set_refund_razorpay_id(refundId, rzp.id)
  return { refundId, status: updated?.status ?? "PROCESSING", razorpayRefundId: rzp.id }
catch err:
  rpc mark_refund_failed(refundId, String(err))     // PROCESSING -> FAILED (already supported)
  return { refundId, status: "FAILED" }
```

`mark_refund_processing` (0023) is now unused by this path; leave it in place (harmless, no
other callers change). The webhook fallback in `apply_refund_webhook` (lookup by
`razorpay_payment_id`) already covers "Razorpay call succeeded, function died before
`set_refund_razorpay_id`" — unchanged.

**Files:** `supabase/migrations/0064_refund_submission_claim.sql` (new),
`supabase/functions/_shared/submit-refund.ts` (rewrite),
`supabase/functions/_shared/refunds.test.ts` (add claim-race unit coverage where feasible),
integration test in Part 4.

No client changes. All four refund edge functions funnel through `submitRequestedRefund`.

---

## Part 2 — Uncaptured Razorpay payments

**Defect:** `create-razorpay-order` sends no `payment_capture`; nothing ever captures an
`authorized` payment; `reconcile` treats `AUTHORIZED` as non-terminal with no way forward.

### `_shared/razorpay.ts`

Add:

```ts
/** Captures an authorized payment. Treats Razorpay's "already captured" (400) as success by re-fetching. */
export async function captureRazorpayPayment(
  paymentId: string, amountMinor: number, currency: string, keyId: string, keySecret: string,
): Promise<RazorpayPayment> {
  const res = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}/capture`, {
    method: "POST",
    headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`, "Content-Type": "application/json" },
    body: JSON.stringify({ amount: amountMinor, currency }),
  });
  if (res.ok) return res.json();
  // Already captured, or a transient issue — re-fetch and let the caller decide.
  const payment = await fetchRazorpayPayment(paymentId, keyId, keySecret);
  if (payment.status === "captured") return payment;
  throw new Error(`Razorpay capture failed with status ${res.status}`);
}
```

Unit-testable? No (does fetch) — keep it thin, cover the decision in integration/manual.

### `create-razorpay-order/index.ts`

Add `payment_capture: 1` to the `POST /v1/orders` body (honored hint; harmless if ignored).

### `verify-razorpay-payment/index.ts`

After `fetchRazorpayPayment`, before `mapRazorpayPaymentStatus`:

```
if (razorpayPayment.status === "authorized") {
  try {
    razorpayPayment = await captureRazorpayPayment(
      razorpayPayment.id, razorpayPayment.amount, razorpayPayment.currency, razorpayKeyId, razorpayKeySecret);
  } catch (err) {
    console.error("[verify-razorpay-payment] capture failed", { paymentOrderId: order.id, error: String(err) });
    return jsonResponse({ error: "Unable to reach the payment gateway. Please try again shortly." }, 502);
  }
}
```

Then the existing `targetStatus = mapRazorpayPaymentStatus(razorpayPayment.status)` naturally
becomes `CAPTURED`.

### `reconcile-razorpay-payment/index.ts`

After `pickMostDecisivePayment`, if `decisive.status === "authorized"`, capture it the same
way (capture failure → 502), then reassign `decisive` to the captured payment and continue.

**Files:** `_shared/razorpay.ts`, `create-razorpay-order/index.ts`,
`verify-razorpay-payment/index.ts`, `reconcile-razorpay-payment/index.ts`. No migration, no
client changes.

---

## Part 3 — Public guest-booking abuse controls

**Defect:** `public_create_guest_booking` is a direct anon PostgREST RPC. No IP visibility,
no rate limit, no verification, no cap; creates immediately-`CONFIRMED` unpaid bookings.

### Migration `0065_public_booking_hardening.sql`

```sql
-- Attempt log for velocity limiting. ip_hash, not raw IP (privacy). RLS on,
-- zero policies -> only SECURITY DEFINER functions and the service role touch it.
create table public_booking_attempts (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid references facilities (id) on delete cascade,
  ip_hash text,
  phone_digits text,
  created_at timestamptz not null default now()
);
create index public_booking_attempts_ip_idx    on public_booking_attempts (ip_hash, created_at);
create index public_booking_attempts_phone_idx on public_booking_attempts (phone_digits, created_at);
alter table public_booking_attempts enable row level security;

-- record_and_check_public_booking_attempt: log this attempt, then reject if
-- the IP or phone is over a window limit. Called by the public-guest-booking
-- edge function BEFORE public_create_guest_booking.
--   per IP:    > 8 in 10 min  OR  > 20 in 60 min
--   per phone: > 5 in 60 min
create function record_and_check_public_booking_attempt(
  p_facility_id uuid, p_ip_hash text, p_phone_digits text
) returns void
language plpgsql security definer set search_path = public as $$
declare ip_10 int; ip_60 int; ph_60 int;
begin
  insert into public_booking_attempts (facility_id, ip_hash, phone_digits)
  values (p_facility_id, nullif(p_ip_hash, ''), nullif(p_phone_digits, ''));

  if nullif(p_ip_hash, '') is not null then
    select count(*) into ip_10 from public_booking_attempts
      where ip_hash = p_ip_hash and created_at > now() - interval '10 minutes';
    select count(*) into ip_60 from public_booking_attempts
      where ip_hash = p_ip_hash and created_at > now() - interval '60 minutes';
    if ip_10 > 8 or ip_60 > 20 then
      raise exception 'Too many booking attempts. Please try again later.' using errcode = 'P0001';
    end if;
  end if;

  if nullif(p_phone_digits, '') is not null then
    select count(*) into ph_60 from public_booking_attempts
      where phone_digits = p_phone_digits and created_at > now() - interval '60 minutes';
    if ph_60 > 5 then
      raise exception 'Too many booking attempts for this number. Please try again later.' using errcode = 'P0001';
    end if;
  end if;
end;
$$;
grant execute on function record_and_check_public_booking_attempt(uuid, text, text) to anon, authenticated;
```

### `public_create_guest_booking` — add the unpaid-booking cap

`create or replace` the 0042/0045 function body; add, right after `find_or_create_guest`
returns `guest`:

```sql
if (
  select count(*) from bookings b
  where b.guest_player_id = guest.id
    and b.customer_type = 'GUEST'
    and b.status in ('pending', 'confirmed')
    and b.payment_status = 'PENDING'
    and b.start_time > now()
) >= 4 then
  raise exception 'You have unpaid bookings still pending. Please complete or cancel them before booking again.'
    using errcode = '23514';
end if;
```

Everything else in the function is unchanged — copy it verbatim from its current definition
(0045 replaced `get_or_create_membership_session`; the live `public_create_guest_booking`
body is the one in 0042, unchanged since).

### New edge function `supabase/functions/public-guest-booking/index.ts`

- POST only. No `Authorization` requirement beyond the anon apikey the browser sends.
- Env: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, optional `TURNSTILE_SECRET`, `PUBLIC_BOOKING_IP_SALT`.
- Body: the same params `public_create_guest_booking` takes, plus optional `captchaToken`.
- Steps:
  1. `ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim()`
     `ipHash = sha256(ip + (PUBLIC_BOOKING_IP_SALT ?? ""))` (hex; empty string when no IP).
  2. `phoneDigits = body.phone.replace(/\D/g, "")`.
  3. If `TURNSTILE_SECRET` set: POST `captchaToken` + `ip` to
     `https://challenges.cloudflare.com/turnstile/v0/siteverify`; 403 on failure. If unset,
     skip (wired, dormant).
  4. anon client (`createClient(url, anonKey)` — no auth header; nothing escalates).
  5. `rpc("record_and_check_public_booking_attempt", { p_facility_id, p_ip_hash: ipHash, p_phone_digits: phoneDigits })`
     — `P0001` → 429 with the raised message.
  6. `rpc("public_create_guest_booking", { ...body params })` — map errors the same way
     `createPublicGuestBooking` does today (no-longer-available → 409, friendly sentence →
     400, else generic 500). Return the RPC payload on success (200).
- CORS headers like the other functions.

### Web client — `src/features/public-booking/public-booking.ts`

`createPublicGuestBooking`: replace the `supabase.rpc("public_create_guest_booking", ...)`
call with `supabase.functions.invoke("public-guest-booking", { body: { ...same params } })`.
Keep the existing error-to-exception mapping, adapted to the `{ error }` JSON shape +
`SlotUnavailableError` on 409 / "no longer available". `getPublicCourtAvailability` and
`getPublicBookingFacility` stay direct RPCs.

Update `src/features/public-booking/public-booking.test.ts` if it stubs `.rpc` for the
create path (switch to stubbing `.functions.invoke`).

**Files:** `0065_public_booking_hardening.sql` (new),
`supabase/functions/public-guest-booking/index.ts` (new),
`supabase/functions/public-guest-booking/deno.json` if needed,
`src/features/public-booking/public-booking.ts`, its test.

---

## Part 4 — DB integration test harness

### Setup

- `supabase init` → `supabase/config.toml`. Keep default ports. `[auth] enabled = true`.
  No `seed.sql` (tests build their own fixtures). Commit `config.toml`; add
  `supabase/.branches`, `supabase/.temp` to `.gitignore` if not already.
- `supabase/tests/integration/` — Deno tests.
- `supabase/tests/deno.json` with a task:
  `"test": "deno test --allow-net --allow-env --allow-read"`.
- `supabase/tests/README.md`: `supabase start` → `supabase db reset` → `deno task test`
  (from `supabase/tests/`). Local only; never touches a remote project.

### `supabase/tests/integration/_helpers.ts`

- `npm:pg` (or `jsr:@db/postgres`) — pick `postgres` (deno) driver.
- `PG = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"`.
- `superuserClient()` — one connection, bypasses RLS (for fixtures + service-role-equivalent
  RPC calls).
- `authedClient(userId)` — connection that runs
  `select set_config('request.jwt.claims', json_build_object('sub', $1, 'role','authenticated')::text, false); set role authenticated;`
  so `auth.uid()` and RLS behave like a signed-in facility user.
- Fixture builders (superuser): `makeFacility()`, `makeUser(role)` → inserts `auth.users` +
  `profiles` + `facility_users`, `makeSport()`, `makeCourt()`, `makeOperatingHours()` (open
  24h for simplicity), `makeMembershipBatch()`, `makePaymentOrder(status)`.
- `cleanup()` — truncate the app tables between files (or wrap each test in a transaction +
  rollback where no concurrency is needed; concurrency tests need real commits so those
  truncate).

### Test files (each a `Deno.test` with steps)

1. `booking_concurrency_test.ts` — two `authedClient`s call `create_booking` for the same
   court/time; exactly one returns a row, the other raises `23P01` (exclusion_violation).
2. `guest_capacity_test.ts` — `release_membership_capacity(session, 1)`; two clients call
   `book_guest_slot` → one wins, one raises `23514`. `release_membership_capacity` beyond
   `capacity - members_booked` raises. `restore_membership_capacity` of a guest-booked slot
   raises.
3. `payment_verification_test.ts` — `apply_payment_verification` with wrong amount / wrong
   `razorpay_order_id` / a second `razorpay_payment_id` each raise `23514`. Two calls with a
   genuine `CAPTURED` → exactly one `payments` row. Cancelled booking before settlement →
   `settlement_exceptions` row, `payments` row preserved, order `SETTLEMENT_EXCEPTION`.
4. `refund_test.ts` — `request_refund` beyond `refundable_amount` raises. Two concurrent
   `claim_refund_for_submission` → one row, one NULL. `apply_refund_webhook` replayed
   (`processed` twice, and `created` after `processed`) → no double effect; a `failed` after
   `processed` does not un-process. Pending refund never reads `PROCESSED`.
5. `offline_payment_test.ts` — `record_obligation_payment` twice with the same
   `idempotency_key` → second returns `duplicate: true`, one `payments` row. Two concurrent
   calls for the whole outstanding balance → one succeeds, the other raises `23514`.
6. `facility_isolation_test.ts` — `authedClient(facilityA user)` calling
   `get_finance_summary(facilityB)` and `list_pending_payments(facilityB)` raise `42501`;
   `select ... from payments where facility_id = facilityB` returns 0 rows.
7. `public_booking_test.ts` — `record_and_check_public_booking_attempt` past the IP and
   phone windows raises `P0001`; `public_create_guest_booking` with 4 existing unpaid future
   guest bookings raises `23514`.

### Optional

`.github/workflows/db-tests.yml` — `supabase/setup-cli`, `supabase start`, `supabase db
reset`, `deno task --cwd supabase/tests test`. Include it; it is the payoff of choosing this
harness.

**Files:** `supabase/config.toml` (new), `supabase/tests/**` (new), `.gitignore` (edit),
optionally `.github/workflows/db-tests.yml` (new).

---

## Task order

1. **Part 4 setup** — `supabase init`, `config.toml`, `_helpers.ts`, `.gitignore`. Verify
   `supabase start` + `db reset` + an empty `deno task test` run clean.
2. **Part 1** — migration `0064`, `submit-refund.ts`, then `refund_test.ts` + shared unit
   test. `deno test _shared` green.
3. **Part 2** — `_shared/razorpay.ts`, three edge functions, `payment_verification_test.ts`
   capture assertions where reachable (the capture HTTP call itself is manual/staging).
   `deno test _shared` green.
4. **Part 3** — migration `0065`, `public-guest-booking` function,
   `public-booking.ts` + test, `public_booking_test.ts`.
5. **Remaining Part 4 tests** — files 1, 2, 3, 5, 6 from the list.
6. **Optional CI workflow.**
7. Full `npm test` (web) + `deno test supabase/functions` + `deno task test` (integration,
   needs local stack) + `cd mobile && flutter analyze` — report; user commits & applies.

## Verification per part

- Web: `npm run typecheck` + `npm run lint` + `npm test` — no new failures vs the two
  known-pre-existing (`supabase-payment.service.test.ts` tsc, flaky timer tests).
- Edge shared logic: `deno test supabase/functions/_shared/`.
- Integration: `deno task test` from `supabase/tests/` against a running local stack.
- Flutter: unaffected (`flutter analyze` sanity only).
