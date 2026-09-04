# DB integration tests

Real-Postgres tests for the transaction core: concurrency, idempotency, and
facility isolation — the scenarios from the 2026-09-04 audit (§27) that a
pure-logic unit test cannot prove.

These run **only against a local Supabase stack**. They never touch the
linked project.

## Run

```sh
# from the repo root — needs Docker running
supabase start
supabase db reset          # applies every migration in supabase/migrations/

cd supabase/tests
deno task test
```

`supabase db reset` re-applies the full migration set to the local database,
so the tests always run against current schema. Re-run it after adding a
migration.

## Layout

- `integration/_helpers.ts` — connection helpers (`superuser()` bypasses RLS;
  `authed(userId)` runs as `authenticated` with `auth.uid()` set) and fixture
  builders. Each test file cleans the tables it uses in a `beforeAll`.
- `integration/*_test.ts` — one file per scenario group.

## What is covered

| File | Scenario |
|------|----------|
| `booking_concurrency_test.ts` | two users, one last court slot → exactly one wins |
| `guest_capacity_test.ts` | released-capacity race; release ≤ unused; restore blocked once guest-booked |
| `payment_verification_test.ts` | amount/order/payment-id tamper rejected; duplicate CAPTURED → one payment row; settlement-exception preserves the payment |
| `refund_test.ts` | over-refund blocked; concurrent submission claim → one winner; webhook replay/out-of-order no-op; pending never PROCESSED |
| `offline_payment_test.ts` | idempotency-key dedupe; concurrent last-balance → one wins |
| `facility_isolation_test.ts` | facility A cannot read facility B finance / payments |
| `public_booking_test.ts` | rate-limit window + unpaid-booking cap both reject |
