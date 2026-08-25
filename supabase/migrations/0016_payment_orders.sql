-- ═══════════════════════════════════════════════════════════════════════════
-- Razorpay Payment Foundation — Phase 1 (database).
--
--   payment_orders — GameAll's own pre-capture record: "someone wants to pay
--   for X, here's the authoritative amount, here's the Razorpay order once
--   it exists." Created and left PAYMENT_PENDING-equivalent (status
--   'CREATED'/'ORDER_CREATED') until a later phase's webhook/verification
--   confirms an actual payment. Never implies success.
--
--   payments (existing, 0001_init.sql) — the eventual completed Finance
--   transaction. Reused, not duplicated: extended here with the columns a
--   future phase needs to link a captured payment back to its order and to
--   whichever source (booking or guest slot) it paid for, and to support
--   guest-sourced transactions that have no member. Nothing writes to it in
--   this phase — Phase 1/2 only ever create/update payment_orders.
--
-- Why a new table instead of just widening `payments`: `payments` is a
-- record of money that has actually moved (created via the existing
-- create_membership flow only after a plan is chosen). A payment ORDER is a
-- pre-payment intent that may expire, fail, or be abandoned — conflating the
-- two would mean either fabricating fake `payments` rows for abandoned
-- checkouts (bad for Finance reporting) or losing the pending/expiry
-- lifecycle entirely.
--
-- Price authority: for MEMBER_BOOKING/GUEST_BOOKING, the amount is read
-- directly off the existing bookings/membership_session_bookings row's
-- already-server-computed amount_minor (captured at booking-creation time
-- via the existing resolve_booking_price pricing engine) — never
-- recalculated here, and the client's amount is never read at all. For
-- MEMBERSHIP, the amount comes straight from membership_plans.price_inr.
-- ═══════════════════════════════════════════════════════════════════════════

create type payment_source_type as enum ('MEMBERSHIP', 'MEMBER_BOOKING', 'GUEST_BOOKING');

create type payment_order_status as enum (
  'CREATED',
  'ORDER_CREATED',
  'PAYMENT_ATTEMPTED',
  'AUTHORIZED',
  'CAPTURED',
  'COMPLETED',
  'FAILED',
  'CANCELLED',
  'REFUND_REQUESTED',
  'REFUNDED'
);

create table payment_orders (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  source_type payment_source_type not null,
  -- Exactly the FKs relevant to the source_type are set — see the check
  -- constraint below. Explicit typed columns (not a polymorphic id) so
  -- referential integrity is enforced by Postgres itself, matching this
  -- project's existing convention (payments.membership_id, etc).
  booking_id uuid references bookings (id) on delete cascade,
  membership_session_booking_id uuid references membership_session_bookings (id) on delete cascade,
  member_id uuid references members (id) on delete cascade,
  plan_id uuid references membership_plans (id) on delete restrict,
  amount_minor integer not null check (amount_minor > 0),
  currency text not null default 'INR',
  status payment_order_status not null default 'CREATED',
  razorpay_order_id text,
  razorpay_payment_id text,
  razorpay_signature text,
  receipt text not null,
  -- A pending order that nobody paid must not hold court capacity forever —
  -- Phase 3+ (checkout/verification) reads this to decide whether an order
  -- can still be paid or must be re-created.
  expires_at timestamptz not null,
  created_by uuid not null references profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_orders_source_check check (
    (source_type = 'MEMBERSHIP' and member_id is not null and plan_id is not null and booking_id is null and membership_session_booking_id is null)
    or (source_type = 'MEMBER_BOOKING' and booking_id is not null and membership_session_booking_id is null and plan_id is null)
    or (source_type = 'GUEST_BOOKING' and plan_id is null and ((booking_id is not null) <> (membership_session_booking_id is not null)))
  )
);

