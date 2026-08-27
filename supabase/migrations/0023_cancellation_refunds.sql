-- ═══════════════════════════════════════════════════════════════════════════
-- Cancellation, Refund & Payment Recovery — Phase 6.
--
--   Booking / Membership Session Booking / Membership
--         │  cancel_booking / cancel_membership_guest_slot / cancel_membership
--         ▼
--   Cancellation Policy (configurable per facility, sensible default)
--         │
--         ▼
--   request_refund — the SINGLE write path for a refund record, regardless
--   of where it originated (a cancellation, an owner override, or a
--   settlement-exception resolution). Over-refund and concurrent-refund
--   protected by refundable_amount() + a partial unique index; never mutates
--   the original `payments` transaction row.
--         │
--         ▼
--   refunds — REQUESTED → PROCESSING → PENDING → PROCESSED (or → FAILED).
--   Only an Edge Function (create-razorpay-refund / cancel-booking /
--   cancel-membership-slot / cancel-membership) ever calls the real Razorpay
--   Refund API — this migration only ever creates/advances a `refunds` row,
--   never talks to Razorpay itself (Postgres has no such capability here,
--   and the Razorpay secret must stay server-side regardless — spec §17/§52).
--         │
--         ▼
--   apply_refund_webhook — the razorpay-webhook Edge Function's refund.*
--   handler calls this; forward-only + idempotent, exactly like
--   apply_payment_verification (0019). Only a genuine transition into
--   PROCESSED touches payment_orders.status / settlement_exceptions —
--   never on a duplicate or out-of-order delivery (spec §21/§62).
--
-- Reused as-is: bookings' own exclusion constraint (0001) already excludes
-- cancelled rows, so cancelling a booking releases court availability for
-- free — no new availability code needed (spec §36). Guest capacity release
-- is equally free: get_membership_session_capacity (0014) derives
-- guest_available_capacity live from CONFIRMED rows only, so cancelling a
-- membership_session_bookings row already frees the slot (spec §37).
-- payment_orders / payments / settlement_exceptions (0016/0019/0021) are
-- read and updated, never duplicated or deleted.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- cancellation_policies — one configurable row per facility (spec §9:
-- "do not hard-code arbitrary cancellation windows"). Missing row falls
-- back to a documented default inside refund_percent_for_policy, so a
-- facility that never configures one still behaves sensibly rather than
-- refusing to cancel at all.
-- ─────────────────────────────────────────────────────────────────────────
create table cancellation_policies (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade unique,
  full_refund_hours integer not null default 24 check (full_refund_hours >= 0),
  full_refund_percent integer not null default 100 check (full_refund_percent between 0 and 100),
  partial_refund_hours integer not null default 2 check (partial_refund_hours >= 0),
  partial_refund_percent integer not null default 50 check (partial_refund_percent between 0 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cancellation_policies_window_order check (full_refund_hours >= partial_refund_hours)
);

alter table cancellation_policies enable row level security;
create policy "cancellation_policies_select_members" on cancellation_policies for select
  using (is_facility_member(facility_id));
create policy "cancellation_policies_write_managers" on cancellation_policies for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

create trigger cancellation_policies_set_updated_at
  before update on cancellation_policies
  for each row execute function set_updated_at();

create function upsert_cancellation_policy(
  p_facility_id uuid,
  p_full_refund_hours integer,
  p_full_refund_percent integer,
  p_partial_refund_hours integer,
  p_partial_refund_percent integer
) returns cancellation_policies
language plpgsql
as $$
declare
  result cancellation_policies;
begin
  insert into cancellation_policies (facility_id, full_refund_hours, full_refund_percent, partial_refund_hours, partial_refund_percent)
  values (p_facility_id, p_full_refund_hours, p_full_refund_percent, p_partial_refund_hours, p_partial_refund_percent)
  on conflict (facility_id) do update set
    full_refund_hours = excluded.full_refund_hours,
    full_refund_percent = excluded.full_refund_percent,
    partial_refund_hours = excluded.partial_refund_hours,
    partial_refund_percent = excluded.partial_refund_percent,
    updated_at = now()
  returning * into result;
  return result;
end;
$$;

grant execute on function upsert_cancellation_policy(uuid, integer, integer, integer, integer) to authenticated;

create function get_effective_cancellation_policy(p_facility_id uuid) returns cancellation_policies
language sql
stable
as $$
  select coalesce(
    (select cp from cancellation_policies cp where cp.facility_id = p_facility_id),
    row(gen_random_uuid(), p_facility_id, 24, 100, 2, 50, now(), now())::cancellation_policies
  );
$$;

grant execute on function get_effective_cancellation_policy(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- refund_percent_for_policy: pure decision function — how much of the
-- refundable amount should this cancellation return, given how many hours
-- remain before the booking/session was due to start? Same 24h/100%,
-- 2h/50%, else 0% shape as the spec's own worked example, but always
-- sourced from the facility's configured (or default) policy, never
-- hard-coded into the caller.
-- ─────────────────────────────────────────────────────────────────────────
create function refund_percent_for_policy(p_facility_id uuid, p_hours_until_start numeric) returns integer
language plpgsql
stable
as $$
declare
  policy cancellation_policies;
begin
  policy := get_effective_cancellation_policy(p_facility_id);
  if p_hours_until_start >= policy.full_refund_hours then
    return policy.full_refund_percent;
  elsif p_hours_until_start >= policy.partial_refund_hours then
    return policy.partial_refund_percent;
  else
    return 0;
  end if;
end;
$$;

grant execute on function refund_percent_for_policy(uuid, numeric) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- refunds — one row per refund attempt against a payment_order. The
-- original `payments` transaction row is never touched (spec §26/§73);
-- this is the append-only ledger of money given back.
-- ─────────────────────────────────────────────────────────────────────────
create table refunds (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  payment_order_id uuid not null references payment_orders (id) on delete cascade,
  transaction_id uuid references payments (id) on delete set null,
  source_type payment_source_type not null,
  -- Untyped, same tradeoff as settlement_exceptions.source_id (0021) — may
  -- point at bookings, membership_session_bookings, or memberships
  -- depending on source_type; always read joined through payment_order_id.
  source_id uuid,
  razorpay_payment_id text not null,
  razorpay_refund_id text,
  amount_minor integer not null check (amount_minor > 0),
  currency text not null default 'INR',
  reason refund_reason not null,
  status refund_status not null default 'REQUESTED',
  is_override boolean not null default false,
  override_reason text,
  -- The cancellation-policy percent actually applied, for the audit trail
  -- (spec §10/§47) — null for a manual/settlement-exception refund that
  -- was never policy-derived.
  policy_percent_applied integer,
  failure_reason text,
  initiated_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  processed_at timestamptz
);

create index refunds_facility_id_idx on refunds (facility_id);
create index refunds_payment_order_id_idx on refunds (payment_order_id);
create index refunds_status_idx on refunds (status);
create unique index refunds_razorpay_refund_id_idx on refunds (razorpay_refund_id) where razorpay_refund_id is not null;
-- §41 "Concurrent Refunds" / §60 "Duplicate Refund Test": at most one
-- in-flight refund per payment order at a time — the hard backstop behind
-- request_refund's own application-level check below.
create unique index refunds_one_active_per_order_idx on refunds (payment_order_id)
  where status in ('REQUESTED', 'PROCESSING', 'PENDING');

alter table refunds enable row level security;
create policy "refunds_select_staff" on refunds for select
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));
create policy "refunds_write_staff" on refunds for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

