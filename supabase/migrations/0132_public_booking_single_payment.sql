-- ═══════════════════════════════════════════════════════════════════════════
-- ONE payment for every booking a player makes on the public /book page.
--
-- A player who books several courts or several times pays the advance once, in one Razorpay Checkout, not once per
-- booking. One payment order then covers several bookings:
--
--   * payment_order_bookings      — which bookings an order covers and each one's share of the amount;
--   * create_public_payment_order — validates the held bookings and makes that single order for the sum of their
--                                   advances (service role only; the checkout function checks the phone number first);
--   * apply_payment_verification  — when the payment is captured, records each booking's share as its own payments
--                                   row, so every booking's Paid / Pending figures stay right;
--   * settle_payment              — confirms every booking the order covers;
--   * public_booking_receipt      — paid amount now comes from the payments rows only (an order's total no longer
--                                   belongs to any one booking).
-- Single-booking payments (staff links, member bookings, memberships) behave exactly as before.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists payment_order_bookings (
  payment_order_id uuid not null references payment_orders (id) on delete cascade,
  booking_id uuid not null references bookings (id) on delete cascade,
  amount_minor integer not null check (amount_minor > 0),
  created_at timestamptz not null default now(),
  primary key (payment_order_id, booking_id)
);
create index if not exists payment_order_bookings_booking_id_idx on payment_order_bookings (booking_id);

-- Written only by create_public_payment_order below; nobody reads it directly.
alter table payment_order_bookings enable row level security;

create or replace function create_public_payment_order(p_booking_ids uuid[]) returns payment_orders
language plpgsql
as $$
declare
  ids uuid[];
  b bookings;
  first_b bookings;
  fac facilities;
  amounts integer[] := '{}';
  total integer := 0;
  n integer;
  i integer;
  existing payment_orders;
  result payment_orders;
begin
  select array_agg(x order by x) into ids from (select distinct unnest(p_booking_ids) as x) d;
  n := coalesce(array_length(ids, 1), 0);
  if n = 0 or n > 12 then
    raise exception 'Choose between 1 and 12 bookings to pay for.' using errcode = '23514';
  end if;

  for i in 1..n loop
    select * into b from bookings where id = ids[i] for update;
    if b.id is null or b.customer_type <> 'GUEST' then
      raise exception 'That booking could not be found.' using errcode = '23503';
    end if;
    if i = 1 then
      first_b := b;
    elsif b.facility_id <> first_b.facility_id or b.guest_player_id is distinct from first_b.guest_player_id then
      raise exception 'Those bookings do not belong together.' using errcode = '23514';
    end if;
    if b.status <> 'pending' or b.hold_expires_at is null or b.hold_expires_at <= now() then
      raise exception 'That booking is no longer being held for payment.' using errcode = '23514';
    end if;
    if b.end_time - b.start_time <= interval '1 hour' or coalesce(b.amount_minor, 0) <= 0 then
      raise exception 'That booking does not need an online advance.' using errcode = '23514';
    end if;
    amounts[i] := guest_booking_advance_minor(b.amount_minor, b.start_time, b.end_time);
    total := total + amounts[i];
  end loop;

  select * into fac from facilities where id = first_b.facility_id;

  -- The same bookings already have an open order for this exact amount: hand it back, never a second one.
  select po.* into existing
  from payment_orders po
  where po.booking_id = ids[1]
    and po.source_type = 'GUEST_BOOKING'
    and po.status in ('CREATED', 'ORDER_CREATED', 'PAYMENT_ATTEMPTED', 'AUTHORIZED')
    and po.expires_at > now()
    and po.amount_minor = total
    and (select count(*) from payment_order_bookings x where x.payment_order_id = po.id) = n
    and not exists (select 1 from payment_order_bookings x where x.payment_order_id = po.id and x.booking_id <> all (ids))
  order by po.created_at desc
  limit 1;
  if existing.id is not null then
    return existing;
  end if;

  insert into payment_orders (
    facility_id, source_type, booking_id, amount_minor, currency, status, receipt, expires_at, created_by
  ) values (
    first_b.facility_id, 'GUEST_BOOKING', ids[1], total, coalesce(fac.currency, 'INR'), 'CREATED',
    'GAMEALL-GUESTBOOKING-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
    now() + interval '15 minutes', null
  ) returning * into result;

  for i in 1..n loop
    insert into payment_order_bookings (payment_order_id, booking_id, amount_minor) values (result.id, ids[i], amounts[i]);
  end loop;

  return result;
end;
$$;

