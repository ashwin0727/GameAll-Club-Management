-- ═══════════════════════════════════════════════════════════════════════════
-- Reports follow the top bar's sport selection.
--
-- Every report function that took one sport (p_facility_sport_id) now also takes a list (p_facility_sport_ids):
-- null is All Sports, a list narrows the figures to those sports. The single-sport argument still works and
-- the two combine (both must hold), so the mobile app, which sends only the single one, is unaffected.
--
-- The Revenue report's totals come from the Finance functions, which got the same argument in 0137; the overview
-- passes it through. The two Memberships report functions had no sport argument at all — they gain the list and
-- narrow by the sport each membership's member is enrolled in (membership_in_sports, from 0137).
--
-- Everything else in each function is exactly as in its latest definition.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── get_booking_analytics (from 0058_analytics_bookings.sql; 1 filter) ──
drop function if exists get_booking_analytics(uuid, text, date, date, uuid, uuid);

create or replace function get_booking_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  total bigint,
  completed bigint,
  confirmed bigint,
  pending bigint,
  cancelled bigint,
  guest_count bigint,
  member_count bigint,
  avg_guest_booking_value_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with b as (
    select bk.status::text as status, bk.customer_type, bk.amount_minor, bk.payment_status
    from bookings bk
    where bk.facility_id = p_facility_id
      and range_ @> bk.start_time
      and (p_facility_sport_id is null or bk.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or bk.facility_sport_id = any (p_facility_sport_ids))
      and (p_court_id is null or bk.court_id = p_court_id)
  )
  select
    count(*)::bigint,
    count(*) filter (where status = 'completed')::bigint,
    count(*) filter (where status = 'confirmed')::bigint,
    count(*) filter (where status = 'pending')::bigint,
    count(*) filter (where status = 'cancelled')::bigint,
    count(*) filter (where customer_type = 'GUEST')::bigint,
    count(*) filter (where customer_type = 'MEMBER')::bigint,
    coalesce(
      round(
        avg(amount_minor) filter (
          where customer_type = 'GUEST' and payment_status = 'PAID' and status <> 'cancelled'
        )
      )::bigint,
      0
    )
  from b;
end;
$$;

