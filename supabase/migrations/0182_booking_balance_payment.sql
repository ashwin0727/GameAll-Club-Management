-- ═══════════════════════════════════════════════════════════════════════════
-- Paying the BALANCE of a booking online (Player app, Home page).
--
-- A guest booking over an hour is confirmed by a 50% advance paid online (0130/0131); the rest is normally paid at the venue. Once the
-- booking is about to end, Home now asks the player for the balance (0177: pendingPayments, `balance`), and this lets them pay it:
--
--   create_booking_balance_order(p_booking_id)   service role (create-player-booking-payment-link): the payment order for what is still
--                                                owed on a confirmed booking, i.e. its amount minus the online payments already made.
--                                                An open order for the same amount is reused, never a second one.
--   settle_payment                               identical to 0132 except the single-booking branch: a booking is PAID when the payments
--                                                made for it add up to its amount (before: only when this one payment covered all of it).
--
-- The amount is worked out here from the booking and its payments; nothing the app sends is trusted.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function create_booking_balance_order(p_booking_id uuid)
returns payment_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  b bookings;
  fac facilities;
  v_paid_minor integer;
  v_due integer;
  existing payment_orders;
  result payment_orders;
begin
  select * into b from bookings where id = p_booking_id for update;
  if b.id is null then
    raise exception 'We could not find that booking.' using errcode = '23503';
  end if;
  if b.status <> 'confirmed' then
    raise exception 'That booking is not confirmed.' using errcode = '23514';
  end if;
  if b.amount_minor is null or b.amount_minor <= 0 then
    raise exception 'That booking has no payable amount.' using errcode = '23514';
  end if;

  select coalesce(sum(p.amount_inr), 0) * 100 into v_paid_minor from payments p where p.booking_id = b.id and p.status = 'paid';
  v_due := b.amount_minor - v_paid_minor;
  if v_due <= 0 then
    raise exception 'That booking is already paid.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = b.facility_id;

  select * into existing from payment_orders
   where booking_id = b.id
     and source_type = case when b.customer_type = 'GUEST' then 'GUEST_BOOKING' else 'MEMBER_BOOKING' end::payment_source_type
     and status in ('CREATED', 'ORDER_CREATED', 'PAYMENT_ATTEMPTED', 'AUTHORIZED')
     and expires_at > now()
     and amount_minor = v_due
   order by created_at desc limit 1;
  if existing.id is not null then
    return existing;
  end if;

  insert into payment_orders (facility_id, source_type, booking_id, amount_minor, currency, status, receipt, expires_at, created_by)
  values (
    b.facility_id,
    case when b.customer_type = 'GUEST' then 'GUEST_BOOKING' else 'MEMBER_BOOKING' end::payment_source_type,
    b.id, v_due, coalesce(fac.currency, 'INR'), 'CREATED',
    'GAMEALL-BALANCE-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
    now() + interval '15 minutes', null
  ) returning * into result;
  return result;
end;
$$;
revoke all on function create_booking_balance_order(uuid) from public, anon, authenticated;
grant execute on function create_booking_balance_order(uuid) to service_role;

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
  v_row record;
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

  elsif exists (select 1 from payment_order_bookings where payment_order_id = row_.id) then
    -- One payment covering several bookings: confirm each of them. A booking that lapsed or was cancelled in the
    -- meantime is recorded as a settlement exception (the money is then refunded by staff); the others still confirm.
    for v_row in select booking_id, amount_minor from payment_order_bookings where payment_order_id = row_.id order by booking_id loop
      select * into b from bookings where id = v_row.booking_id and facility_id = row_.facility_id for update;
      if b.id is null or b.status = 'cancelled' then
        exception_reason := 'BOOKING_NO_LONGER_AVAILABLE';
      else
        update bookings
          set status = 'confirmed',
              payment_status = case when v_row.amount_minor >= coalesce(b.amount_minor, 0) then 'PAID' else b.payment_status end
          where id = b.id;
      end if;
    end loop;

  elsif row_.booking_id is not null then
    select * into b from bookings where id = row_.booking_id and facility_id = row_.facility_id for update;
    if b.id is null or b.status = 'cancelled' then
      exception_reason := 'BOOKING_NO_LONGER_AVAILABLE';
    else
      update bookings
        set status = 'confirmed',
            payment_status = case
              when row_.amount_minor >= coalesce(b.amount_minor, 0) then 'PAID'
              -- the balance of a booking whose advance was paid earlier: paid in full once the payments add up
              when coalesce((select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'), 0) >= coalesce(b.amount_minor, 0) then 'PAID'
              else b.payment_status end
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
