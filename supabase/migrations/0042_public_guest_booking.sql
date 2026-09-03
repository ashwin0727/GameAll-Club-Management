-- ═══════════════════════════════════════════════════════════════════════════
-- Public guest booking (/book/<facilityId>) — three anon-callable
-- SECURITY DEFINER functions, following the same shape as the public
-- membership sign-up in 0026/0027.
--
-- No new availability engine, pricing logic or booking path is introduced
-- here. Each function is a thin, security-checked wrapper over what already
-- exists:
--
--   booking_window_fits_operating_hours  → is the court open then
--   court_has_active_membership_window   → is the slot membership-protected
--   resolve_booking_price                → what it costs
--   find_or_create_guest                 → the guest/customer record
--   create_booking                       → the authoritative court booking
--   book_guest_slot                      → released membership capacity
--
-- Concurrency is left to the database primitives that already guarantee it:
-- the bookings_no_overlap GiST exclusion constraint for court bookings, and
-- book_guest_slot's `select … for update` on the session row for released
-- capacity. Nothing relies on the browser's view of availability.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- What the public page may know about a facility: its name, and the sports
-- it offers. Deliberately narrow — no owner, no contact, no counts, no
-- settings, nothing about memberships.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_public_booking_facility(p_facility_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'facilityId', f.id,
    'facilityName', f.name,
    'city', coalesce(f.city, ''),
    'currency', coalesce(f.currency, 'INR'),
    'sports', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'facilitySportId', fs.id,
          'name', coalesce(fs.custom_sport_name, sp.name)
        ) order by coalesce(fs.custom_sport_name, sp.name)
      )
      from facility_sports fs
      left join sports sp on sp.id = fs.sport_id
      where fs.facility_id = f.id
        and exists (
          select 1 from courts c
          where c.facility_sport_id = fs.id and not c.archived
        )
    ), '[]'::jsonb)
  )
  from facilities f
  where f.id = p_facility_id;
$$;

grant execute on function get_public_booking_facility(uuid) to anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Bookable slots for one sport on one date, per court.
--
-- A slot is offered only when it is inside the court's operating hours, is
-- not already taken, and is not protected membership capacity. Where a
-- membership session covers the slot, it becomes bookable only for as many
-- seats as the owner has explicitly released and not yet sold.
--
-- The payload carries nothing operational: no session id, no batch id, no
-- capacity, no member counts, no release counts. Just a time, whether it
-- can be booked, and the price.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_public_court_availability(
  p_facility_id uuid,
  p_facility_sport_id uuid,
  p_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  fac facilities;
  tz text;
  result jsonb := '[]'::jsonb;
  c record;
  h integer;
  slot_start timestamptz;
  slot_end timestamptz;
  slots jsonb;
  released integer;
  guest_booked integer;
  is_available boolean;
  price integer;
begin
  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    return '[]'::jsonb;
  end if;
  tz := coalesce(fac.timezone, 'Asia/Kolkata');

  for c in
    select ct.id, ct.name
    from courts ct
    where ct.facility_id = p_facility_id
      and ct.facility_sport_id = p_facility_sport_id
      and not ct.archived
    order by ct.display_order, ct.name
  loop
    slots := '[]'::jsonb;

    for h in 0..23 loop
      slot_start := (p_date::text || ' ' || lpad(h::text, 2, '0') || ':00:00')::timestamp at time zone tz;
      slot_end := slot_start + interval '1 hour';

      -- Never offer a slot that has already started.
      continue when slot_end <= now();

      -- Same operating-hours authority the admin booking path uses, so a
      -- court override is honoured here without restating the rules.
      continue when not booking_window_fits_operating_hours(p_facility_id, c.id, slot_start, slot_end);

      is_available := not exists (
        select 1
        from bookings b
        where b.court_id = c.id
          and b.status in ('pending', 'confirmed')
          and tstzrange(b.start_time, b.end_time) && tstzrange(slot_start, slot_end)
      );

      if is_available and court_has_active_membership_window(c.id, slot_start, slot_end, tz) then
        -- Membership capacity is protected by default. It opens to the
        -- public only for seats the owner released and that are still free.
        select
          coalesce(ms.released_capacity, 0),
          coalesce((
            select count(*)
            from membership_session_bookings msb
            where msb.session_id = ms.id
              and msb.participant_type = 'GUEST'
              and msb.status = 'CONFIRMED'
          ), 0)
        into released, guest_booked
        from membership_batches mb
        left join membership_sessions ms
          on ms.batch_id = mb.id and ms.session_date = p_date
        where mb.court_id = c.id
          and mb.is_active
          and extract(dow from (slot_start at time zone tz)) = any(mb.days_of_week)
          and mb.start_time < (slot_end at time zone tz)::time
          and mb.end_time > (slot_start at time zone tz)::time
        limit 1;

        is_available := coalesce(released, 0) > coalesce(guest_booked, 0);
      end if;

      price := resolve_booking_price(p_facility_sport_id, c.id, slot_start, slot_end, tz);

      slots := slots || jsonb_build_object(
        'startTime', slot_start,
        'endTime', slot_end,
        'available', is_available,
        'priceMinor', coalesce(price, 0)
      );
    end loop;

    if jsonb_array_length(slots) > 0 then
      result := result || jsonb_build_object(
        'courtId', c.id,
        'courtName', c.name,
        'slots', slots
      );
    end if;
  end loop;

  return result;
end;
$$;

grant execute on function get_public_court_availability(uuid, uuid, date) to anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Create the booking.
--
-- Re-checks availability server-side at the moment of writing: whatever the
-- browser believed a minute ago is irrelevant. Routes to the existing
-- create_booking for a normal court slot, or to book_guest_slot when the
-- owner has released membership capacity — each of which carries its own
-- concurrency guarantee, so two guests racing for one remaining seat cannot
-- both win.
--
-- Never creates an auth account, a member, or a membership. The guest is
-- recorded through find_or_create_guest, which reuses an existing guest at
-- the same facility with the same phone number.
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
begin
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Please enter your name.' using errcode = '23514';
  end if;

  -- Phone is the identity this booking is looked up by, so it is validated
  -- rather than trusted: 10–15 digits once punctuation is stripped.
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

  if court_has_active_membership_window(p_court_id, p_start_time, p_end_time, tz) then
    -- Released membership capacity. Locate the batch covering this window,
    -- then let book_guest_slot do the capacity check under its own row lock.
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
        -- book_guest_slot refuses once released capacity is exhausted. That
        -- is the race being lost, not a fault worth surfacing verbatim.
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

  -- Ordinary court slot. create_booking re-validates operating hours, refuses
  -- membership-protected windows and prices the slot; the bookings_no_overlap
  -- exclusion constraint rejects the loser of a race for the same slot.
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
    'bookingStatus', booking.status
  );
end;
$$;

grant execute on function public_create_guest_booking(
  uuid, uuid, timestamptz, timestamptz, text, text, text, text, text, integer
) to anon, authenticated;