grant execute on function get_booking_analytics(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_booking_trend (from 0058_analytics_bookings.sql; 1 filter) ──
drop function if exists get_booking_trend(uuid, text, date, date, uuid, uuid, text);

create or replace function get_booking_trend(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_granularity text default 'daily',
  p_facility_sport_ids uuid[] default null
) returns table (
  bucket_date date,
  total bigint,
  completed bigint,
  cancelled bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  unit text;
  step interval;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if p_granularity not in ('daily', 'weekly', 'monthly') then
    raise exception 'Unknown granularity: %', p_granularity using errcode = '22023';
  end if;
  unit := case p_granularity when 'daily' then 'day' when 'weekly' then 'week' else 'month' end;
  step := case p_granularity when 'daily' then interval '1 day' when 'weekly' then interval '1 week' else interval '1 month' end;

  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with buckets as (
    select generate_series(
      date_trunc(unit, lower(range_) at time zone tz),
      date_trunc(unit, (upper(range_) - interval '1 microsecond') at time zone tz),
      step
    )::date as bucket
  ),
  grouped as (
    select date_trunc(unit, bk.start_time at time zone tz)::date as bucket,
           count(*) as total,
           count(*) filter (where bk.status = 'completed') as completed,
           count(*) filter (where bk.status = 'cancelled') as cancelled
    from bookings bk
    where bk.facility_id = p_facility_id
      and range_ @> bk.start_time
      and (p_facility_sport_id is null or bk.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or bk.facility_sport_id = any (p_facility_sport_ids))
      and (p_court_id is null or bk.court_id = p_court_id)
    group by 1
  )
  select b.bucket,
         coalesce(g.total, 0)::bigint,
         coalesce(g.completed, 0)::bigint,
         coalesce(g.cancelled, 0)::bigint
  from buckets b
  left join grouped g on g.bucket = b.bucket
  order by b.bucket;
end;
$$;

grant execute on function get_booking_trend(uuid, text, date, date, uuid, uuid, text, uuid[]) to authenticated;

-- ── get_bookings_by_sport (from 0067_fix_bookings_by_sport_ambiguous_alias.sql; 1 filter) ──
drop function if exists get_bookings_by_sport(uuid, text, date, date, uuid, uuid);

create or replace function get_bookings_by_sport(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  booking_count bigint
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  select
    fs.id,
    coalesce(fs.custom_sport_name, sp.name),
    count(bk.id)::bigint
  from facility_sports fs
  join sports sp on sp.id = fs.sport_id
  left join bookings bk
    on bk.facility_sport_id = fs.id
    and range_ @> bk.start_time
    and (p_court_id is null or bk.court_id = p_court_id)
  where fs.facility_id = p_facility_id
    and fs.is_active
    and (p_facility_sport_id is null or fs.id = p_facility_sport_id)
      and (p_facility_sport_ids is null or fs.id = any (p_facility_sport_ids))
  group by fs.id, coalesce(fs.custom_sport_name, sp.name)
  order by count(bk.id) desc, coalesce(fs.custom_sport_name, sp.name);
end;
$$;

grant execute on function get_bookings_by_sport(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_booking_source_split (from 0058_analytics_bookings.sql; 1 filter) ──
drop function if exists get_booking_source_split(uuid, text, date, date, uuid, uuid);

create or replace function get_booking_source_split(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  source text,
  booking_count bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with b as (
    select bk.customer_type
    from bookings bk
    where bk.facility_id = p_facility_id
      and range_ @> bk.start_time
      and (p_facility_sport_id is null or bk.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or bk.facility_sport_id = any (p_facility_sport_ids))
      and (p_court_id is null or bk.court_id = p_court_id)
  )
  select s.source, coalesce(count(b.customer_type), 0)::bigint
  from (values ('GUEST'), ('MEMBER')) as s(source)
  left join b on b.customer_type = s.source
  group by s.source
  order by s.source;
end;
$$;

grant execute on function get_booking_source_split(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_overall_utilization (from 0059_analytics_utilization.sql; 1 filter) ──
drop function if exists get_overall_utilization(uuid, text, date, date, uuid, uuid);

create or replace function get_overall_utilization(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  open_minutes bigint,
  booked_minutes bigint,
  utilization_pct numeric
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with per_court as (
    select
      (select coalesce(sum(minutes), 0) from analytics_court_open_minutes_by_cell(c.id, range_)) as open_min,
      (select coalesce(sum(minutes), 0) from analytics_court_booked_minutes_by_cell(c.id, range_)) as booked_min
    from courts c
    where c.facility_id = p_facility_id
      and not c.archived
      and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or c.facility_sport_id = any (p_facility_sport_ids))
      and (p_court_id is null or c.id = p_court_id)
  )
  select
    round(coalesce(sum(open_min), 0))::bigint,
    round(coalesce(sum(booked_min), 0))::bigint,
    case when coalesce(sum(open_min), 0) > 0
      then least(100, round((sum(booked_min) / sum(open_min)) * 100, 1))
      else 0 end
  from per_court;
end;
$$;

grant execute on function get_overall_utilization(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_court_utilization (from 0059_analytics_utilization.sql; 1 filter) ──
drop function if exists get_court_utilization(uuid, text, date, date, uuid, uuid);

create or replace function get_court_utilization(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  open_minutes integer,
  booked_minutes integer,
  utilization_pct numeric
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  select
    c.id,
    c.name,
    c.facility_sport_id,
    coalesce(fs.custom_sport_name, sp.name),
    round(o.open_min)::integer,
    round(b.booked_min)::integer,
    case when o.open_min > 0
      then least(100, round((b.booked_min / o.open_min) * 100, 1))
      else 0 end
  from courts c
  join facility_sports fs on fs.id = c.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  cross join lateral (
    select coalesce(sum(minutes), 0) as open_min from analytics_court_open_minutes_by_cell(c.id, range_)
  ) o
  cross join lateral (
    select coalesce(sum(minutes), 0) as booked_min from analytics_court_booked_minutes_by_cell(c.id, range_)
  ) b
  where c.facility_id = p_facility_id
    and not c.archived
    and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or c.facility_sport_id = any (p_facility_sport_ids))
    and (p_court_id is null or c.id = p_court_id)
  order by c.name;
end;
$$;

grant execute on function get_court_utilization(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_sport_utilization (from 0059_analytics_utilization.sql; 1 filter) ──
drop function if exists get_sport_utilization(uuid, text, date, date, uuid, uuid);

create or replace function get_sport_utilization(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  open_minutes bigint,
  booked_minutes bigint,
  utilization_pct numeric
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with per_court as (
    select
      c.facility_sport_id,
      coalesce(fs.custom_sport_name, sp.name) as sport_name,
      (select coalesce(sum(minutes), 0) from analytics_court_open_minutes_by_cell(c.id, range_)) as open_min,
      (select coalesce(sum(minutes), 0) from analytics_court_booked_minutes_by_cell(c.id, range_)) as booked_min
    from courts c
    join facility_sports fs on fs.id = c.facility_sport_id
    join sports sp on sp.id = fs.sport_id
    where c.facility_id = p_facility_id
      and not c.archived
      and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or c.facility_sport_id = any (p_facility_sport_ids))
      and (p_court_id is null or c.id = p_court_id)
  )
  select
    pc.facility_sport_id,
    pc.sport_name,
    round(sum(pc.open_min))::bigint,
    round(sum(pc.booked_min))::bigint,
    case when sum(pc.open_min) > 0
      then least(100, round((sum(pc.booked_min) / sum(pc.open_min)) * 100, 1))
      else 0 end
  from per_court pc
  group by pc.facility_sport_id, pc.sport_name
  order by pc.sport_name;
end;
$$;

grant execute on function get_sport_utilization(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_peak_hours (from 0059_analytics_utilization.sql; 1 filter) ──
drop function if exists get_peak_hours(uuid, text, date, date, uuid, uuid);

create or replace function get_peak_hours(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  hour smallint,
  open_minutes integer,
  booked_minutes integer,
  demand_pct numeric
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with scope as (
    select c.id
    from courts c
    where c.facility_id = p_facility_id
      and not c.archived
      and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or c.facility_sport_id = any (p_facility_sport_ids))
      and (p_court_id is null or c.id = p_court_id)
  ),
  open_c as (
    select w.hour, sum(w.minutes) as m
    from scope cross join lateral analytics_court_open_minutes_by_cell(scope.id, range_) w
    group by w.hour
  ),
  book_c as (
    select w.hour, sum(w.minutes) as m
    from scope cross join lateral analytics_court_booked_minutes_by_cell(scope.id, range_) w
    group by w.hour
  )
  select
    o.hour,
    round(o.m)::integer,
    round(coalesce(b.m, 0))::integer,
    least(100, round((coalesce(b.m, 0) / o.m) * 100, 1))
  from open_c o
  left join book_c b on b.hour = o.hour
  where o.m > 0
  order by o.hour;
end;
$$;

grant execute on function get_peak_hours(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_demand_heatmap (from 0059_analytics_utilization.sql; 1 filter) ──
drop function if exists get_demand_heatmap(uuid, text, date, date, uuid, uuid);

create or replace function get_demand_heatmap(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  dow smallint,
  hour smallint,
  open_minutes integer,
  booked_minutes integer,
  demand_pct numeric
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with scope as (
    select c.id
    from courts c
    where c.facility_id = p_facility_id
      and not c.archived
      and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or c.facility_sport_id = any (p_facility_sport_ids))
      and (p_court_id is null or c.id = p_court_id)
  ),
  open_c as (
    select w.dow, w.hour, sum(w.minutes) as m
    from scope cross join lateral analytics_court_open_minutes_by_cell(scope.id, range_) w
    group by w.dow, w.hour
  ),
  book_c as (
    select w.dow, w.hour, sum(w.minutes) as m
    from scope cross join lateral analytics_court_booked_minutes_by_cell(scope.id, range_) w
    group by w.dow, w.hour
  )
  select
    o.dow,
    o.hour,
    round(o.m)::integer,
    round(coalesce(b.m, 0))::integer,
    least(100, round((coalesce(b.m, 0) / o.m) * 100, 1))
  from open_c o
  left join book_c b on b.dow = o.dow and b.hour = o.hour
  where o.m > 0
  order by o.dow, o.hour;
end;
$$;

grant execute on function get_demand_heatmap(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_revenue_by_sport (from 0060_analytics_revenue.sql; 1 filter) ──
drop function if exists get_revenue_by_sport(uuid, text, date, date, uuid, uuid);

create or replace function get_revenue_by_sport(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  revenue_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with rev as (
    select
      coalesce(bc.facility_sport_id, ms.facility_sport_id) as fs_id,
      (p.amount_inr * 100)::bigint as amount_minor
    from payments p
    left join bookings b on b.id = p.booking_id
    left join courts bc on bc.id = b.court_id
    left join membership_session_bookings msb on msb.id = p.membership_session_booking_id
    left join membership_sessions ms on ms.id = msb.session_id
    where p.facility_id = p_facility_id
      and p.status = 'paid'
      and range_ @> coalesce(p.paid_at, p.created_at)
      and coalesce(bc.facility_sport_id, ms.facility_sport_id) is not null
      and (p_court_id is null or coalesce(b.court_id, ms.court_id) = p_court_id)
  )
  select
    fs.id,
    coalesce(fs.custom_sport_name, sp.name),
    coalesce(sum(rev.amount_minor), 0)::bigint
  from facility_sports fs
  join sports sp on sp.id = fs.sport_id
  left join rev on rev.fs_id = fs.id
  where fs.facility_id = p_facility_id
    and fs.is_active
    and (p_facility_sport_id is null or fs.id = p_facility_sport_id)
      and (p_facility_sport_ids is null or fs.id = any (p_facility_sport_ids))
  group by fs.id, coalesce(fs.custom_sport_name, sp.name)
  order by coalesce(sum(rev.amount_minor), 0) desc, 2;
end;
$$;

grant execute on function get_revenue_by_sport(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_revenue_by_court (from 0060_analytics_revenue.sql; 1 filter) ──
drop function if exists get_revenue_by_court(uuid, text, date, date, uuid, uuid);

create or replace function get_revenue_by_court(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  revenue_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with rev as (
    select
      coalesce(b.court_id, ms.court_id) as court_id,
      (p.amount_inr * 100)::bigint as amount_minor
    from payments p
    left join bookings b on b.id = p.booking_id
    left join membership_session_bookings msb on msb.id = p.membership_session_booking_id
    left join membership_sessions ms on ms.id = msb.session_id
    where p.facility_id = p_facility_id
      and p.status = 'paid'
      and range_ @> coalesce(p.paid_at, p.created_at)
      and coalesce(b.court_id, ms.court_id) is not null
  )
  select
    c.id,
    c.name,
    c.facility_sport_id,
    coalesce(fs.custom_sport_name, sp.name),
    coalesce(sum(rev.amount_minor), 0)::bigint
  from courts c
  join facility_sports fs on fs.id = c.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  left join rev on rev.court_id = c.id
  where c.facility_id = p_facility_id
    and not c.archived
    and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or c.facility_sport_id = any (p_facility_sport_ids))
    and (p_court_id is null or c.id = p_court_id)
  group by c.id, c.name, c.facility_sport_id, coalesce(fs.custom_sport_name, sp.name)
  order by coalesce(sum(rev.amount_minor), 0) desc, c.name;
end;
$$;

grant execute on function get_revenue_by_court(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_membership_session_analytics (from 0061_analytics_memberships.sql; 1 filter) ──
drop function if exists get_membership_session_analytics(uuid, text, date, date, uuid, uuid);

create or replace function get_membership_session_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  session_count bigint,
  total_capacity bigint,
  member_allocations bigint,
  guest_released bigint,
  guest_booked bigint,
  remaining_released bigint,
  unused_capacity bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  start_d date;
  end_d date;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  start_d := (lower(range_) at time zone tz)::date;
  end_d := ((upper(range_) - interval '1 microsecond') at time zone tz)::date;

  return query
  with s as (
    select
      ms.capacity,
      ms.released_capacity,
      (select count(*) from membership_session_bookings b
         where b.session_id = ms.id and b.participant_type = 'MEMBER' and b.status = 'CONFIRMED') as member_cnt,
      (select count(*) from membership_session_bookings b
         where b.session_id = ms.id and b.participant_type = 'GUEST' and b.status = 'CONFIRMED') as guest_cnt
    from membership_sessions ms
    where ms.facility_id = p_facility_id
      and ms.session_date >= start_d
      and ms.session_date <= end_d
      and (p_facility_sport_id is null or ms.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or ms.facility_sport_id = any (p_facility_sport_ids))
      and (p_court_id is null or ms.court_id = p_court_id)
  )
  select
    count(*)::bigint,
    coalesce(sum(capacity), 0)::bigint,
    coalesce(sum(member_cnt), 0)::bigint,
    coalesce(sum(released_capacity), 0)::bigint,
    coalesce(sum(guest_cnt), 0)::bigint,
    coalesce(sum(released_capacity) - sum(guest_cnt), 0)::bigint,
    coalesce(sum(capacity) - sum(member_cnt) - sum(guest_cnt), 0)::bigint
  from s;
end;
$$;

grant execute on function get_membership_session_analytics(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_guest_release_analytics (from 0061_analytics_memberships.sql; 2 filters) ──
drop function if exists get_guest_release_analytics(uuid, text, date, date, uuid, uuid);

create or replace function get_guest_release_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  released bigint,
  booked bigint,
  remaining bigint,
  revenue_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  start_d date;
  end_d date;
  v_released bigint;
  v_booked bigint;
  v_rev bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  start_d := (lower(range_) at time zone tz)::date;
  end_d := ((upper(range_) - interval '1 microsecond') at time zone tz)::date;

  select
    coalesce(sum(ms.released_capacity), 0),
    coalesce(sum((
      select count(*) from membership_session_bookings b
      where b.session_id = ms.id and b.participant_type = 'GUEST' and b.status = 'CONFIRMED'
    )), 0)
  into v_released, v_booked
  from membership_sessions ms
  where ms.facility_id = p_facility_id
    and ms.session_date >= start_d
    and ms.session_date <= end_d
    and (p_facility_sport_id is null or ms.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or ms.facility_sport_id = any (p_facility_sport_ids))
    and (p_court_id is null or ms.court_id = p_court_id);

  select coalesce(sum(p.amount_inr), 0) * 100
  into v_rev
  from payments p
  join membership_session_bookings msb on msb.id = p.membership_session_booking_id
  join membership_sessions ms on ms.id = msb.session_id
  where p.facility_id = p_facility_id
    and p.status = 'paid'
    and range_ @> coalesce(p.paid_at, p.created_at)
    and (p_facility_sport_id is null or ms.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or ms.facility_sport_id = any (p_facility_sport_ids))
    and (p_court_id is null or ms.court_id = p_court_id);

  return query select
    v_released::bigint,
    v_booked::bigint,
    greatest(v_released - v_booked, 0)::bigint,
    v_rev::bigint;
end;
$$;

grant execute on function get_guest_release_analytics(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_guest_booking_analytics (from 0066_fix_guest_analytics_ambiguous_columns.sql; 1 filter) ──
drop function if exists get_guest_booking_analytics(uuid, text, date, date, uuid, uuid);

create or replace function get_guest_booking_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  total bigint,
  completed bigint,
  confirmed bigint,
  pending bigint,
  cancelled bigint,
  revenue_minor bigint,
  avg_booking_value_minor bigint,
  collected_minor bigint,
  outstanding_minor bigint,
  collection_rate_pct numeric
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with gb as (
    select
      b.id,
      b.status::text as status,
      coalesce(b.amount_minor, 0) as amount_minor,
      b.payment_status,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'
      ), 0)::bigint as collected_minor
    from bookings b
    where b.facility_id = p_facility_id
      and b.customer_type = 'GUEST'
      and range_ @> b.start_time
      and (p_facility_sport_id is null or b.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or b.facility_sport_id = any (p_facility_sport_ids))
      and (p_court_id is null or b.court_id = p_court_id)
  ),
  agg as (
    select
      count(*) as total,
      count(*) filter (where gb.status = 'completed') as completed,
      count(*) filter (where gb.status = 'confirmed') as confirmed,
      count(*) filter (where gb.status = 'pending') as pending,
      count(*) filter (where gb.status = 'cancelled') as cancelled,
      coalesce(sum(gb.collected_minor), 0) as collected,
      coalesce(sum(gb.amount_minor) filter (
        where gb.payment_status = 'PAID' and gb.status <> 'cancelled'
      ), 0) as paid_value,
      count(*) filter (where gb.payment_status = 'PAID' and gb.status <> 'cancelled') as paid_count,
      coalesce(sum(greatest(gb.amount_minor - gb.collected_minor, 0)) filter (where gb.status <> 'cancelled'), 0) as outstanding
    from gb
  )
  select
    agg.total::bigint,
    agg.completed::bigint,
    agg.confirmed::bigint,
    agg.pending::bigint,
    agg.cancelled::bigint,
    agg.collected::bigint,
    case when agg.paid_count > 0 then round(agg.paid_value / agg.paid_count)::bigint else 0 end,
    agg.collected::bigint,
    agg.outstanding::bigint,
    case when (agg.collected + agg.outstanding) > 0
      then round((agg.collected::numeric / (agg.collected + agg.outstanding)) * 100, 1)
      else 0 end
  from agg;
end;
$$;

grant execute on function get_guest_booking_analytics(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_guest_bookings_by_sport (from 0066_fix_guest_analytics_ambiguous_columns.sql; 1 filter) ──
drop function if exists get_guest_bookings_by_sport(uuid, text, date, date, uuid, uuid);

create or replace function get_guest_bookings_by_sport(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  booking_count bigint,
  revenue_minor bigint
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with gb as (
    select
      b.facility_sport_id,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'
      ), 0)::bigint as collected_minor
    from bookings b
    where b.facility_id = p_facility_id
      and b.customer_type = 'GUEST'
      and range_ @> b.start_time
      and (p_court_id is null or b.court_id = p_court_id)
  )
  select
    fs.id,
    coalesce(fs.custom_sport_name, sp.name),
    count(gb.facility_sport_id)::bigint,
    coalesce(sum(gb.collected_minor), 0)::bigint
  from facility_sports fs
  join sports sp on sp.id = fs.sport_id
  left join gb on gb.facility_sport_id = fs.id
  where fs.facility_id = p_facility_id
    and fs.is_active
    and (p_facility_sport_id is null or fs.id = p_facility_sport_id)
      and (p_facility_sport_ids is null or fs.id = any (p_facility_sport_ids))
  group by fs.id, coalesce(fs.custom_sport_name, sp.name)
  order by count(gb.facility_sport_id) desc, 2;
end;
$$;

grant execute on function get_guest_bookings_by_sport(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_guest_bookings_by_court (from 0066_fix_guest_analytics_ambiguous_columns.sql; 1 filter) ──
drop function if exists get_guest_bookings_by_court(uuid, text, date, date, uuid, uuid);

create or replace function get_guest_bookings_by_court(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  court_id uuid,
  court_name text,
  sport_name text,
  booking_count bigint,
  revenue_minor bigint
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with gb as (
    select
      b.court_id,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'
      ), 0)::bigint as collected_minor
    from bookings b
    where b.facility_id = p_facility_id
      and b.customer_type = 'GUEST'
      and range_ @> b.start_time
  )
  select
    c.id,
    c.name,
    coalesce(fs.custom_sport_name, sp.name),
    count(gb.court_id)::bigint,
    coalesce(sum(gb.collected_minor), 0)::bigint
  from courts c
  join facility_sports fs on fs.id = c.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  left join gb on gb.court_id = c.id
  where c.facility_id = p_facility_id
    and not c.archived
    and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or c.facility_sport_id = any (p_facility_sport_ids))
    and (p_court_id is null or c.id = p_court_id)
  group by c.id, c.name, coalesce(fs.custom_sport_name, sp.name)
  order by count(gb.court_id) desc, c.name;
end;
$$;

grant execute on function get_guest_bookings_by_court(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_guest_peak_hours (from 0066_fix_guest_analytics_ambiguous_columns.sql; 1 filter) ──
drop function if exists get_guest_peak_hours(uuid, text, date, date, uuid, uuid);

create or replace function get_guest_peak_hours(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  hour smallint,
  booking_count bigint
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  range_ tstzrange;
  tz text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  select
    extract(hour from b.start_time at time zone tz)::smallint as hour,
    count(*)::bigint
  from bookings b
  where b.facility_id = p_facility_id
    and b.customer_type = 'GUEST'
    and b.status <> 'cancelled'
    and range_ @> b.start_time
    and (p_facility_sport_id is null or b.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or b.facility_sport_id = any (p_facility_sport_ids))
    and (p_court_id is null or b.court_id = p_court_id)
  group by 1
  order by 1;
end;
$$;

grant execute on function get_guest_peak_hours(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_analytics_overview (from 0062_analytics_overview.sql) ──
drop function if exists get_analytics_overview(uuid, text, date, date, uuid, uuid);

create or replace function get_analytics_overview(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  gross_revenue_minor bigint,
  booking_revenue_minor bigint,
  membership_revenue_minor bigint,
  expenses_minor bigint,
  net_revenue_minor bigint,
  outstanding_minor bigint,
  total_bookings bigint,
  completed_bookings bigint,
  cancelled_bookings bigint,
  overall_utilization_pct numeric
)
language plpgsql
stable
as $$
declare
  v_gross bigint;
  v_exp bigint;
  v_net bigint;
  v_out bigint;
  v_membership bigint;
  v_member_book bigint;
  v_guest_book bigint;
  v_total bigint;
  v_completed bigint;
  v_cancelled bigint;
  v_util numeric;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  select s.gross_revenue_minor, s.expenses_minor, s.net_revenue_minor, s.outstanding_minor
    into v_gross, v_exp, v_net, v_out
    from get_finance_summary(p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_ids) s;

  select b.membership_revenue_minor, b.member_booking_revenue_minor, b.guest_booking_revenue_minor
    into v_membership, v_member_book, v_guest_book
    from get_revenue_breakdown(p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_ids) b;

  select a.total, a.completed, a.cancelled
    into v_total, v_completed, v_cancelled
    from get_booking_analytics(
      p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id, p_facility_sport_ids
    ) a;

  select u.utilization_pct
    into v_util
    from get_overall_utilization(
      p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id, p_facility_sport_ids
    ) u;

  return query select
    coalesce(v_gross, 0),
    (coalesce(v_member_book, 0) + coalesce(v_guest_book, 0))::bigint,
    coalesce(v_membership, 0),
    coalesce(v_exp, 0),
    coalesce(v_net, 0),
    coalesce(v_out, 0),
    coalesce(v_total, 0),
    coalesce(v_completed, 0),
    coalesce(v_cancelled, 0),
    coalesce(v_util, 0);
end;
$$;

grant execute on function get_analytics_overview(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

-- ── get_membership_analytics (from 0061_analytics_memberships.sql) ──
drop function if exists get_membership_analytics(uuid, text, date, date);

create or replace function get_membership_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  active_members bigint,
  new_memberships bigint,
  expiring_soon bigint,
  membership_revenue_minor bigint,
  paid_count bigint,
  partially_paid_count bigint,
  pending_count bigint,
  outstanding_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  today date;
  v_rev bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;
  today := (now() at time zone tz)::date;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  select b.membership_revenue_minor into v_rev
    from get_revenue_breakdown(p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_ids) b;

  return query
  with new_m as (
    select
      mm.id,
      (coalesce(mm.total_amount_inr, mm.membership_fee_inr, mp.price_inr, 0) * 100)::bigint as total_minor,
      (coalesce(
        (select sum(pp.amount_inr) from payments pp where pp.membership_id = mm.id and pp.status = 'paid'),
        0
      ) * 100)::bigint as paid_minor
    from memberships mm
    left join membership_plans mp on mp.id = mm.plan_id
    where mm.facility_id = p_facility_id
      and range_ @> mm.created_at
      and membership_in_sports(mm.id, p_facility_sport_ids)
  )
  select
    (select count(*) from memberships where facility_id = p_facility_id and status = 'active' and membership_in_sports(memberships.id, p_facility_sport_ids))::bigint,
    (select count(*) from new_m)::bigint,
    (select count(*) from memberships
       where facility_id = p_facility_id and status = 'active'
         and end_date >= today and end_date <= today + 30
         and membership_in_sports(memberships.id, p_facility_sport_ids))::bigint,
    coalesce(v_rev, 0),
    (select count(*) from new_m where total_minor > 0 and paid_minor >= total_minor)::bigint,
    (select count(*) from new_m where paid_minor > 0 and paid_minor < total_minor)::bigint,
    (select count(*) from new_m where paid_minor = 0 and total_minor > 0)::bigint,
    (select coalesce(sum(greatest(total_minor - paid_minor, 0)), 0) from new_m)::bigint;
end;
$$;

grant execute on function get_membership_analytics(uuid, text, date, date, uuid[]) to authenticated;

-- ── get_memberships_by_type (from 0061_analytics_memberships.sql) ──
drop function if exists get_memberships_by_type(uuid, text, date, date);

create or replace function get_memberships_by_type(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  membership_type text,
  plan_name text,
  count bigint,
  revenue_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with m as (
    select
      mm.membership_type,
      coalesce(mp.name, '—') as plan_name,
      (coalesce(
        (select sum(pp.amount_inr) from payments pp where pp.membership_id = mm.id and pp.status = 'paid'),
        0
      ) * 100)::bigint as paid_minor
    from memberships mm
    left join membership_plans mp on mp.id = mm.plan_id
    where mm.facility_id = p_facility_id
      and range_ @> mm.created_at
      and membership_in_sports(mm.id, p_facility_sport_ids)
  )
  select m.membership_type, m.plan_name, count(*)::bigint, coalesce(sum(m.paid_minor), 0)::bigint
  from m
  group by m.membership_type, m.plan_name
  order by count(*) desc, m.membership_type;
end;
$$;

grant execute on function get_memberships_by_type(uuid, text, date, date, uuid[]) to authenticated;