create index payment_orders_facility_id_idx on payment_orders (facility_id);
create index payment_orders_booking_id_idx on payment_orders (booking_id) where booking_id is not null;
create index payment_orders_membership_session_booking_id_idx on payment_orders (membership_session_booking_id) where membership_session_booking_id is not null;
create index payment_orders_status_idx on payment_orders (status);
create index payment_orders_created_at_idx on payment_orders (created_at);
create index payment_orders_expires_at_idx on payment_orders (expires_at);
-- Idempotency: a Razorpay order/payment id, once attached, can never be
-- attached to a second GameAll payment order — the hard backstop behind the
-- application-level "reuse an existing valid pending order" logic in
-- create_payment_order below.
create unique index payment_orders_razorpay_order_id_idx on payment_orders (razorpay_order_id) where razorpay_order_id is not null;
create unique index payment_orders_razorpay_payment_id_idx on payment_orders (razorpay_payment_id) where razorpay_payment_id is not null;

alter table payment_orders enable row level security;

-- Payment/finance data — facility staff only. Members have no Supabase Auth
-- session in this app (see the Members architecture fix), so there is no
-- member-self-service angle to add here, unlike bookings/memberships.
create policy "payment_orders_select_staff" on payment_orders for select
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));
create policy "payment_orders_write_staff" on payment_orders for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

create trigger payment_orders_set_updated_at
  before update on payment_orders
  for each row execute function set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- payments: additive extension only — nothing in this phase writes to this
-- table. member_id relaxed to nullable so a future GUEST_BOOKING-sourced
-- transaction (no member at all) can be represented without a fake row.
-- ─────────────────────────────────────────────────────────────────────────
alter table payments
  alter column member_id drop not null,
  add column payment_order_id uuid references payment_orders (id) on delete set null,
  add column booking_id uuid references bookings (id) on delete set null,
  add column guest_player_id uuid references guest_players (id) on delete set null,
  add column payment_method text,
  add column paid_at timestamptz,
  add column updated_at timestamptz not null default now();

create index payments_payment_order_id_idx on payments (payment_order_id) where payment_order_id is not null;
create index payments_booking_id_idx on payments (booking_id) where booking_id is not null;
create unique index payments_razorpay_order_id_idx on payments (razorpay_order_id) where razorpay_order_id is not null;
create unique index payments_razorpay_payment_id_idx on payments (razorpay_payment_id) where razorpay_payment_id is not null;

-- ─────────────────────────────────────────────────────────────────────────
-- create_payment_order: the single write path for starting a payment,
-- regardless of source. Validates ownership/facility-match and reads the
-- ALREADY-authoritative amount off the source row (or the plan, for a new
-- membership) — the client's amount is never read, let alone trusted.
-- Reuses a still-valid pending order for the same source instead of
-- creating a duplicate (spec §"Duplicate Order"); an expired one is not
-- reused (spec §"Expired Payment Order") — a fresh row is created instead.
-- ─────────────────────────────────────────────────────────────────────────
create function create_payment_order(
  p_facility_id uuid,
  p_source_type payment_source_type,
  p_booking_id uuid default null,
  p_membership_session_booking_id uuid default null,
  p_member_id uuid default null,
  p_plan_id uuid default null
) returns payment_orders
language plpgsql
as $$
declare
  result payment_orders;
  existing payment_orders;
  fac facilities;
  b bookings;
  msb membership_session_bookings;
  plan membership_plans;
  computed_amount integer;
  computed_member_id uuid;
