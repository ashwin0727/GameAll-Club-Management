-- ═══════════════════════════════════════════════════════════════════════════
-- Guest bookings longer than one hour are secured with a 50% ONLINE advance.
--
-- A player booking more than an hour (say 4 hours at ₹300 = ₹1,200) pays ₹600 online first; the booking is only
-- confirmed once that advance has been received, and the balance is collected later through the existing
-- Pending Payments flow. Bookings of an hour or less are unchanged (the payment link charges the full amount).
--
--   * guest_booking_advance_minor  — the one place the rule lives: duration > 1 hour → 50% (rounded up).
--   * create_payment_order         — takes p_advance; when true, a guest booking longer than an hour gets an
--                                    order for the advance only. The client never supplies an amount.
--   * settle_payment               — an advance settles the booking to CONFIRMED but leaves payment_status
--                                    PENDING (the guest-bookings list derives "partially paid" from the
--                                    payments rows, see 0054); only a full-amount payment marks it PAID.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function guest_booking_advance_minor(p_amount_minor integer, p_start timestamptz, p_end timestamptz)
returns integer
language sql
immutable
as $$
  select case
    when p_end - p_start > interval '1 hour' then ceil(p_amount_minor * 0.5)::integer
    else p_amount_minor
  end
$$;

grant execute on function guest_booking_advance_minor(integer, timestamptz, timestamptz) to authenticated;

drop function if exists create_payment_order(uuid, payment_source_type, uuid, uuid, uuid, uuid);

create function create_payment_order(
  p_facility_id uuid,
  p_source_type payment_source_type,
  p_booking_id uuid default null,
  p_membership_session_booking_id uuid default null,
  p_member_id uuid default null,
  p_plan_id uuid default null,
  p_advance boolean default false
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
      -- Longer than an hour: only the advance is collected online.
      if p_advance then
        computed_amount := guest_booking_advance_minor(b.amount_minor, b.start_time, b.end_time);
      end if;
    else
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
      and amount_minor = computed_amount
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

grant execute on function create_payment_order(uuid, payment_source_type, uuid, uuid, uuid, uuid, boolean) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- settle_payment: identical to 0021 except the booking branch — an advance confirms the booking without marking
-- it fully paid.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function settle_payment(p_payment_order_id uuid) returns payment_orders
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
      exception_reason := 'MEMBERSHIP_INVALID';
    end;
    if exception_reason is null then
      update payments set membership_id = membership_row.id where id = v_transaction_id;
    end if;

  elsif row_.membership_session_booking_id is not null then
    select * into msb from membership_session_bookings where id = row_.membership_session_booking_id and facility_id = row_.facility_id for update;
    if msb.id is null or msb.status <> 'CONFIRMED' then
      exception_reason := 'BOOKING_NO_LONGER_AVAILABLE';
    end if;

  elsif row_.booking_id is not null then
    select * into b from bookings where id = row_.booking_id and facility_id = row_.facility_id for update;
    if b.id is null or b.status = 'cancelled' then
      exception_reason := 'BOOKING_NO_LONGER_AVAILABLE';
    else
      update bookings
        set status = 'confirmed',
            payment_status = case when row_.amount_minor >= coalesce(b.amount_minor, 0) then 'PAID' else b.payment_status end
        where id = b.id;
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
