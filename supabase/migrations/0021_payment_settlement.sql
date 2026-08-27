-- ═══════════════════════════════════════════════════════════════════════════
-- Payment Settlement & Business Confirmation — Phase 5.
--
-- VERIFIED PAYMENT → PAYMENT CAPTURED → BUSINESS SETTLEMENT → CONFIRM
-- BOOKING / ACTIVATE MEMBERSHIP → FINANCE.
--
-- A captured payment is the TRIGGER for settlement, never a blind
-- confirmation — settle_payment revalidates the underlying booking/
-- membership is still confirmable *right now* (it may have been cancelled,
-- or a plan deactivated, while the payment was in flight) before touching
-- any business table. If it isn't, the payment and its Finance transaction
-- are preserved exactly as-is and a settlement_exceptions row records why
-- — refund/resolution is the next phase's job, not this one's.
--
-- Reused as-is: payment_orders (0016), payments (0001+0016), bookings
-- (0001+0009+0011), membership_session_bookings (0014 — its capacity check
-- already runs atomically at booking-creation time via book_guest_slot, so
-- there is no capacity left to "consume" here, only to revalidate),
-- memberships/membership_plans (0001), create_membership (0012, refactored
-- below into a shared helper — not duplicated).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- settlement_exceptions — the owner-visible audit trail for "payment
-- received, but the business operation needs attention." Facility-staff
-- RLS, same shape as every other facility-scoped table in this project.
-- ─────────────────────────────────────────────────────────────────────────
create table settlement_exceptions (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  payment_order_id uuid not null references payment_orders (id) on delete cascade,
  transaction_id uuid references payments (id) on delete set null,
  source_type payment_source_type not null,
  -- The booking/membership-session-booking/member id this exception is
  -- about — deliberately untyped (no FK) since it can point at any of
  -- three different tables depending on source_type, same "explicit typed
  -- alternative to a polymorphic FK" tradeoff payment_orders itself made;
  -- here there's genuinely one nullable slot rather than three, so a plain
  -- uuid is simpler and the row is always read joined through payment_orders
  -- anyway.
  source_id uuid,
  reason text not null check (reason in (
    'BOOKING_NO_LONGER_AVAILABLE',
    'GUEST_CAPACITY_EXHAUSTED',
    'MEMBERSHIP_INVALID',
    'BUSINESS_VALIDATION_FAILED',
    'DATABASE_SETTLEMENT_FAILURE'
  )),
  status text not null default 'OPEN' check (status in ('OPEN', 'RESOLVED')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index settlement_exceptions_facility_id_idx on settlement_exceptions (facility_id);
create index settlement_exceptions_payment_order_id_idx on settlement_exceptions (payment_order_id);
create index settlement_exceptions_status_idx on settlement_exceptions (status) where status = 'OPEN';

alter table settlement_exceptions enable row level security;
create policy "settlement_exceptions_select_staff" on settlement_exceptions for select
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));
create policy "settlement_exceptions_write_staff" on settlement_exceptions for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

-- ─────────────────────────────────────────────────────────────────────────
-- activate_membership — extracted from create_membership's body so
-- settlement can reuse the exact same validity-calculation and
-- membership-row-creation logic without also triggering create_membership's
-- own `payments` insert (which has no payment_order_id/Razorpay linkage at
-- all — correct for its original manual/cash-assignment caller, but would
-- create a SECOND, untraceable transaction row for a Razorpay-settled
-- membership, alongside the one apply_payment_verification already
-- inserted). create_membership itself becomes a thin wrapper below so its
-- existing behavior/signature/grants for the manual assignment flow is
-- completely unchanged.
-- ─────────────────────────────────────────────────────────────────────────
create function activate_membership(
  p_member_id uuid,
  p_facility_id uuid,
  p_plan_id uuid,
  p_start_date date
) returns memberships
language plpgsql
as $$
declare
  plan membership_plans;
  result memberships;
  computed_end date;
  computed_status membership_status;
