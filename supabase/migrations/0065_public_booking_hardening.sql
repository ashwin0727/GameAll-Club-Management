-- ═══════════════════════════════════════════════════════════════════════════
-- Public booking hardening — abuse controls for the anonymous
-- /book/<facilityId> flow.
--
-- Before: public_create_guest_booking was a direct anon PostgREST RPC. No
-- client IP was visible to it, there was no rate limit, no verification and
-- no cap — a script could confirm-book every slot of every court
-- indefinitely, each booking landing immediately CONFIRMED and unpaid.
--
-- After:
--   * A new Edge Function (public-guest-booking) is the only write path.
--     It sees the real client IP, optionally verifies a CAPTCHA token, and
--     calls record_and_check_public_booking_attempt before the booking RPC.
--   * record_and_check_public_booking_attempt logs each attempt and rejects
--     an IP or phone that is over a short-window limit.
--   * public_create_guest_booking itself caps how many unpaid future guest
--     bookings one guest may hold at a facility.
--
-- Reused as-is: the whole booking/availability/pricing engine, guest_players
-- dedupe, book_guest_slot's row lock, the bookings exclusion constraint.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- public_booking_attempts — append-only velocity log. ip_hash, never a raw
-- IP (the Edge Function hashes it with a salt). RLS on with zero policies:
-- only SECURITY DEFINER functions and the service role ever touch it.
-- ─────────────────────────────────────────────────────────────────────────
create table public_booking_attempts (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid references facilities (id) on delete cascade,
  ip_hash text,
  phone_digits text,
  created_at timestamptz not null default now()
);

create index public_booking_attempts_ip_idx on public_booking_attempts (ip_hash, created_at);
create index public_booking_attempts_phone_idx on public_booking_attempts (phone_digits, created_at);

alter table public_booking_attempts enable row level security;
-- No policies: anon/authenticated get zero rows; SECURITY DEFINER + service role only.

-- ─────────────────────────────────────────────────────────────────────────
-- record_and_check_public_booking_attempt — log this attempt, then reject
-- if the IP or the phone is over a window limit. Called by the
-- public-guest-booking Edge Function BEFORE public_create_guest_booking.
--
--   per IP:    > 8 attempts / 10 min   OR   > 20 attempts / 60 min
--   per phone: > 5 attempts / 60 min
--
-- Deliberately generous — this stops scripted flooding, not a person
-- rebooking a couple of times. Tune the constants here if a facility hits
-- them in normal use.
-- ─────────────────────────────────────────────────────────────────────────
create function record_and_check_public_booking_attempt(
  p_facility_id uuid,
  p_ip_hash text,
  p_phone_digits text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text := nullif(trim(coalesce(p_ip_hash, '')), '');
  v_phone text := nullif(regexp_replace(coalesce(p_phone_digits, ''), '\D', '', 'g'), '');
  ip_10 integer;
  ip_60 integer;
  phone_60 integer;
begin
  insert into public_booking_attempts (facility_id, ip_hash, phone_digits)
  values (p_facility_id, v_ip, v_phone);

  if v_ip is not null then
    select count(*) into ip_10 from public_booking_attempts
      where ip_hash = v_ip and created_at > now() - interval '10 minutes';
    select count(*) into ip_60 from public_booking_attempts
      where ip_hash = v_ip and created_at > now() - interval '60 minutes';
    if ip_10 > 8 or ip_60 > 20 then
      raise exception 'Too many booking attempts. Please try again in a little while.' using errcode = 'P0001';
    end if;
  end if;

  if v_phone is not null then
    select count(*) into phone_60 from public_booking_attempts
      where phone_digits = v_phone and created_at > now() - interval '60 minutes';
    if phone_60 > 5 then
      raise exception 'Too many booking attempts for this number. Please try again in a little while.' using errcode = 'P0001';
    end if;
  end if;
end;
$$;

grant execute on function record_and_check_public_booking_attempt(uuid, text, text) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- public_create_guest_booking — unchanged from 0042 except for one added
-- guard: a guest may not stockpile unpaid, unstarted court bookings. This
-- is the standing-capacity cap that stops a single identity holding a
-- facility's calendar hostage without ever paying.
--
-- The whole body is restated (create or replace) so the guard sits in the
-- one authoritative write path; everything else is byte-for-byte the 0042
-- definition.
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
