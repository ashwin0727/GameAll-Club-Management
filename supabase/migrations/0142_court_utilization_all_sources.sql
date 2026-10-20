-- ═══════════════════════════════════════════════════════════════════════════
-- Court Utilization counts every use of a court: guest bookings, membership time, and coaching.
--
-- All five utilization reports (by court, by sport, overall, peak hours, demand heatmap) get their "booked" time from one
-- function, analytics_court_booked_minutes_by_cell. It counted
--     * court bookings (guest and member, anything not cancelled), and
--     * membership sessions that had at least one confirmed slot booking
-- so a membership batch that holds a court every morning counted only on days someone booked a slot in it, and coaching
-- sessions were not counted at all.
--
-- It now counts the court as in use when any of these holds it:
--     1. a court booking that is not cancelled                          (guest and member bookings)
--     2. a membership batch — every day it runs inside its dates, except its blocked dates — plus any membership session
--        that was used (kept, so a one-off session is not lost)
--     3. a coaching session that is not cancelled
-- Time is merged per court before it is counted, so a guest booking inside a membership slot, or two things on the same
-- hour, count once — utilization never exceeds the time the court actually has.
--
-- Same name, arguments and result columns as 0057, so every caller (and the report pages) is unchanged.
-- ═══════════════════════════════════════════════════════════════════════════

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
begin
  select c.facility_id into v_facility from courts c where c.id = p_court_id;
  if v_facility is null then return; end if;
  select coalesce(f.timezone, 'Asia/Kolkata') into tz from facilities f where f.id = v_facility;

  for rec in
    with raw as (
      -- 1. court bookings
      select b.start_time as s, b.end_time as e
        from bookings b
       where b.court_id = p_court_id and b.status <> 'cancelled'

      union all
      -- 2a. membership batches: each day a batch runs, inside its window and not on a blocked date
      select (d.d::date::timestamp + mb.start_time) at time zone tz,
             (d.d::date::timestamp + mb.end_time) at time zone tz
        from membership_batches mb
       cross join generate_series(
              ((lower(p_range) at time zone tz)::date)::timestamp,
              ((upper(p_range) at time zone tz)::date)::timestamp,
              interval '1 day') d(d)
       where mb.court_id = p_court_id
         and mb.status in ('ACTIVE', 'EXPIRED')
         and extract(dow from d.d)::smallint = any (mb.days_of_week)
         and d.d::date >= mb.start_date
         and (mb.end_date is null or d.d::date <= mb.end_date)
         and not exists (
               select 1 from membership_batch_blocked_dates x
                where x.batch_id = mb.id and x.blocked_date = d.d::date)

      union all
      -- 2b. membership sessions that were used (at least one confirmed slot)
      select (ms.session_date::timestamp + ms.start_time) at time zone tz,
             (ms.session_date::timestamp + ms.end_time) at time zone tz
        from membership_sessions ms
       where ms.court_id = p_court_id
         and exists (select 1 from membership_session_bookings msb where msb.session_id = ms.id and msb.status = 'CONFIRMED')

      union all
      -- 3. coaching sessions
      select cs.start_at, cs.end_at
        from coaching_sessions cs
       where cs.court_id = p_court_id and cs.status <> 'CANCELLED'
    ),
    clipped as (
      select greatest(r.s, lower(p_range)) as s, least(r.e, upper(p_range)) as e
        from raw r
       where r.s < upper(p_range) and r.e > lower(p_range)
    ),
    good as (select s, e from clipped where e > s),
    ordered as (
      select s, e,
             max(e) over (order by s, e rows between unbounded preceding and 1 preceding) as prev_max
        from good
    ),
    grp as (
      select s, e,
             sum(case when prev_max is null or s > prev_max then 1 else 0 end) over (order by s, e) as g
        from ordered
    )
    select min(s) as s, max(e) as e from grp group by g
  loop
    return query select w.dow, w.hour, w.minutes from analytics_window_cells(rec.s, rec.e, tz) w;
  end loop;
end;
$$;
