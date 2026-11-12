-- Operating Hours redesign: holidays / special closures, a daily break, "bookings outside hours" and sport-wise hours.
--
--   * facility_closures                  dates the venue is closed (a holiday, maintenance, an event) with a name
--   * facilities.allow_bookings_outside_hours   staff (owner / manager / staff) may create bookings outside the working hours
--   * facilities.operating_break_start / _end   a fixed daily break inside the working hours (stored here so it can be shown again;
--                                              the schedule itself carries it as two time slots, which booking checks already understand)
--   * facilities.sport_wise_hours        each sport has its own hours (stored as per-court schedules, which already override the venue's)
--
-- Every booking path asks booking_window_fits_operating_hours(), so a closure date and the staff override are enforced in that one place.

-- ── facility settings ────────────────────────────────────────────────────
alter table facilities
  add column if not exists allow_bookings_outside_hours boolean not null default false,
  add column if not exists operating_break_start time,
  add column if not exists operating_break_end time,
  add column if not exists sport_wise_hours boolean not null default false;

-- Existing venues keep today's behaviour (strict hours); a venue set up from now on starts with the owner's choice switched on.
alter table facilities alter column allow_bookings_outside_hours set default true;

alter table facilities drop constraint if exists facilities_break_pair_chk;
alter table facilities add constraint facilities_break_pair_chk
  check ((operating_break_start is null) = (operating_break_end is null)
         and (operating_break_start is null or operating_break_start <> operating_break_end));

-- ── closures ─────────────────────────────────────────────────────────────
create table if not exists facility_closures (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  closure_date date not null,
  name text not null check (char_length(btrim(name)) between 2 and 60),
  created_at timestamptz not null default now(),
  unique (facility_id, closure_date)
);
create index if not exists facility_closures_facility_date_idx on facility_closures (facility_id, closure_date);

alter table facility_closures enable row level security;

drop policy if exists "facility_closures_select_members" on facility_closures;
create policy "facility_closures_select_members" on facility_closures for select
  using (is_facility_member(facility_id));
drop policy if exists "facility_closures_write_managers" on facility_closures;
create policy "facility_closures_write_managers" on facility_closures for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

-- ── the one place that decides "is the venue open then" ─────────────────
-- Same rules as 0010, plus: a closure date is closed, and staff may go outside the hours when the owner allows it.
-- Security definer (read-only): it must see closures and the setting whoever is asking, including a visitor on the booking page.
create or replace function booking_window_fits_operating_hours(
  p_facility_id uuid,
  p_court_id uuid,
  p_start timestamptz,
  p_end timestamptz
) returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  tz text;
  allow_outside boolean;
  local_start timestamp;
  local_end timestamp;
  dow smallint;
  start_min integer;
  end_min integer;
  v_schedule_id uuid;
  day operating_days;
  slot operating_time_slots;
  slot_start_min integer;
  slot_end_min integer;
  fits boolean;
begin
  select timezone, allow_bookings_outside_hours into tz, allow_outside from facilities where id = p_facility_id;
  tz := coalesce(tz, 'Asia/Kolkata');

  local_start := p_start at time zone tz;
  local_end := p_end at time zone tz;

  if local_end::date <> local_start::date then
    -- Bookings that cross a local calendar day boundary aren't supported yet.
    return false;
  end if;

  -- the owner lets their own team book outside the working hours (and on closure dates)
  if coalesce(allow_outside, false) and auth.uid() is not null and is_facility_member(p_facility_id) then
    return true;
  end if;

  -- a holiday / special closure
  if exists (select 1 from facility_closures c where c.facility_id = p_facility_id and c.closure_date = local_start::date) then
    return false;
  end if;

  dow := extract(dow from local_start);
  start_min := extract(hour from local_start) * 60 + extract(minute from local_start);
  end_min := extract(hour from local_end) * 60 + extract(minute from local_end);

  select id into v_schedule_id from operating_schedules
    where playing_area_id = p_court_id and scope_type = 'PLAYING_AREA';
  if v_schedule_id is null then
    select id into v_schedule_id from operating_schedules
      where facility_id = p_facility_id and scope_type = 'FACILITY';
  end if;
  if v_schedule_id is null then
    return false;
  end if;

  select * into day from operating_days where operating_days.schedule_id = v_schedule_id and day_of_week = dow;
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
