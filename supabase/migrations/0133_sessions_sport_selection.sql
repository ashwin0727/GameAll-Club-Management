-- ═══════════════════════════════════════════════════════════════════════════
-- Membership Sessions follows the top bar's sport selection.
--
-- The summary cards and the session list could only be asked for the whole facility (or, for the list, one sport).
-- Both now take an optional list of sports: null is All Sports, a list narrows every figure and row to those sports.
-- Everything else is exactly as in 0036.
-- ═══════════════════════════════════════════════════════════════════════════

drop function if exists get_membership_sessions_summary(uuid);
drop function if exists list_membership_sessions_admin(uuid, text, uuid, uuid, text, smallint, integer, integer);

create or replace function get_membership_sessions_summary(p_facility_id uuid, p_facility_sport_ids uuid[] default null)
returns jsonb
language sql
stable
as $$
  with b as (
    select mb.*,
      membership_batch_roster_count(mb.id) as roster,
      (extract(dow from current_date)::smallint = any(mb.days_of_week)
        and not exists (select 1 from membership_batch_blocked_dates x where x.batch_id = mb.id and x.blocked_date = current_date)
      ) as runs_today
    from membership_batches mb
    where mb.facility_id = p_facility_id
      and (p_facility_sport_ids is null or mb.facility_sport_id = any (p_facility_sport_ids))
  )
  select jsonb_build_object(
    'totalSessions', (select count(*) from b),
    'activeSessions', (select count(*) from b where is_active),
    'todaysSessions', (select count(*) from b where is_active and runs_today),
    'guestSlotsReleased', coalesce((
      select sum(s.released_capacity) from membership_sessions s
      where s.facility_id = p_facility_id and s.session_date >= current_date
        and (p_facility_sport_ids is null or s.batch_id in (select id from b))
    ), 0),
    'avgUtilizationPct', coalesce((
      select round(avg(least(1.0, roster::numeric / nullif(capacity, 0))) * 100)
      from b where is_active
    ), 0)
  );
$$;
grant execute on function get_membership_sessions_summary(uuid, uuid[]) to authenticated;

create or replace function list_membership_sessions_admin(
  p_facility_id uuid,
  p_search text default null,
  p_facility_sport_id uuid default null,
  p_facility_sport_ids uuid[] default null,
  p_court_id uuid default null,
  p_status text default null,          -- 'active' | 'paused' | 'full'
  p_day smallint default null,         -- 0..6
  p_limit integer default 10,
  p_offset integer default 0
) returns table (
  batch_id uuid,
  name text,
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  days_of_week smallint[],
  start_time time,
  end_time time,
  capacity integer,
  roster_count integer,
  released_today integer,
  guest_booked_today integer,
  utilization_pct integer,
  status text,
  is_active boolean,
  total_count bigint
)
language sql
stable
as $$
  with base as (
    select
      b.id as batch_id,
      b.name,
      b.court_id,
      c.name as court_name,
      b.facility_sport_id,
      coalesce(fs.custom_sport_name, sp.name) as sport_name,
      b.days_of_week,
      b.start_time,
      b.end_time,
      b.capacity,
      membership_batch_roster_count(b.id) as roster_count,
      coalesce((select s.released_capacity from membership_sessions s where s.batch_id = b.id and s.session_date = current_date), 0) as released_today,
      coalesce((select count(*) from membership_session_bookings mb
        join membership_sessions s on s.id = mb.session_id
        where s.batch_id = b.id and s.session_date = current_date
          and mb.participant_type = 'GUEST' and mb.status = 'CONFIRMED'), 0)::integer as guest_booked_today,
      b.is_active,
      b.created_at
    from membership_batches b
    join courts c on c.id = b.court_id
    join facility_sports fs on fs.id = b.facility_sport_id
    join sports sp on sp.id = fs.sport_id
    where b.facility_id = p_facility_id
      and (p_search is null or b.name ilike '%' || p_search || '%' or c.name ilike '%' || p_search || '%')
      and (p_facility_sport_id is null or b.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or b.facility_sport_id = any (p_facility_sport_ids))
      and (p_court_id is null or b.court_id = p_court_id)
      and (p_day is null or p_day = any(b.days_of_week))
  ),
  scored as (
    select *,
      case when capacity > 0 then least(100, round(roster_count::numeric / capacity * 100))::integer else 0 end as utilization_pct,
      case
        when not is_active then 'paused'
        when roster_count >= capacity then 'full'
        else 'active'
      end as status
    from base
  ),
  filtered as (
    select * from scored where p_status is null or status = p_status
  )
  select
    batch_id, name, court_id, court_name, facility_sport_id, sport_name,
    days_of_week, start_time, end_time, capacity, roster_count, released_today,
    guest_booked_today, utilization_pct, status, is_active,
    count(*) over () as total_count
  from filtered
  order by start_time, name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
$$;
grant execute on function list_membership_sessions_admin(uuid, text, uuid, uuid[], uuid, text, smallint, integer, integer) to authenticated;
