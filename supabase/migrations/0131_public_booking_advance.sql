-- ═══════════════════════════════════════════════════════════════════════════
-- Public booking page: a booking longer than one hour is secured with a 50% ONLINE advance.
--
-- (Staff-made guest bookings got the same rule in 0130.) On /book/<facility>:
--   * public_create_guest_booking makes such a booking a PENDING hold on the court, with hold_expires_at 30
--     minutes ahead, and tells the browser an advance is due (advanceRequired / advanceMinor);
--   * the player pays that advance in Razorpay Checkout, opened straight from the booking page (the
--     public-booking-checkout edge function creates the order and verifies the payment — no link is made or shared);
--   * a paid advance settles the booking to CONFIRMED (settle_payment, 0130); an unpaid one is cancelled once
--     the hold lapses, freeing the court (release_expired_booking_holds).
-- Bookings of an hour or less are unchanged: confirmed at once, paid at the venue.
-- ═══════════════════════════════════════════════════════════════════════════

alter table bookings add column if not exists hold_expires_at timestamptz;

-- A payment link for an anonymous player is made by a function running as the service role, so there is no
-- signed-in profile to record as the creator.
alter table payment_orders alter column created_by drop not null;

-- ─────────────────────────────────────────────────────────────────────────
-- release_expired_booking_holds — cancels advance holds whose time ran out without a payment being captured.
-- Safe for anyone to call: it only ever touches rows that are already past their own deadline and unpaid.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function release_expired_booking_holds() returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  released integer;
begin
  with expired as (
    update bookings b
      set status = 'cancelled', cancellation_reason = 'Advance payment not received in time'
      where b.status = 'pending'
        and b.hold_expires_at is not null
        and b.hold_expires_at < now()
        and b.payment_status = 'PENDING'
        and not exists (
          select 1 from payment_orders po
          where po.booking_id = b.id
            and po.status in ('PAYMENT_VERIFIED', 'AUTHORIZED', 'CAPTURED', 'COMPLETED')
        )
      returning b.id
  )
  select count(*) into released from expired;
  return released;
end;
$$;

grant execute on function release_expired_booking_holds() to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- public_booking_receipt — everything the confirmation page and the invoice show for one booking: who booked, when,
-- which sport and court, and how much of it is paid. The booking id alone is not enough; the phone number the
-- booking was made with must match.
--   paymentStatus: PAID (nothing left), PARTIALLY_PAID (an advance is in), PENDING (nothing paid yet).
-- ─────────────────────────────────────────────────────────────────────────
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
    coalesce((select sum(po.amount_minor) from payment_orders po where po.booking_id = b.id and po.status in ('CAPTURED', 'COMPLETED')), 0),
    case when b.payment_status = 'PAID' then total else 0 end
  );
  select p.razorpay_payment_id, p.paid_at, p.payment_method into last_payment, last_paid_at, method
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

-- ─────────────────────────────────────────────────────────────────────────
-- public_create_guest_booking — 0065's body, plus the advance hold above.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public_create_guest_booking(
  p_facility_id uuid,
  p_court_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_name text,
  p_phone text,
  p_email text default null,
  p_purpose text default null,
  p_notes text default null,
  p_party_size integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  fac facilities;
  court courts;
  tz text;
  guest guest_players;
  digits text;
  booking bookings;
  session_booking membership_session_bookings;
  batch membership_batches;
  session_row membership_sessions;
  guest_booked integer;
  combined_notes text;
  booking_code text;
  amount integer;
  sport_name text;
  unpaid_pending integer;
