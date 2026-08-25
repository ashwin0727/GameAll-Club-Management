-- ═══════════════════════════════════════════════════════════════════════════
-- Razorpay Payment Verification, Webhooks & Reconciliation — Phase 4.
--
-- The client is never the final authority for payment success (see the
-- Phase 4 spec's "Critical Principle"). This migration adds the one piece
-- of server-side state that both the verify-razorpay-payment Edge Function
-- (client-triggered, runs under the caller's own staff session) and the
-- razorpay-webhook Edge Function (Razorpay-triggered, runs under the
-- service role — there is no user session to scope it to) share:
--
--   apply_payment_verification — the single, atomic, row-locked gate that
--   decides whether a reported Razorpay payment result is allowed to move
--   payment_orders.status forward, and if it reaches CAPTURED, upserts the
--   existing `payments` Finance table (never a second/duplicate table).
--
-- This phase deliberately stops at CAPTURED + a Finance transaction row —
-- it never touches bookings.status, bookings.payment_status, or the
-- memberships table. Booking confirmation / membership activation are the
-- next phase's job, reading payment_orders.status = 'CAPTURED' as their
-- input.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- razorpay_webhook_events — dedupe + audit log for inbound Razorpay
-- webhooks. Keyed on Razorpay's own x-razorpay-event-id so a redelivered
-- webhook (Razorpay retries on anything but a 2xx) is detected before any
-- business logic runs a second time. Service-role only: this is an
-- internal ops/audit log, not something any facility user needs to see, so
-- RLS is enabled with zero policies — a normal authenticated user gets zero
-- rows, only the webhook function's service-role client (which bypasses
-- RLS entirely, as Postgres/Supabase always allow for the service role)
-- can read or write it.
-- ─────────────────────────────────────────────────────────────────────────
create table razorpay_webhook_events (
  id uuid primary key default gen_random_uuid(),
  event_id text not null unique,
  event_type text not null,
  payload jsonb not null,
  processed boolean not null default false,
  processed_at timestamptz,
  -- Set when processing raised an error, so a failed-but-signature-valid
  -- delivery is visible for debugging without ever exposing it to a client
  -- (spec §"Webhook Failure Handling": don't silently discard valid events).
  error text,
  created_at timestamptz not null default now()
);

create index razorpay_webhook_events_event_type_idx on razorpay_webhook_events (event_type);
create index razorpay_webhook_events_processed_idx on razorpay_webhook_events (processed) where not processed;

alter table razorpay_webhook_events enable row level security;
-- No policies: authenticated/anon get zero rows; service role bypasses RLS.

-- ─────────────────────────────────────────────────────────────────────────
-- apply_payment_verification — see header comment. Runs as whichever role
-- calls it (staff session for verify-razorpay-payment, service role for
-- the webhook) — it does not escalate privilege itself. Concurrency
-- safety comes from `select ... for update`: two simultaneous calls for
-- the same payment order (e.g. a webhook and a client verification racing
-- each other) serialize on that row lock, so exactly one of them performs
-- the forward transition and the other sees the already-advanced state.
--
-- p_razorpay_signature is optional — the webhook path has already verified
-- the *webhook's* signature separately and has no per-payment signature to
-- pass; verify-razorpay-payment does. Whichever call sets it first wins
-- (coalesce), it is never overwritten with null.
-- ─────────────────────────────────────────────────────────────────────────
create function apply_payment_verification(
  p_payment_order_id uuid,
  p_razorpay_order_id text,
  p_razorpay_payment_id text,
  p_razorpay_status text,
  p_amount_minor integer,
  p_currency text,
  p_razorpay_signature text default null
) returns payment_orders
language plpgsql
as $$
declare
  row_ payment_orders;
  result payment_orders;
  target_status payment_order_status;
  rank_map jsonb := '{
    "CREATED": 0, "ORDER_CREATED": 1, "PAYMENT_ATTEMPTED": 2,
    "PAYMENT_VERIFICATION_PENDING": 3, "PAYMENT_VERIFIED": 4,
    "AUTHORIZED": 5, "CAPTURED": 6, "COMPLETED": 7
  }'::jsonb;
  current_rank int;
  target_rank int;
  v_guest_player_id uuid;
begin
  select * into row_ from payment_orders where id = p_payment_order_id for update;
  if row_.id is null then
    raise exception 'Payment order not found.' using errcode = 'P0002';
  end if;

  -- §"Payment Order Matching" / §"Wrong Order Test": never verify a
  -- Razorpay result against an unrelated GameAll order.
  if row_.razorpay_order_id is distinct from p_razorpay_order_id then
    raise exception 'Razorpay order does not match this payment order.' using errcode = '23514';
  end if;

  -- §"Razorpay Payment Validation": once a payment id is attached, a
  -- second, different payment id can never be substituted in.
  if row_.razorpay_payment_id is not null and row_.razorpay_payment_id is distinct from p_razorpay_payment_id then
    raise exception 'A different payment has already been recorded for this order.' using errcode = '23514';
  end if;

  -- §"Amount Tampering Protection" / §"Currency Validation": compare
  -- against GameAll's own stored (server-computed, never client-supplied)
  -- amount/currency — the caller passes Razorpay's authoritative amount,
  -- fetched directly from Razorpay's API or webhook payload, never from
  -- the browser/app.
  if p_amount_minor is distinct from row_.amount_minor or upper(p_currency) is distinct from upper(row_.currency) then
    raise exception 'Payment amount or currency does not match the expected amount.' using errcode = '23514';
  end if;

  if p_razorpay_status not in ('AUTHORIZED', 'CAPTURED', 'FAILED', 'PAYMENT_VERIFIED') then
    raise exception 'Unknown Razorpay-derived status: %', p_razorpay_status using errcode = '22023';
  end if;
  target_status := p_razorpay_status::payment_order_status;

  -- §"Event Ordering" / §"Payment State Machine": status only ever moves
  -- forward. FAILED is a special terminal branch — reachable only before
  -- the payment has actually been authorized/captured (a `payment.failed`
  -- webhook for an order GameAll already knows was captured is a
  -- contradiction Razorpay would not normally send; defensively ignored
  -- rather than downgrading).
  if target_status = 'FAILED' then
    if row_.status in ('CREATED', 'ORDER_CREATED', 'PAYMENT_ATTEMPTED', 'PAYMENT_VERIFICATION_PENDING', 'PAYMENT_VERIFIED') then
      update payment_orders
        set status = 'FAILED',
            razorpay_payment_id = coalesce(p_razorpay_payment_id, razorpay_payment_id),
            razorpay_signature = coalesce(p_razorpay_signature, razorpay_signature)
        where id = p_payment_order_id
        returning * into result;
    else
      result := row_;
    end if;
    return result;
  end if;

  current_rank := (rank_map ->> row_.status::text)::int;
  target_rank := (rank_map ->> target_status::text)::int;

  if current_rank is null or target_rank <= current_rank then
    -- Already at or past this state (idempotent retry — §"Client Retry",
    -- §"Duplicate Webhook Test") or in a terminal state this function
    -- doesn't advance from (FAILED/CANCELLED/REFUND*). No-op.
    return row_;
  end if;

  update payment_orders
    set status = target_status,
        razorpay_payment_id = coalesce(p_razorpay_payment_id, razorpay_payment_id),
        razorpay_signature = coalesce(p_razorpay_signature, razorpay_signature)
    where id = p_payment_order_id
    returning * into result;

  -- §"Transaction Creation": only a genuine, just-happened transition into
  -- CAPTURED creates the Finance transaction row — never on every call,
  -- and never for AUTHORIZED-only (money held, not yet captured).
  if target_status = 'CAPTURED' then
    if result.membership_session_booking_id is not null then
      select guest_player_id into v_guest_player_id from membership_session_bookings where id = result.membership_session_booking_id;
    elsif result.source_type = 'GUEST_BOOKING' and result.booking_id is not null then
      select guest_player_id into v_guest_player_id from bookings where id = result.booking_id;
    else
      v_guest_player_id := null;
    end if;

    insert into payments (
      facility_id, member_id, payment_order_id, booking_id, guest_player_id,
      razorpay_order_id, razorpay_payment_id, amount_inr, status, payment_method, paid_at
    ) values (
      result.facility_id, result.member_id, result.id, result.booking_id, v_guest_player_id,
      result.razorpay_order_id, result.razorpay_payment_id, round(result.amount_minor / 100.0), 'paid', 'RAZORPAY', now()
    )
    -- §"Transaction Idempotency": the existing unique index on
    -- payments.razorpay_payment_id (0016_payment_orders.sql) is the hard
    -- backstop — a duplicate payment.captured webhook or a verify call
    -- racing the webhook can reach this insert twice; the second is a
    -- no-op, never a second transaction row.
    on conflict (razorpay_payment_id) where razorpay_payment_id is not null do nothing;
  end if;

  return result;
end;
$$;

-- `authenticated` needs EXECUTE because facility staff DO call this
-- directly (via verify-razorpay-payment / reconcile-razorpay-payment
-- running under their own session) — but this grant does not broaden what
-- they can reach: the function is SECURITY INVOKER (the default — no
-- `security definer` above), so its internal `for update` select and the
-- update/insert on payment_orders/payments still run under the calling
-- role's own privileges and are still subject to those tables' existing
-- RLS policies. The service role (used only by the webhook) always
-- bypasses RLS regardless of this grant, and needs no grant of its own.
grant execute on function apply_payment_verification(uuid, text, text, text, integer, text, text) to authenticated;