create trigger refunds_set_updated_at
  before update on refunds
  for each row execute function set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- refundable_amount: Captured Amount − Processed Refunds − Pending/
-- In-flight Refunds (spec §40). The single source of truth every refund
-- request is validated against — never trusts a client-claimed amount.
-- ─────────────────────────────────────────────────────────────────────────
create function refundable_amount(p_payment_order_id uuid) returns integer
language sql
stable
as $$
  select po.amount_minor
    - coalesce((select sum(r.amount_minor) from refunds r where r.payment_order_id = po.id and r.status = 'PROCESSED'), 0)
    - coalesce((select sum(r.amount_minor) from refunds r where r.payment_order_id = po.id and r.status in ('REQUESTED', 'PROCESSING', 'PENDING')), 0)
  from payment_orders po
  where po.id = p_payment_order_id;
$$;

grant execute on function refundable_amount(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- request_refund: the single write path for a refund RECORD (spec §51 "no
-- manual database refunds" — every caller, including cancel_booking below,
-- funnels through this). Does NOT call Razorpay — only an Edge Function
-- does that, after this returns REQUESTED (spec §17/§52). Locks the
-- payment_orders row so a concurrent over-refund attempt is impossible
-- even before the unique index would catch it.
-- ─────────────────────────────────────────────────────────────────────────
create function request_refund(
  p_payment_order_id uuid,
  p_amount_minor integer,
  p_reason refund_reason,
  p_source_type payment_source_type,
  p_source_id uuid,
  p_is_override boolean default false,
  p_override_reason text default null,
  p_policy_percent_applied integer default null
) returns refunds
language plpgsql
as $$
declare
  po payment_orders;
  txn payments;
  max_refundable integer;
  result refunds;
begin
  select * into po from payment_orders where id = p_payment_order_id for update;
  if po.id is null then
    raise exception 'Payment order not found.' using errcode = 'P0002';
  end if;
  if po.status not in ('COMPLETED', 'SETTLEMENT_EXCEPTION', 'PARTIALLY_REFUNDED') then
    raise exception 'This payment is not eligible for a refund.' using errcode = '23514';
  end if;
  if po.razorpay_payment_id is null then
    raise exception 'This payment has no captured Razorpay payment to refund.' using errcode = '23514';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Refund amount must be positive.' using errcode = '23514';
  end if;

  max_refundable := refundable_amount(po.id);
  if p_amount_minor > max_refundable then
    raise exception 'The maximum refundable amount is %.', max_refundable using errcode = '23514';
  end if;

  select id into txn from payments where payment_order_id = po.id order by created_at desc limit 1;

  begin
    insert into refunds (
      facility_id, payment_order_id, transaction_id, source_type, source_id,
      razorpay_payment_id, amount_minor, currency, reason, status,
      initiated_by, is_override, override_reason, policy_percent_applied
    ) values (
      po.facility_id, po.id, txn.id, p_source_type, p_source_id,
      po.razorpay_payment_id, p_amount_minor, po.currency, p_reason, 'REQUESTED',
      auth.uid(), p_is_override, p_override_reason, p_policy_percent_applied
    ) returning * into result;
  exception when unique_violation then
    -- §41/§60: a second concurrent/duplicate request never creates a
    -- second refund — it safely observes the one already in flight.
    select * into result from refunds
      where payment_order_id = po.id and status in ('REQUESTED', 'PROCESSING', 'PENDING')
      order by created_at desc limit 1;
    return result;
  end;

  return result;
end;
$$;

grant execute on function request_refund(uuid, integer, refund_reason, payment_source_type, uuid, boolean, text, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- cancel_booking: the single write path for cancelling a `bookings` row
-- (member booking, or an ad-hoc guest booking) — replaces the previous
-- client-side plain status update. Court availability release is free
-- (see header comment); refund eligibility is policy-derived unless the
-- caller (owner override) supplies an explicit percent.
-- ─────────────────────────────────────────────────────────────────────────
create function cancel_booking(
  p_booking_id uuid,
  p_reason text default null,
  p_refund_override_percent integer default null,
  p_override_reason text default null
) returns bookings
language plpgsql
as $$
declare
  b bookings;
  po payment_orders;
  pct integer;
  refund_amount integer;
  hours_until numeric;
begin
  select * into b from bookings where id = p_booking_id for update;
  if b.id is null then
    raise exception 'Booking not found.' using errcode = 'P0002';
  end if;
  if b.status not in ('pending', 'confirmed') then
    raise exception 'This booking cannot be cancelled.' using errcode = '23514';
  end if;

  update bookings set status = 'cancelled', cancellation_reason = p_reason where id = b.id returning * into b;

  select * into po from payment_orders
    where booking_id = b.id and status in ('COMPLETED', 'SETTLEMENT_EXCEPTION', 'PARTIALLY_REFUNDED')
    order by created_at desc limit 1;

  if po.id is not null and po.razorpay_payment_id is not null then
    hours_until := extract(epoch from (b.start_time - now())) / 3600.0;
    if p_refund_override_percent is not null then
      pct := greatest(0, least(100, p_refund_override_percent));
    else
      pct := refund_percent_for_policy(b.facility_id, hours_until);
    end if;

    if pct > 0 then
      refund_amount := round(refundable_amount(po.id) * pct / 100.0)::integer;
      if refund_amount > 0 then
        perform request_refund(
          po.id, refund_amount,
          case when p_refund_override_percent is not null then 'OWNER_OVERRIDE' else 'CUSTOMER_CANCELLATION' end::refund_reason,
          po.source_type, b.id,
          p_refund_override_percent is not null, p_override_reason, pct
        );
      end if;
    end if;
  end if;

  return b;
end;
$$;

grant execute on function cancel_booking(uuid, text, integer, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- cancel_membership_guest_slot: cancels a released-capacity guest booking
-- (membership_session_bookings row). Reuses cancel_membership_slot_booking's
-- exact update (0014) inline rather than calling it, so this stays a
-- single transaction alongside the refund request. Guest capacity release
-- is free — see header comment.
-- ─────────────────────────────────────────────────────────────────────────
create function cancel_membership_guest_slot(
  p_booking_id uuid,
  p_reason text default null,
  p_refund_override_percent integer default null,
  p_override_reason text default null
) returns membership_session_bookings
language plpgsql
as $$
declare
  msb membership_session_bookings;
  session membership_sessions;
  fac facilities;
  po payment_orders;
  pct integer;
  refund_amount integer;
  hours_until numeric;
  session_start timestamptz;
begin
  update membership_session_bookings set status = 'CANCELLED'
    where id = p_booking_id and status = 'CONFIRMED'
    returning * into msb;
  if msb.id is null then
    raise exception 'Booking not found or already cancelled' using errcode = 'P0002';
  end if;

  select * into session from membership_sessions where id = msb.session_id;
  select * into fac from facilities where id = msb.facility_id;
  session_start := (session.session_date::text || ' ' || session.start_time::text)::timestamp at time zone coalesce(fac.timezone, 'Asia/Kolkata');

  select * into po from payment_orders
    where membership_session_booking_id = msb.id and status in ('COMPLETED', 'SETTLEMENT_EXCEPTION', 'PARTIALLY_REFUNDED')
    order by created_at desc limit 1;

  if po.id is not null and po.razorpay_payment_id is not null then
    hours_until := extract(epoch from (session_start - now())) / 3600.0;
    if p_refund_override_percent is not null then
      pct := greatest(0, least(100, p_refund_override_percent));
    else
      pct := refund_percent_for_policy(msb.facility_id, hours_until);
    end if;

    if pct > 0 then
      refund_amount := round(refundable_amount(po.id) * pct / 100.0)::integer;
      if refund_amount > 0 then
        perform request_refund(
          po.id, refund_amount,
          case when p_refund_override_percent is not null then 'OWNER_OVERRIDE' else 'CUSTOMER_CANCELLATION' end::refund_reason,
          po.source_type, msb.id,
          p_refund_override_percent is not null, p_override_reason, pct
        );
      end if;
    end if;
  end if;

  return msb;
end;
$$;

grant execute on function cancel_membership_guest_slot(uuid, text, integer, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- cancel_membership: membership cancellation is deliberately NOT
-- time-policy-driven (spec §14/§15 — "do not automatically refund an
-- active membership unless the configured business policy allows it").
-- The caller (owner/manager) explicitly decides the refund amount, if any;
-- omitting it cancels the membership with no refund at all.
-- ─────────────────────────────────────────────────────────────────────────
-- Supersedes the bare cancel_membership(uuid) from 0012_memberships.sql —
-- dropped explicitly (a changed argument list would otherwise sit
-- alongside it as an ambiguous overload, same reasoning as 0014's
-- create_booking rebuild) and replaced with a strict superset: calling
-- with only p_membership_id defaults reason/refund to null, matching the
-- old function's behavior exactly, plus the new (active/pending)-only
-- guard so an already-terminal membership can't be "re-cancelled".
drop function if exists cancel_membership(uuid);

create function cancel_membership(
  p_membership_id uuid,
  p_reason text default null,
  p_refund_amount_minor integer default null,
  p_override_reason text default null
) returns memberships
language plpgsql
as $$
declare
  m memberships;
  po payment_orders;
  max_refundable integer;
begin
  update memberships set status = 'cancelled'
    where id = p_membership_id and status in ('active', 'pending')
    returning * into m;
  if m.id is null then
    raise exception 'Membership not found or not cancellable.' using errcode = 'P0002';
  end if;

  if p_refund_amount_minor is not null and p_refund_amount_minor > 0 then
    select po2.* into po from payment_orders po2
      where po2.member_id = m.member_id and po2.plan_id = m.plan_id and po2.source_type = 'MEMBERSHIP'
        and po2.status in ('COMPLETED', 'SETTLEMENT_EXCEPTION', 'PARTIALLY_REFUNDED')
      order by po2.created_at desc limit 1;
    if po.id is null or po.razorpay_payment_id is null then
      raise exception 'No captured Razorpay payment found for this membership.' using errcode = '23514';
    end if;
    max_refundable := refundable_amount(po.id);
    if p_refund_amount_minor > max_refundable then
      raise exception 'The maximum refundable amount is %.', max_refundable using errcode = '23514';
    end if;
    perform request_refund(po.id, p_refund_amount_minor, 'OWNER_OVERRIDE'::refund_reason, po.source_type, m.id, true, p_override_reason, null);
  end if;

  return m;
end;
$$;

grant execute on function cancel_membership(uuid, text, integer, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- refund_settlement_exception / initiate_manual_refund: the two other
-- entry points into request_refund — an owner resolving a §16 "payment
-- received, booking not confirmed" exception with a full refund, or an
-- owner manually adjusting/partially refunding any settled payment
-- (spec §30-32) without a cancellation having happened at all.
-- ─────────────────────────────────────────────────────────────────────────
create function refund_settlement_exception(p_settlement_exception_id uuid) returns refunds
language plpgsql
as $$
declare
  ex settlement_exceptions;
  po payment_orders;
  amt integer;
begin
  select * into ex from settlement_exceptions where id = p_settlement_exception_id and status = 'OPEN';
  if ex.id is null then
    raise exception 'Settlement exception not found or already resolved.' using errcode = 'P0002';
  end if;
  select * into po from payment_orders where id = ex.payment_order_id;
  amt := refundable_amount(po.id);
  if amt <= 0 then
    raise exception 'Nothing left to refund for this payment.' using errcode = '23514';
  end if;
  return request_refund(po.id, amt, 'SETTLEMENT_EXCEPTION'::refund_reason, ex.source_type, ex.source_id, false, null, null);
end;
$$;

grant execute on function refund_settlement_exception(uuid) to authenticated;

create function initiate_manual_refund(
  p_payment_order_id uuid,
  p_amount_minor integer,
  p_reason refund_reason,
  p_override_reason text default null
) returns refunds
language plpgsql
as $$
declare
  po payment_orders;
  src_id uuid;
begin
  select * into po from payment_orders where id = p_payment_order_id;
  if po.id is null then
    raise exception 'Payment order not found.' using errcode = 'P0002';
  end if;
  src_id := coalesce(po.booking_id, po.membership_session_booking_id, po.member_id);
  return request_refund(po.id, p_amount_minor, p_reason, po.source_type, src_id, p_override_reason is not null, p_override_reason, null);
end;
$$;

grant execute on function initiate_manual_refund(uuid, integer, refund_reason, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- mark_refund_processing / mark_refund_failed: called by the Edge
-- Functions that actually talk to Razorpay (create-razorpay-refund,
-- cancel-booking, cancel-membership-slot, cancel-membership) right after
-- the Razorpay Refund API call returns. Idempotent no-ops if the refund
-- has already moved past REQUESTED/PROCESSING by the time this runs (e.g.
-- the webhook beat the Edge Function's own follow-up call to it).
-- ─────────────────────────────────────────────────────────────────────────
create function mark_refund_processing(p_refund_id uuid, p_razorpay_refund_id text) returns refunds
language plpgsql
as $$
declare
  result refunds;
begin
  update refunds set status = 'PROCESSING', razorpay_refund_id = p_razorpay_refund_id
    where id = p_refund_id and status = 'REQUESTED'
    returning * into result;
  if result.id is null then
    select * into result from refunds where id = p_refund_id;
  end if;
  return result;
end;
$$;

grant execute on function mark_refund_processing(uuid, text) to authenticated;

create function mark_refund_failed(p_refund_id uuid, p_error text default null) returns refunds
language plpgsql
as $$
declare
  result refunds;
begin
  update refunds set status = 'FAILED', failure_reason = p_error
    where id = p_refund_id and status in ('REQUESTED', 'PROCESSING')
    returning * into result;
  if result.id is null then
    select * into result from refunds where id = p_refund_id;
  end if;
  return result;
end;
$$;

grant execute on function mark_refund_failed(uuid, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- apply_refund_webhook: the razorpay-webhook Edge Function's refund.*
-- handler calls this — forward-only + idempotent, exactly like
-- apply_payment_verification (0019). Only a genuine transition into
-- PROCESSED touches payment_orders.status / settlement_exceptions.
-- ─────────────────────────────────────────────────────────────────────────
create function apply_refund_webhook(
  p_razorpay_refund_id text,
  p_razorpay_payment_id text,
  p_status text, -- 'created' | 'processed' | 'failed' — Razorpay's refund.* event tail
  p_amount_minor integer
) returns refunds
language plpgsql
as $$
declare
  r refunds;
  rank_map jsonb := '{"REQUESTED": 0, "PROCESSING": 1, "PENDING": 2, "PROCESSED": 3}'::jsonb;
  target text;
  cur_rank int;
  tgt_rank int;
  po payment_orders;
  total_processed integer;
begin
  select * into r from refunds where razorpay_refund_id = p_razorpay_refund_id for update;
  if r.id is null then
    -- refund.created may arrive before mark_refund_processing's own write
    -- lands (a genuine race between the Edge Function's Razorpay call
    -- returning and the webhook firing) — fall back to the still-open
    -- refund for this payment.
    select * into r from refunds
      where razorpay_payment_id = p_razorpay_payment_id and status in ('REQUESTED', 'PROCESSING', 'PENDING')
      order by created_at desc limit 1 for update;
    if r.id is null then
      raise exception 'No matching refund found for razorpay_refund_id %', p_razorpay_refund_id using errcode = 'P0002';
    end if;
    update refunds set razorpay_refund_id = p_razorpay_refund_id where id = r.id returning * into r;
  end if;

  if p_status = 'failed' then
    if r.status in ('REQUESTED', 'PROCESSING', 'PENDING') then
      update refunds set status = 'FAILED' where id = r.id returning * into r;
    end if;
    return r;
  end if;

  target := case p_status when 'processed' then 'PROCESSED' when 'created' then 'PROCESSING' else 'PENDING' end;
  cur_rank := (rank_map ->> r.status::text)::int;
  tgt_rank := (rank_map ->> target)::int;

  if cur_rank is null or tgt_rank <= cur_rank then
    -- §21/§62: duplicate or out-of-order delivery — no-op.
    return r;
  end if;

  update refunds set status = target::refund_status, processed_at = case when target = 'PROCESSED' then now() else processed_at end
    where id = r.id returning * into r;

  if target = 'PROCESSED' then
    select * into po from payment_orders where id = r.payment_order_id for update;
    total_processed := coalesce((select sum(amount_minor) from refunds where payment_order_id = po.id and status = 'PROCESSED'), 0);
    if total_processed >= po.amount_minor then
      update payment_orders set status = 'REFUNDED' where id = po.id;
    else
      update payment_orders set status = 'PARTIALLY_REFUNDED' where id = po.id;
    end if;

    -- §16: a settlement-exception refund, once processed, resolves the
    -- exception it was raised for.
    update settlement_exceptions set status = 'RESOLVED', resolved_at = now()
      where payment_order_id = po.id and status = 'OPEN';
  end if;

  return r;
end;
$$;

grant execute on function apply_refund_webhook(text, text, text, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- Read helpers — Finance/Owner refund visibility (spec §28/§29/§30).
-- ─────────────────────────────────────────────────────────────────────────
create function get_refund(p_refund_id uuid) returns refunds
language sql
stable
as $$
  select * from refunds where id = p_refund_id;
$$;

grant execute on function get_refund(uuid) to authenticated;

create function list_refunds(p_facility_id uuid) returns setof refunds
language sql
stable
as $$
  select * from refunds where facility_id = p_facility_id order by created_at desc;
$$;

grant execute on function list_refunds(uuid) to authenticated;

create function list_settlement_exceptions(p_facility_id uuid, p_status text default 'OPEN') returns setof settlement_exceptions
language sql
stable
as $$
  select * from settlement_exceptions
  where facility_id = p_facility_id and (p_status is null or status = p_status)
  order by created_at desc;
$$;

grant execute on function list_settlement_exceptions(uuid, text) to authenticated;