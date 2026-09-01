-- ═══════════════════════════════════════════════════════════════════════════
-- Membership Sessions dashboard — Phase 9.
--
-- The page is reworked into a dashboard: KPI tiles, a filterable list of
-- recurring "sessions" (membership_batches, relabelled), and a per-session
-- detail panel (Overview / Members / Occurrences / Bookings / Activity).
--
--   • membership_batch_blocked_dates — a date a session is skipped.
--   • block_membership_batch_date / unblock_membership_batch_date
--   • get_or_create_membership_session — rejects a blocked date.
--   • get_membership_sessions_summary — the KPI tiles.
--   • list_membership_sessions_admin — the session list (roster, released,
--     utilisation, status), filterable + paginated.
--   • get_membership_session_detail — the detail panel's Overview.
--   • list_membership_session_occurrences — upcoming dates + status.
--   • list_membership_session_bookings — member + guest bookings.
--   • list_membership_session_activity — derived activity feed.
--   • duplicate_membership_batch — clone a session template.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- Blocked dates
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists membership_batch_blocked_dates (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references membership_batches (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  blocked_date date not null,
  reason text,
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (batch_id, blocked_date)
);
create index if not exists membership_batch_blocked_dates_batch_idx
  on membership_batch_blocked_dates (batch_id, blocked_date);

alter table membership_batch_blocked_dates enable row level security;

drop policy if exists "membership_batch_blocked_dates_select" on membership_batch_blocked_dates;
create policy "membership_batch_blocked_dates_select" on membership_batch_blocked_dates for select
  using (is_facility_member(facility_id));
drop policy if exists "membership_batch_blocked_dates_write" on membership_batch_blocked_dates;
create policy "membership_batch_blocked_dates_write" on membership_batch_blocked_dates for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

create or replace function block_membership_batch_date(p_batch_id uuid, p_date date, p_reason text default null)
returns void
language plpgsql
as $$
declare
  b membership_batches;
begin
  select * into b from membership_batches where id = p_batch_id;
  if b.id is null then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;
  insert into membership_batch_blocked_dates (batch_id, facility_id, blocked_date, reason, created_by)
  values (p_batch_id, b.facility_id, p_date, nullif(trim(p_reason), ''), auth.uid())
  on conflict (batch_id, blocked_date) do update set reason = excluded.reason;
end;
$$;
grant execute on function block_membership_batch_date(uuid, date, text) to authenticated;

create or replace function unblock_membership_batch_date(p_batch_id uuid, p_date date) returns void
language sql
as $$
  delete from membership_batch_blocked_dates where batch_id = p_batch_id and blocked_date = p_date;
$$;
grant execute on function unblock_membership_batch_date(uuid, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_or_create_membership_session — a blocked date can't be materialised.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_or_create_membership_session(p_batch_id uuid, p_session_date date)
returns membership_sessions
language plpgsql
as $$
declare
  batch membership_batches;
  result membership_sessions;
  dow smallint;
begin
  select * into batch from membership_batches where id = p_batch_id;
  if batch.id is null then
    raise exception 'Membership batch not found' using errcode = 'P0002';
  end if;
  if not batch.is_active then
    raise exception 'This membership batch is no longer active.' using errcode = '23514';
  end if;

  dow := extract(dow from p_session_date);
  if not (dow = any(batch.days_of_week)) then
    raise exception 'This date is not a scheduled day for this membership batch.' using errcode = '23514';
  end if;
  if exists (select 1 from membership_batch_blocked_dates where batch_id = p_batch_id and blocked_date = p_session_date) then
    raise exception 'This date is blocked for this session.' using errcode = '23514';
  end if;

  insert into membership_sessions (
    batch_id, facility_id, court_id, facility_sport_id, session_date, start_time, end_time, capacity
  ) values (
    batch.id, batch.facility_id, batch.court_id, batch.facility_sport_id, p_session_date, batch.start_time, batch.end_time, batch.capacity
  )
  on conflict (batch_id, session_date) do update set updated_at = now()
  returning * into result;

  return result;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Shared: roster / released / utilisation for a batch on a given date.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function membership_batch_roster_count(p_batch_id uuid) returns integer
language sql stable as $$
  select count(*)::integer from membership_batch_members where batch_id = p_batch_id;
$$;
grant execute on function membership_batch_roster_count(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_membership_sessions_summary — the KPI tiles.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_membership_sessions_summary(p_facility_id uuid)
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
  )
  select jsonb_build_object(
    'totalSessions', (select count(*) from b),
    'activeSessions', (select count(*) from b where is_active),
    'todaysSessions', (select count(*) from b where is_active and runs_today),
    'guestSlotsReleased', coalesce((
      select sum(s.released_capacity) from membership_sessions s
      where s.facility_id = p_facility_id and s.session_date >= current_date
    ), 0),
    'avgUtilizationPct', coalesce((
      select round(avg(least(1.0, roster::numeric / nullif(capacity, 0))) * 100)
      from b where is_active
    ), 0)
  );
$$;
grant execute on function get_membership_sessions_summary(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_membership_sessions_admin — the session list.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_membership_sessions_admin(
  p_facility_id uuid,
  p_search text default null,
  p_facility_sport_id uuid default null,
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
grant execute on function list_membership_sessions_admin(uuid, text, uuid, uuid, text, smallint, integer, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_membership_session_detail — the detail panel's Overview.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_membership_session_detail(p_batch_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  b membership_batches;
  court_name text;
  sport_name text;
  plan_name text;
  creator text;
  roster integer;
  today_guests integer;
  today_mat_id uuid;
  today_released integer;
  next_date date;
  d date;
begin
  select * into b from membership_batches where id = p_batch_id;
  if b.id is null then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;

  select c.name into court_name from courts c where c.id = b.court_id;
  select coalesce(fs.custom_sport_name, sp.name) into sport_name
    from facility_sports fs join sports sp on sp.id = fs.sport_id where fs.id = b.facility_sport_id;
  if b.plan_id is not null then
    select name into plan_name from membership_plans where id = b.plan_id;
  end if;
  roster := membership_batch_roster_count(b.id);

  select s.id, s.released_capacity into today_mat_id, today_released
    from membership_sessions s where s.batch_id = b.id and s.session_date = current_date;
  select count(*) into today_guests from membership_session_bookings mb
    where mb.session_id = today_mat_id and mb.participant_type = 'GUEST' and mb.status = 'CONFIRMED';

  -- Next scheduled, non-blocked occurrence after today.
  next_date := null;
  for i in 1..14 loop
    d := current_date + i;
    if extract(dow from d)::smallint = any(b.days_of_week)
       and not exists (select 1 from membership_batch_blocked_dates x where x.batch_id = b.id and x.blocked_date = d) then
      next_date := d;
      exit;
    end if;
  end loop;

  return jsonb_build_object(
    'batchId', b.id,
    'facilityId', b.facility_id,
    'name', b.name,
    'courtId', b.court_id,
    'courtName', court_name,
    'facilitySportId', b.facility_sport_id,
    'sportName', sport_name,
    'planName', plan_name,
    'daysOfWeek', b.days_of_week,
    'startTime', b.start_time,
    'endTime', b.end_time,
    'capacity', b.capacity,
    'isActive', b.is_active,
    'createdByName', creator,
    'createdAt', b.created_at,
    'updatedAt', b.updated_at,
    'rosterCount', roster,
    'guestsBookedToday', coalesce(today_guests, 0),
    'releasedToday', coalesce(today_released, 0),
    'availableToRelease', greatest(b.capacity - roster - coalesce(today_released, 0), 0),
    'runsToday', (extract(dow from current_date)::smallint = any(b.days_of_week)
      and not exists (select 1 from membership_batch_blocked_dates x where x.batch_id = b.id and x.blocked_date = current_date)),
    'nextOccurrenceDate', next_date
  );
end;
$$;
grant execute on function get_membership_session_detail(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_membership_session_occurrences — upcoming dates + status.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_membership_session_occurrences(p_batch_id uuid, p_days integer default 30)
returns table (
  occurrence_date date,
  is_blocked boolean,
  block_reason text,
  materialized boolean,
  member_count integer,
  guest_count integer,
  released_capacity integer
)
language sql
stable
as $$
  with b as (select * from membership_batches where id = p_batch_id),
  dates as (
    select (current_date + gs)::date as d
    from generate_series(0, greatest(p_days, 1)) gs
  )
  select
    dates.d,
    exists (select 1 from membership_batch_blocked_dates x where x.batch_id = p_batch_id and x.blocked_date = dates.d),
    (select reason from membership_batch_blocked_dates x where x.batch_id = p_batch_id and x.blocked_date = dates.d),
    (s.id is not null),
    coalesce((select count(*) from membership_session_bookings mb where mb.session_id = s.id and mb.participant_type = 'MEMBER' and mb.status = 'CONFIRMED'), membership_batch_roster_count(p_batch_id))::integer,
    coalesce((select count(*) from membership_session_bookings mb where mb.session_id = s.id and mb.participant_type = 'GUEST' and mb.status = 'CONFIRMED'), 0)::integer,
    coalesce(s.released_capacity, 0)
  from dates
  cross join b
  left join membership_sessions s on s.batch_id = b.id and s.session_date = dates.d
  where extract(dow from dates.d)::smallint = any(b.days_of_week)
  order by dates.d;
$$;
grant execute on function list_membership_session_occurrences(uuid, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_membership_session_bookings — member + guest bookings for a session.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_membership_session_bookings(p_batch_id uuid, p_limit integer default 50)
returns table (
  booking_id uuid,
  session_date date,
  participant_type text,
  participant_name text,
  slot_source text,
  status text,
  amount_minor integer,
  created_at timestamptz
)
language sql
stable
as $$
  select
    mb.id,
    s.session_date,
    mb.participant_type,
    coalesce(mem.full_name, g.name, 'Guest'),
    mb.slot_source,
    mb.status,
    mb.amount_minor,
    mb.created_at
  from membership_session_bookings mb
  join membership_sessions s on s.id = mb.session_id
  left join members mem on mem.id = mb.member_id
  left join guest_players g on g.id = mb.guest_player_id
  where s.batch_id = p_batch_id
  order by mb.created_at desc
  limit greatest(p_limit, 1);
$$;
grant execute on function list_membership_session_bookings(uuid, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_membership_session_activity — derived feed (no event-log table).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_membership_session_activity(p_batch_id uuid, p_limit integer default 30)
returns table (
  kind text,
  actor text,
  detail text,
  at timestamptz
)
language sql
stable
as $$
  select * from (
    select 'created'::text, null::text, 'Session created'::text, b.created_at
    from membership_batches b where b.id = p_batch_id
    union all
    select 'member_added', null, mem.full_name || ' added to the session', bm.created_at
    from membership_batch_members bm join members mem on mem.id = bm.member_id
    where bm.batch_id = p_batch_id
    union all
    select
      case when mb.participant_type = 'GUEST' then 'guest_booking' else 'member_booking' end,
      p.full_name,
      coalesce(mem.full_name, g.name, 'Guest') || ' — ' || to_char(s.session_date, 'DD Mon'),
      mb.created_at
    from membership_session_bookings mb
    join membership_sessions s on s.id = mb.session_id
    left join members mem on mem.id = mb.member_id
    left join guest_players g on g.id = mb.guest_player_id
    left join profiles p on p.id = mb.created_by
    where s.batch_id = p_batch_id
  ) t
  order by at desc
  limit greatest(p_limit, 1);
$$;
grant execute on function list_membership_session_activity(uuid, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- duplicate_membership_batch — clone a session template (no members).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function duplicate_membership_batch(p_batch_id uuid, p_new_name text default null)
returns membership_batches
language plpgsql
as $$
declare
  src membership_batches;
  result membership_batches;
begin
  select * into src from membership_batches where id = p_batch_id;
  if src.id is null then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(src.facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized.' using errcode = '42501';
  end if;

  insert into membership_batches (
    facility_id, plan_id, facility_sport_id, court_id, name,
    days_of_week, start_time, end_time, capacity, is_active
  ) values (
    src.facility_id, src.plan_id, src.facility_sport_id, src.court_id,
    coalesce(nullif(trim(p_new_name), ''), src.name || ' (copy)'),
    src.days_of_week, src.start_time, src.end_time, src.capacity, true
  ) returning * into result;

  return result;
end;
$$;
grant execute on function duplicate_membership_batch(uuid, text) to authenticated;