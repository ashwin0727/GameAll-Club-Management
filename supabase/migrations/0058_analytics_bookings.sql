-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 2: Bookings.
--
-- Four read-only aggregates over `bookings` (the authoritative record — this
-- never decides what a booking's status or customer type is, it counts what
-- is already there). Same parameter shape as every analytics RPC:
--   p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id,
--   p_court_id  [, p_granularity]
-- Dates resolve through resolve_finance_date_range so "This Month" means the
-- same window as Finance. Bookings are dated by start_time.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_booking_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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

grant execute on function get_booking_analytics(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_booking_trend(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_granularity text default 'daily'
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

grant execute on function get_booking_trend(uuid, text, date, date, uuid, uuid, text) to authenticated;


create or replace function get_bookings_by_sport(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
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
  select
    fs.id,
    coalesce(fs.custom_sport_name, sp.name) as sport_name,
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
  group by fs.id, sport_name
  order by count(bk.id) desc, sport_name;
end;
$$;

grant execute on function get_bookings_by_sport(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_booking_source_split(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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
      and (p_court_id is null or bk.court_id = p_court_id)
  )
  select s.source, coalesce(count(b.customer_type), 0)::bigint
  from (values ('GUEST'), ('MEMBER')) as s(source)
  left join b on b.customer_type = s.source
  group by s.source
  order by s.source;
end;
$$;

grant execute on function get_booking_source_split(uuid, text, date, date, uuid, uuid) to authenticated;
