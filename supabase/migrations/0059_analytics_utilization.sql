-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 3b: Court Utilization.
--
-- booked ÷ open, per the availability primitives in 0057. "open" is the
-- facility's operating hours (no maintenance model); "booked" is
-- non-cancelled bookings + membership sessions with >=1 confirmed slot,
-- clipped to the selected range. Utilisation is capped at 100% (a booking
-- outside operating hours still counts as booked time — matches
-- summary.ts::computeUtilizationPercent).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_court_utilization(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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
    and (p_court_id is null or c.id = p_court_id)
  order by c.name;
end;
$$;

grant execute on function get_court_utilization(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_sport_utilization(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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

grant execute on function get_sport_utilization(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_overall_utilization(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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

grant execute on function get_overall_utilization(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_peak_hours(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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

grant execute on function get_peak_hours(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_demand_heatmap(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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

grant execute on function get_demand_heatmap(uuid, text, date, date, uuid, uuid) to authenticated;