begin
  -- Free any court time held for an advance that never arrived, so it can be booked again.
  perform release_expired_booking_holds();

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Please enter your name.' using errcode = '23514';
  end if;

  digits := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  if length(digits) < 10 or length(digits) > 15 then
    raise exception 'Please enter a valid mobile number.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    raise exception 'We could not find that venue.' using errcode = '23503';
  end if;
  tz := coalesce(fac.timezone, 'Asia/Kolkata');

  select * into court from courts
  where id = p_court_id and facility_id = p_facility_id and not archived;
  if court.id is null then
    raise exception 'We could not find that court.' using errcode = '23503';
  end if;

  if p_end_time <= p_start_time then
    raise exception 'Please choose a valid time.' using errcode = '23514';
  end if;
  if p_start_time <= now() then
    raise exception 'That time has already passed. Please choose another time.' using errcode = '23514';
  end if;

  select coalesce(fs.custom_sport_name, sp.name) into sport_name
  from facility_sports fs
  left join sports sp on sp.id = fs.sport_id
  where fs.id = court.facility_sport_id;

  combined_notes := nullif(trim(concat_ws(
    ' — ',
    nullif(trim(coalesce(p_purpose, '')), ''),
    nullif(trim(coalesce(p_notes, '')), '')
  )), '');

  guest := find_or_create_guest(p_facility_id, p_name, p_phone, nullif(trim(coalesce(p_email, '')), ''), null);

  -- Standing-capacity cap: no more than 4 unpaid, not-yet-started court
  -- bookings per guest per facility. Paid or past bookings never count.
  select count(*) into unpaid_pending
  from bookings b
  where b.guest_player_id = guest.id
    and b.customer_type = 'GUEST'
    and b.status in ('pending', 'confirmed')
    and b.payment_status = 'PENDING'
    and b.start_time > now();
  if unpaid_pending >= 4 then
    raise exception 'You have unpaid bookings still pending. Please complete or cancel them before booking again.'
      using errcode = '23514';
  end if;

  if court_has_active_membership_window(p_court_id, p_start_time, p_end_time, tz) then
    select mb.* into batch
    from membership_batches mb
    where mb.court_id = p_court_id
      and mb.is_active
      and extract(dow from (p_start_time at time zone tz)) = any(mb.days_of_week)
      and mb.start_time < (p_end_time at time zone tz)::time
      and mb.end_time > (p_start_time at time zone tz)::time
    limit 1;

    if batch.id is null then
      raise exception 'Sorry, this court is no longer available.' using errcode = '23514';
    end if;

    begin
      session_booking := book_guest_slot(batch.id, (p_start_time at time zone tz)::date, guest.id);
    exception
      when others then
        raise exception 'Sorry, this court is no longer available.' using errcode = '23514';
    end;

    select * into session_row from membership_sessions where id = session_booking.session_id;
    booking_code := 'GSB' || upper(substr(replace(session_booking.id::text, '-', ''), 1, 4));
    amount := session_booking.amount_minor;

    return jsonb_build_object(
      'bookingId', session_booking.id,
      'code', booking_code,
      'facilityName', fac.name,
      'sportName', coalesce(sport_name, 'Sport'),
      'courtName', court.name,
      'startTime', p_start_time,
      'endTime', p_end_time,
      'guestName', guest.name,
      'guestPhone', guest.phone,
      'amountMinor', coalesce(amount, 0),
      'currency', coalesce(fac.currency, 'INR'),
      'paymentStatus', 'PENDING',
      'bookingStatus', 'CONFIRMED'
    );
  end if;

  begin
    booking := create_booking(
      p_facility_id := p_facility_id,
      p_court_id := p_court_id,
      p_start_time := p_start_time,
      p_end_time := p_end_time,
      p_customer_type := 'GUEST',
      p_member_id := null,
      p_guest_name := null,
      p_guest_phone := null,
      p_notes := combined_notes,
      p_payment_status := 'PENDING',
      p_guest_player_id := guest.id,
      p_party_size := greatest(coalesce(p_party_size, 1), 1),
      p_payment_method := null
    );
  exception
    when exclusion_violation then
      raise exception 'Sorry, this court is no longer available.' using errcode = '23514';
    when check_violation then
      raise exception 'Sorry, this court is no longer available.' using errcode = '23514';
  end;

  -- A booking longer than an hour is only accepted once its 50% advance is paid online: until then it is a PENDING
  -- hold on the court that lapses after 30 minutes (release_expired_booking_holds). The payment settles it to CONFIRMED.
  if booking.end_time - booking.start_time > interval '1 hour' then
    update bookings
      set status = 'pending', hold_expires_at = now() + interval '30 minutes'
      where id = booking.id
      returning * into booking;
  end if;

  booking_code := 'GBK' || upper(substr(replace(booking.id::text, '-', ''), 1, 4));

  return jsonb_build_object(
    'bookingId', booking.id,
    'code', booking_code,
    'facilityName', fac.name,
    'sportName', coalesce(sport_name, 'Sport'),
    'courtName', court.name,
    'startTime', booking.start_time,
    'endTime', booking.end_time,
    'guestName', guest.name,
    'guestPhone', guest.phone,
    'amountMinor', coalesce(booking.amount_minor, 0),
    'currency', coalesce(booking.currency, 'INR'),
    'paymentStatus', booking.payment_status,
    'bookingStatus', booking.status,
    'advanceRequired', booking.hold_expires_at is not null,
    'advanceMinor', case when booking.hold_expires_at is not null then guest_booking_advance_minor(coalesce(booking.amount_minor, 0), booking.start_time, booking.end_time) else 0 end,
    'holdExpiresAt', booking.hold_expires_at
  );
end;
$$;

grant execute on function public_create_guest_booking(
  uuid, uuid, timestamptz, timestamptz, text, text, text, text, text, integer
) to anon, authenticated;