begin
  select * into plan from membership_plans
    where id = p_plan_id and facility_id = p_facility_id and is_active;
  if plan.id is null then
    raise exception 'Membership plan not found for this facility.' using errcode = '23503';
  end if;

  computed_end := p_start_date + plan.duration_days;
  computed_status := case when computed_end >= current_date then 'active' else 'expired' end;

  insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date)
  values (p_facility_id, p_member_id, p_plan_id, computed_status, p_start_date, computed_end)
  returning * into result;

  return result;
end;
$$;

grant execute on function activate_membership(uuid, uuid, uuid, date) to authenticated;

create or replace function create_membership(
  p_member_id uuid,
  p_facility_id uuid,
  p_plan_id uuid,
  p_start_date date,
  p_payment_status payment_status default 'created'
) returns memberships
language plpgsql
as $$
declare
  plan membership_plans;
  result memberships;
begin
  result := activate_membership(p_member_id, p_facility_id, p_plan_id, p_start_date);

  -- activate_membership already proved p_plan_id belongs to this facility
  -- and is active; re-select just for price_inr.
  select * into plan from membership_plans where id = p_plan_id;
  if plan.price_inr > 0 then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status)
    values (p_facility_id, p_member_id, result.id, plan.price_inr, p_payment_status);
  end if;

  return result;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- settle_payment — the named settlement service the spec asks for.
-- Idempotent (safe to call any number of times for the same order) and
-- retryable (a genuine DB error here does not corrupt payment_orders —
-- see the sub-block in apply_payment_verification below). Requires the
-- order to already be CAPTURED; a business-rule failure (cancelled
-- booking, deactivated plan, ...) is recorded as a settlement_exceptions
-- row and the order moves to SETTLEMENT_EXCEPTION — never silently
-- retried forever, never loses the payment.
-- ─────────────────────────────────────────────────────────────────────────
create function settle_payment(p_payment_order_id uuid) returns payment_orders
language plpgsql
as $$
declare
  row_ payment_orders;
  b bookings;
  msb membership_session_bookings;
  membership_row memberships;
  v_transaction_id uuid;
  exception_reason text;
begin
  select * into row_ from payment_orders where id = p_payment_order_id for update;
  if row_.id is null then
    raise exception 'Payment order not found.' using errcode = 'P0002';
  end if;

  -- §"Idempotency": already settled (successfully or with a recorded
  -- exception) — never re-confirm a booking, re-activate a membership, or
  -- create a second transaction.
  if row_.status in ('COMPLETED', 'SETTLEMENT_EXCEPTION') then
    return row_;
  end if;

  if row_.status <> 'CAPTURED' then
    raise exception 'Payment order is not ready for settlement (status=%).', row_.status using errcode = '23514';
  end if;

  select id into v_transaction_id from payments where payment_order_id = row_.id order by created_at desc limit 1;
  exception_reason := null;

  if row_.source_type = 'MEMBERSHIP' then
    begin
      membership_row := activate_membership(row_.member_id, row_.facility_id, row_.plan_id, current_date);
    exception when sqlstate '23503' then
      -- The plan was deactivated (or otherwise no longer valid) between
      -- checkout and settlement — a genuine business rejection, not a
      -- system failure.
      exception_reason := 'MEMBERSHIP_INVALID';
    end;
    if exception_reason is null then
      update payments set membership_id = membership_row.id where id = v_transaction_id;
    end if;

  elsif row_.membership_session_booking_id is not null then
    -- Guest-slot booking: book_guest_slot already atomically checked and
    -- consumed capacity at booking-creation time (0014_membership_sessions.sql)
    -- — there is nothing left to "consume" here, only to revalidate the
    -- booking is still CONFIRMED (it may have been cancelled since).
    select * into msb from membership_session_bookings where id = row_.membership_session_booking_id and facility_id = row_.facility_id for update;
    if msb.id is null or msb.status <> 'CONFIRMED' then
      exception_reason := 'BOOKING_NO_LONGER_AVAILABLE';
    end if;

  elsif row_.booking_id is not null then
    -- MEMBER_BOOKING, or GUEST_BOOKING via an ad-hoc booking row. The
    -- court/time slot itself has been exclusively held since booking
    -- creation by bookings' own exclusion constraint (0001_init.sql) — the
    -- only thing that can have changed is the booking being cancelled.
    select * into b from bookings where id = row_.booking_id and facility_id = row_.facility_id for update;
    if b.id is null or b.status = 'cancelled' then
      exception_reason := 'BOOKING_NO_LONGER_AVAILABLE';
    else
      update bookings set status = 'confirmed', payment_status = 'PAID' where id = b.id;
    end if;

  else
    exception_reason := 'BUSINESS_VALIDATION_FAILED';
  end if;

  if exception_reason is not null then
    insert into settlement_exceptions (facility_id, payment_order_id, transaction_id, source_type, source_id, reason)
    values (row_.facility_id, row_.id, v_transaction_id, row_.source_type, coalesce(row_.booking_id, row_.membership_session_booking_id, row_.member_id), exception_reason);

    update payment_orders set status = 'SETTLEMENT_EXCEPTION' where id = row_.id returning * into row_;
    return row_;
  end if;

  update payment_orders set status = 'COMPLETED' where id = row_.id returning * into row_;
  return row_;
