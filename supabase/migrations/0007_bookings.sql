-- ═══════════════════════════════════════════════════════════════════════════
-- Bookings — reconciles the 0001 stub `bookings` table with the courts/
-- pricing/operating-hours system built since (0002/0004/0005).
--
--   facilities → courts (playing areas) → bookings ← profiles (member)
--                                              ↑
--                                        guest_name/guest_phone
--                                        (no account required)
--
-- Conflict prevention: the 0001 exclusion constraint (court_id × time range,
-- pending/confirmed only) already guarantees no two live bookings on the
-- same court can overlap — enforced by Postgres itself, not application code.
-- This migration adds the missing pieces: guest customers, a captured price,
-- and a server-side operating-hours check so a booking can't be made for a
-- time the facility/court is actually closed.
-- ═══════════════════════════════════════════════════════════════════════════

alter table bookings
  alter column member_id drop not null,
  add column customer_type text not null default 'MEMBER' check (customer_type in ('MEMBER', 'GUEST')),
  add column guest_name text,
  add column guest_phone text,
  add column facility_sport_id uuid references facility_sports (id) on delete restrict,
  add column amount_minor integer check (amount_minor is null or amount_minor >= 0),
  add column currency text not null default 'INR',
  add column notes text,
  add column updated_at timestamptz not null default now(),
  add constraint bookings_customer_check check (
    (customer_type = 'MEMBER' and member_id is not null and guest_name is null and guest_phone is null)
    or (customer_type = 'GUEST' and member_id is null and guest_name is not null and trim(guest_name) <> '')
  );

create trigger bookings_set_updated_at
  before update on bookings
  for each row execute function set_updated_at();

-- Denormalizes facility_sport_id from the booked court and defends against a
-- client sending a court that doesn't actually belong to the facility it
-- claims — the same integrity pattern 0002 uses for courts.facility_sport_id.
create function enforce_booking_court_consistency() returns trigger
language plpgsql
as $$
declare
  c courts;
begin
  select * into c from courts where id = new.court_id;
  if c is null then
    raise exception 'court % does not exist', new.court_id using errcode = '23503';
  end if;
  if c.facility_id is distinct from new.facility_id then
    raise exception 'booking facility_id must match its court''s facility_id' using errcode = '23514';
  end if;
  if c.archived or c.status <> 'ACTIVE' or not c.booking_enabled then
    raise exception 'This court is not available for booking.' using errcode = '23514';
  end if;
  new.facility_sport_id := c.facility_sport_id;
  return new;
end;
$$;

create trigger bookings_enforce_court_consistency
  before insert or update of court_id on bookings
  for each row execute function enforce_booking_court_consistency();

create index bookings_facility_sport_id_idx on bookings (facility_sport_id);
create index bookings_status_idx on bookings (status);

-- ─────────────────────────────────────────────────────────────────────────
-- booking_window_fits_operating_hours: does [p_start, p_end) fall entirely
-- within an open window (playing-area override if one exists, else the
-- facility schedule) on the local calendar day it starts on? V1 requires the
-- booking to stay within a single local calendar day (matches how every
-- booking is actually made from the UI — pick one date, pick a time range).
-- ─────────────────────────────────────────────────────────────────────────
create function booking_window_fits_operating_hours(
  p_facility_id uuid,
  p_court_id uuid,
  p_start timestamptz,
  p_end timestamptz
) returns boolean
language plpgsql
stable
as $$
declare
  tz text;
  local_start timestamp;
  local_end timestamp;
  dow smallint;
  start_min integer;
  end_min integer;
  schedule_id uuid;
  day operating_days;
  slot operating_time_slots;
  slot_start_min integer;
  slot_end_min integer;
  fits boolean;
begin
  select timezone into tz from facilities where id = p_facility_id;
  tz := coalesce(tz, 'Asia/Kolkata');

  local_start := p_start at time zone tz;
  local_end := p_end at time zone tz;

  if local_end::date <> local_start::date then
    -- Bookings that cross a local calendar day boundary aren't supported yet.
    return false;
  end if;

  dow := extract(dow from local_start);
  start_min := extract(hour from local_start) * 60 + extract(minute from local_start);
  end_min := extract(hour from local_end) * 60 + extract(minute from local_end);

  select id into schedule_id from operating_schedules
    where playing_area_id = p_court_id and scope_type = 'PLAYING_AREA';
  if schedule_id is null then
    select id into schedule_id from operating_schedules
      where facility_id = p_facility_id and scope_type = 'FACILITY';
  end if;
  if schedule_id is null then
    return false;
  end if;

  select * into day from operating_days where operating_days.schedule_id = schedule_id and day_of_week = dow;
  if day.id is null or day.is_closed then
    return false;
  end if;
  if day.is_24_hours then
    return true;
  end if;

  fits := false;
  for slot in select * from operating_time_slots where operating_day_id = day.id
  loop
    slot_start_min := extract(hour from slot.start_time) * 60 + extract(minute from slot.start_time);
    slot_end_min := extract(hour from slot.end_time) * 60 + extract(minute from slot.end_time);
    if slot.crosses_midnight or slot_end_min <= slot_start_min then
      slot_end_min := slot_end_min + 24 * 60;
    end if;
    if start_min >= slot_start_min and end_min <= slot_end_min then
      fits := true;
      exit;
    end if;
  end loop;

  return fits;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- resolve_booking_price: playing-area rule beats sport-level rule; within a
