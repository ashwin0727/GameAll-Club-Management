-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 3a: availability primitives.
--
-- The range-aggregate companions to booking_window_fits_operating_hours
-- (0007). Same tables, same precedence (PLAYING_AREA override, else
-- FACILITY), same day math as summary.ts::operatingMinutesForDay. There is
-- no maintenance/blocked model in GameAll, so open time == bookable time.
--
-- Every figure is "minutes", bucketed by local (day-of-week, hour-of-day)
-- so one primitive feeds court/sport utilisation, peak hours AND the
-- demand heatmap. Internal — called only from 0059's RPCs, which do the
-- has_facility_role check.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function analytics_window_cells(
  p_start timestamptz,
  p_end timestamptz,
  p_tz text
) returns table (dow smallint, hour smallint, minutes numeric)
language sql
stable
as $$
  with b as (
    select
      (p_start at time zone coalesce(p_tz, 'Asia/Kolkata')) as ls,
      (p_end   at time zone coalesce(p_tz, 'Asia/Kolkata')) as le
  ),
  hrs as (
    select generate_series(date_trunc('hour', b.ls), b.le - interval '1 microsecond', interval '1 hour') as h,
           b.ls, b.le
    from b
    where b.le > b.ls
  )
  select
    extract(dow  from h)::smallint,
    extract(hour from h)::smallint,
    (extract(epoch from (least(le, h + interval '1 hour') - greatest(ls, h))) / 60.0)::numeric
  from hrs
  where least(le, h + interval '1 hour') > greatest(ls, h);
$$;


create or replace function analytics_court_open_minutes_by_cell(
  p_court_id uuid,
  p_range tstzrange
) returns table (dow smallint, hour smallint, minutes numeric)
language plpgsql
stable
as $$
declare
  v_facility uuid;
  tz text;
  v_schedule uuid;
  start_d date;
  end_d date;
  d date;
  dow_ smallint;
  day_rec operating_days;
  slot operating_time_slots;
  win_start timestamptz;
  win_end timestamptz;
begin
  select c.facility_id into v_facility from courts c where c.id = p_court_id;
  if v_facility is null then return; end if;
  select coalesce(f.timezone, 'Asia/Kolkata') into tz from facilities f where f.id = v_facility;

  select os.id into v_schedule from operating_schedules os
    where os.playing_area_id = p_court_id and os.scope_type = 'PLAYING_AREA';
  if v_schedule is null then
    select os.id into v_schedule from operating_schedules os
      where os.facility_id = v_facility and os.scope_type = 'FACILITY';
  end if;
  if v_schedule is null then return; end if;

  start_d := (lower(p_range) at time zone tz)::date;
  end_d := ((upper(p_range) - interval '1 microsecond') at time zone tz)::date;

  for d in select generate_series(start_d, end_d, interval '1 day')::date loop
    dow_ := extract(dow from d)::smallint;
    select * into day_rec from operating_days od where od.schedule_id = v_schedule and od.day_of_week = dow_;
    if day_rec.id is null or day_rec.is_closed then continue; end if;

    if day_rec.is_24_hours then
      win_start := greatest(d::timestamp at time zone tz, lower(p_range));
      win_end := least((d + 1)::timestamp at time zone tz, upper(p_range));
      if win_end > win_start then
        return query select w.dow, w.hour, w.minutes from analytics_window_cells(win_start, win_end, tz) w;
      end if;
      continue;
    end if;

    for slot in select * from operating_time_slots ots where ots.operating_day_id = day_rec.id loop
      win_start := (d::timestamp + slot.start_time) at time zone tz;
      if slot.crosses_midnight or slot.end_time <= slot.start_time then
        win_end := ((d + 1)::timestamp + slot.end_time) at time zone tz;
      else
        win_end := (d::timestamp + slot.end_time) at time zone tz;
      end if;
      win_start := greatest(win_start, lower(p_range));
      win_end := least(win_end, upper(p_range));
      if win_end > win_start then
        return query select w.dow, w.hour, w.minutes from analytics_window_cells(win_start, win_end, tz) w;
      end if;
    end loop;
  end loop;
end;
$$;


create or replace function analytics_court_booked_minutes_by_cell(
  p_court_id uuid,
  p_range tstzrange
) returns table (dow smallint, hour smallint, minutes numeric)
language plpgsql
stable
as $$
declare
  v_facility uuid;
  tz text;
  rec record;
  win_start timestamptz;
  win_end timestamptz;
begin
  select c.facility_id into v_facility from courts c where c.id = p_court_id;
  if v_facility is null then return; end if;
  select coalesce(f.timezone, 'Asia/Kolkata') into tz from facilities f where f.id = v_facility;

  -- Ad-hoc bookings — any non-cancelled row overlapping the range.
  for rec in
    select b.start_time as s, b.end_time as e
    from bookings b
    where b.court_id = p_court_id
      and b.status <> 'cancelled'
      and tstzrange(b.start_time, b.end_time) && p_range
  loop
    win_start := greatest(rec.s, lower(p_range));
    win_end := least(rec.e, upper(p_range));
    if win_end > win_start then
      return query select w.dow, w.hour, w.minutes from analytics_window_cells(win_start, win_end, tz) w;
    end if;
  end loop;

  -- Membership sessions that were actually used (>= 1 confirmed slot).
  for rec in
    select
      (ms.session_date::timestamp + ms.start_time) at time zone tz as s,
      (ms.session_date::timestamp + ms.end_time)   at time zone tz as e
    from membership_sessions ms
    where ms.court_id = p_court_id
      and exists (
        select 1 from membership_session_bookings msb
        where msb.session_id = ms.id and msb.status = 'CONFIRMED'
      )
  loop
    if not (tstzrange(rec.s, rec.e) && p_range) then continue; end if;
    win_start := greatest(rec.s, lower(p_range));
    win_end := least(rec.e, upper(p_range));
    if win_end > win_start then
      return query select w.dow, w.hour, w.minutes from analytics_window_cells(win_start, win_end, tz) w;
    end if;
  end loop;
end;
$$;