-- Callable only by the checkout edge function (service role), which checks the player's phone number first.
revoke all on function create_public_payment_order(uuid[]) from public, anon, authenticated;
grant execute on function create_public_payment_order(uuid[]) to service_role;

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
  v_row record;
  v_first boolean := true;
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

    if exists (select 1 from payment_order_bookings where payment_order_id = result.id) then
      -- One payment covering several bookings: each booking gets its own share as its own payments row, so every
      -- booking's paid / pending figures are right. Razorpay's ids are unique per payment, so only the first row
      -- carries them; the others are tied to the same payment through payment_order_id.
      for v_row in
        select pob.booking_id, pob.amount_minor, b.guest_player_id
        from payment_order_bookings pob
        join bookings b on b.id = pob.booking_id
        where pob.payment_order_id = result.id
        order by pob.booking_id
      loop
        insert into payments (
          facility_id, member_id, payment_order_id, booking_id, guest_player_id,
          razorpay_order_id, razorpay_payment_id, amount_inr, status, payment_method, paid_at
        ) values (
          result.facility_id, result.member_id, result.id, v_row.booking_id, v_row.guest_player_id,
          case when v_first then result.razorpay_order_id end,
          case when v_first then result.razorpay_payment_id end,
          round(v_row.amount_minor / 100.0), 'paid', 'RAZORPAY', now()
        );
        v_first := false;
      end loop;
    else
      insert into payments (
        facility_id, member_id, payment_order_id, booking_id, guest_player_id,
        razorpay_order_id, razorpay_payment_id, amount_inr, status, payment_method, paid_at
      ) values (
        result.facility_id, result.member_id, result.id, result.booking_id, v_guest_player_id,
        result.razorpay_order_id, result.razorpay_payment_id, round(result.amount_minor / 100.0), 'paid', 'RAZORPAY', now()
      )
      on conflict (razorpay_payment_id) where razorpay_payment_id is not null do nothing;
    end if;

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

create or replace function public_booking_receipt(p_booking_id uuid, p_phone text) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b bookings;
  g guest_players;
  c courts;
  fac facilities;
  sport_name text;
  wanted text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10);
  paid bigint;
  total bigint;
  last_payment text;
  last_paid_at timestamptz;
  method text;
begin
  perform release_expired_booking_holds();
  select * into b from bookings where id = p_booking_id and customer_type = 'GUEST';
  if b.id is null then
    return jsonb_build_object('found', false);
  end if;
  select * into g from guest_players where id = b.guest_player_id;
  if g.id is null or length(wanted) < 7 or right(regexp_replace(coalesce(g.phone, ''), '\D', '', 'g'), 10) <> wanted then
    return jsonb_build_object('found', false);
  end if;

  select * into c from courts where id = b.court_id;
  select * into fac from facilities where id = b.facility_id;
  select coalesce(fs.custom_sport_name, sp.name) into sport_name
    from facility_sports fs left join sports sp on sp.id = fs.sport_id
    where fs.id = c.facility_sport_id;

  total := coalesce(b.amount_minor, 0);
  -- What actually arrived: money recorded against the booking, or Razorpay orders that settled, whichever is more;
  -- a booking flagged PAID with no rows behind it still counts as settled (same rule as the Guest Bookings list).
  paid := greatest(
    coalesce((select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'), 0),
    case when b.payment_status = 'PAID' then total else 0 end
  );
  -- The Razorpay payment id lives on the first row of a multi-booking payment; the others point at it by order.
  select coalesce(p.razorpay_payment_id, (select o.razorpay_payment_id from payment_orders o where o.id = p.payment_order_id)), p.paid_at, p.payment_method
    into last_payment, last_paid_at, method
    from payments p where p.booking_id = b.id and p.status = 'paid' order by p.paid_at desc nulls last limit 1;

  return jsonb_build_object(
    'found', true,
    'bookingId', b.id,
    'code', 'GBK' || upper(substr(replace(b.id::text, '-', ''), 1, 4)),
    'status', b.status,
    'confirmed', b.status in ('confirmed', 'completed'),
    'cancelled', b.status = 'cancelled',
    'holdExpiresAt', b.hold_expires_at,
    'facilityName', fac.name,
    'sportName', coalesce(sport_name, 'Sport'),
    'courtName', c.name,
    'startTime', b.start_time,
    'endTime', b.end_time,
    'guestName', g.name,
    'guestPhone', g.phone,
    'partySize', b.party_size,
    'currency', coalesce(b.currency, 'INR'),
    'amountMinor', total,
    'paidMinor', least(paid, total),
    'outstandingMinor', greatest(total - paid, 0),
    'paymentStatus', case when total > 0 and paid >= total then 'PAID' when paid > 0 then 'PARTIALLY_PAID' else 'PENDING' end,
    'paymentMethod', coalesce(method, b.payment_method),
    'paymentReference', last_payment,
    'paidAt', last_paid_at
  );
end;
$$;

grant execute on function public_booking_receipt(uuid, text) to anon, authenticated;