begin
  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    raise exception 'Facility not found.' using errcode = '23503';
  end if;

  if p_source_type = 'MEMBERSHIP' then
    if p_member_id is null or p_plan_id is null then
      raise exception 'A member and a plan are required for a membership payment.' using errcode = '23514';
    end if;
    select * into plan from membership_plans where id = p_plan_id and facility_id = p_facility_id and is_active;
    if plan.id is null then
      raise exception 'That membership plan is not available for this facility.' using errcode = '23503';
    end if;
    if not exists (select 1 from members where id = p_member_id and facility_id = p_facility_id) then
      raise exception 'That member does not belong to this facility.' using errcode = '23503';
    end if;
    computed_amount := plan.price_inr * 100;
    computed_member_id := p_member_id;

  elsif p_source_type = 'MEMBER_BOOKING' then
    if p_booking_id is null then
      raise exception 'A booking is required for a member booking payment.' using errcode = '23514';
    end if;
    select * into b from bookings where id = p_booking_id and facility_id = p_facility_id;
    if b.id is null then
      raise exception 'That booking does not belong to this facility.' using errcode = '23503';
    end if;
    if b.customer_type <> 'MEMBER' or b.member_id is null then
      raise exception 'That booking is not a member booking.' using errcode = '23514';
    end if;
    if b.status not in ('pending', 'confirmed') then
      raise exception 'That booking is no longer active.' using errcode = '23514';
    end if;
    if b.amount_minor is null or b.amount_minor <= 0 then
      raise exception 'That booking has no payable amount.' using errcode = '23514';
    end if;
    computed_amount := b.amount_minor;
    computed_member_id := b.member_id;

  elsif p_source_type = 'GUEST_BOOKING' then
    if (p_booking_id is not null) = (p_membership_session_booking_id is not null) then
      raise exception 'Provide exactly one of a booking or a membership guest-slot booking.' using errcode = '23514';
    end if;

    if p_booking_id is not null then
      select * into b from bookings where id = p_booking_id and facility_id = p_facility_id;
      if b.id is null then
        raise exception 'That booking does not belong to this facility.' using errcode = '23503';
      end if;
      if b.customer_type <> 'GUEST' then
        raise exception 'That booking is not a guest booking.' using errcode = '23514';
      end if;
      if b.status not in ('pending', 'confirmed') then
        raise exception 'That booking is no longer active.' using errcode = '23514';
      end if;
      if b.amount_minor is null or b.amount_minor <= 0 then
        raise exception 'That booking has no payable amount.' using errcode = '23514';
      end if;
      computed_amount := b.amount_minor;
    else
      -- A row here already proves book_guest_slot's atomic capacity check
      -- passed at booking time — no need to re-validate guest capacity.
      select * into msb from membership_session_bookings where id = p_membership_session_booking_id and facility_id = p_facility_id;
      if msb.id is null then
        raise exception 'That guest slot booking does not belong to this facility.' using errcode = '23503';
      end if;
      if msb.participant_type <> 'GUEST' or msb.status <> 'CONFIRMED' then
        raise exception 'That guest slot booking is not active.' using errcode = '23514';
      end if;
      if msb.amount_minor is null or msb.amount_minor <= 0 then
        raise exception 'That guest slot booking has no payable amount.' using errcode = '23514';
      end if;
      computed_amount := msb.amount_minor;
    end if;
  end if;

  select * into existing from payment_orders
    where facility_id = p_facility_id
      and source_type = p_source_type
      and status in ('CREATED', 'ORDER_CREATED', 'PAYMENT_ATTEMPTED', 'AUTHORIZED')
      and expires_at > now()
      and booking_id is not distinct from p_booking_id
      and membership_session_booking_id is not distinct from p_membership_session_booking_id
      and (p_source_type <> 'MEMBERSHIP' or (member_id = p_member_id and plan_id = p_plan_id))
    order by created_at desc
    limit 1;
  if existing.id is not null then
    return existing;
  end if;

  insert into payment_orders (
    facility_id, source_type, booking_id, membership_session_booking_id, member_id, plan_id,
    amount_minor, currency, status, receipt, expires_at, created_by
  ) values (
    p_facility_id, p_source_type, p_booking_id, p_membership_session_booking_id, computed_member_id, p_plan_id,
    computed_amount, coalesce(fac.currency, 'INR'), 'CREATED',
    'GAMEALL-' || replace(p_source_type::text, '_', '') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
    now() + interval '15 minutes', auth.uid()
  ) returning * into result;

  return result;
end;
$$;

grant execute on function create_payment_order(uuid, payment_source_type, uuid, uuid, uuid, uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_payment_order: read-back after the Edge Function attaches the
-- Razorpay order id, and for polling/checkout-resume in a later phase.
-- ─────────────────────────────────────────────────────────────────────────
create function get_payment_order(p_payment_order_id uuid) returns payment_orders
language sql
stable
as $$
  select * from payment_orders where id = p_payment_order_id;
$$;

grant execute on function get_payment_order(uuid) to authenticated;