end;
$$;

grant execute on function settle_payment(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- apply_payment_verification (0019_payment_verification.sql) — one
-- addition: a genuine transition into CAPTURED now triggers settlement
-- inline, in the SAME transaction as the CAPTURED status write and the
-- payments insert (§"Database Transaction": these must never be partially
-- applied). Wrapped in its own sub-block: if settle_payment raises an
-- unexpected error, only settle_payment's own effects roll back (via the
-- implicit savepoint a plpgsql BEGIN/EXCEPTION block creates) — the
-- CAPTURED status and the Finance transaction row survive, so the order
-- is left CAPTURED and retryable (via settle_payment directly, or the
-- settle-payment Edge Function) rather than reverting to an earlier
-- status and looking like the payment never happened.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function apply_payment_verification(
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

  if row_.razorpay_order_id is distinct from p_razorpay_order_id then
    raise exception 'Razorpay order does not match this payment order.' using errcode = '23514';
  end if;

  if row_.razorpay_payment_id is not null and row_.razorpay_payment_id is distinct from p_razorpay_payment_id then
    raise exception 'A different payment has already been recorded for this order.' using errcode = '23514';
  end if;

  if p_amount_minor is distinct from row_.amount_minor or upper(p_currency) is distinct from upper(row_.currency) then
    raise exception 'Payment amount or currency does not match the expected amount.' using errcode = '23514';
  end if;

  if p_razorpay_status not in ('AUTHORIZED', 'CAPTURED', 'FAILED', 'PAYMENT_VERIFIED') then
    raise exception 'Unknown Razorpay-derived status: %', p_razorpay_status using errcode = '22023';
  end if;
  target_status := p_razorpay_status::payment_order_status;

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
    return row_;
  end if;

  update payment_orders
    set status = target_status,
        razorpay_payment_id = coalesce(p_razorpay_payment_id, razorpay_payment_id),
        razorpay_signature = coalesce(p_razorpay_signature, razorpay_signature)
    where id = p_payment_order_id
    returning * into result;

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
    on conflict (razorpay_payment_id) where razorpay_payment_id is not null do nothing;

    begin
      perform settle_payment(result.id);
      -- Re-read: settle_payment may have advanced status to COMPLETED/
      -- SETTLEMENT_EXCEPTION — the caller (verify-razorpay-payment /
      -- razorpay-webhook) should see the final settled state, not the
      -- transient CAPTURED it started from.
      select * into result from payment_orders where id = result.id;
    exception when others then
      raise warning 'Settlement failed for payment order %: %', result.id, sqlerrm;
    end;
  end if;

  return result;
end;
$$;

grant execute on function apply_payment_verification(uuid, text, text, text, integer, text, text) to authenticated;