-- scope, a time-windowed rule beats a full-day one; amount is the matched
-- hourly rate × booking duration (every rule in the UI today is PER_HOUR).
-- Returns null when nothing matches — a booking may still be created without
-- a captured price, for staff to fill in manually later.
-- ─────────────────────────────────────────────────────────────────────────
create function resolve_booking_price(
  p_facility_sport_id uuid,
  p_court_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_timezone text
) returns integer
language plpgsql
stable
as $$
declare
  local_start timestamp := p_start at time zone coalesce(p_timezone, 'Asia/Kolkata');
  local_end timestamp := p_end at time zone coalesce(p_timezone, 'Asia/Kolkata');
  dow smallint := extract(dow from local_start);
  is_weekend boolean := dow in (0, 6);
  start_min integer := extract(hour from local_start) * 60 + extract(minute from local_start);
  end_min integer := extract(hour from local_end) * 60 + extract(minute from local_end);
  duration_hours numeric := extract(epoch from (p_end - p_start)) / 3600.0;
  rule pricing_rules;
  rule_start_min integer;
  rule_end_min integer;
begin
  for rule in
    select * from pricing_rules
    where facility_sport_id = p_facility_sport_id
      and is_active
      and (playing_area_id = p_court_id or playing_area_id is null)
      and (day_type = 'ALL_DAYS' or (day_type = 'WEEKENDS') = is_weekend)
    order by (playing_area_id is not null) desc, covers_full_day asc, priority desc
  loop
    if rule.covers_full_day then
      return round(rule.amount_minor * duration_hours);
    end if;
    rule_start_min := extract(hour from rule.start_time) * 60 + extract(minute from rule.start_time);
    rule_end_min := extract(hour from rule.end_time) * 60 + extract(minute from rule.end_time);
    if rule_end_min <= rule_start_min then
      rule_end_min := rule_end_min + 24 * 60;
    end if;
    if start_min >= rule_start_min and end_min <= rule_end_min then
      return round(rule.amount_minor * duration_hours);
    end if;
  end loop;

  return null;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- create_booking: the single write path both clients use. Runs security
-- invoker (default) so bookings_insert_own_or_staff still governs who may
-- call it; validates operating hours server-side (never trust the client to
-- have picked a slot the UI happened to show as available), resolves and
-- captures the price at booking time, and relies on the table's own
-- exclusion constraint to reject a double-booked slot atomically.
-- ─────────────────────────────────────────────────────────────────────────
create function create_booking(
  p_facility_id uuid,
  p_court_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_customer_type text,
  p_member_id uuid,
  p_guest_name text,
  p_guest_phone text,
  p_notes text
) returns bookings
language plpgsql
as $$
declare
  result bookings;
  fac facilities;
  court courts;
  price integer;
begin
  if p_end_time <= p_start_time then
    raise exception 'End time must be after start time.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    raise exception 'facility % does not exist', p_facility_id using errcode = '23503';
  end if;

  select * into court from courts where id = p_court_id and facility_id = p_facility_id;
  if court.id is null then
    raise exception 'court % does not exist for this facility', p_court_id using errcode = '23503';
  end if;

  if not booking_window_fits_operating_hours(p_facility_id, p_court_id, p_start_time, p_end_time) then
    raise exception 'Selected time is outside this court''s operating hours.' using errcode = '23514';
  end if;

  price := resolve_booking_price(court.facility_sport_id, p_court_id, p_start_time, p_end_time, fac.timezone);

  insert into bookings (
    facility_id, court_id, member_id, start_time, end_time, status,
    customer_type, guest_name, guest_phone, amount_minor, currency, notes, created_by
  ) values (
    p_facility_id, p_court_id, p_member_id, p_start_time, p_end_time, 'confirmed',
    coalesce(p_customer_type, 'MEMBER'), p_guest_name, p_guest_phone, price, fac.currency, p_notes, auth.uid()
  ) returning * into result;

  return result;
end;
$$;

grant execute on function create_booking(uuid, uuid, timestamptz, timestamptz, text, uuid, text, text, text) to authenticated;