-- ═══════════════════════════════════════════════════════════════════════════
-- Fix "column reference \"schedule_id\" is ambiguous" (Postgres 42702) in
-- booking_window_fits_operating_hours (0007_bookings.sql).
--
-- The plpgsql variable `schedule_id` shared its name with
-- operating_days.schedule_id, so `where operating_days.schedule_id =
-- schedule_id` was ambiguous on the right-hand side — Postgres couldn't
-- tell whether that bare identifier meant the column or the variable.
-- Renamed the variable to v_schedule_id throughout; logic is unchanged.
-- Affects both Web and Flutter identically since both call the same RPC.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function booking_window_fits_operating_hours(
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
  v_schedule_id uuid;
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