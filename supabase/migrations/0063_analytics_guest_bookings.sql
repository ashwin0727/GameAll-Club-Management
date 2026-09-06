-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 7: Guest bookings.
--
-- Ad-hoc guest bookings only (bookings.customer_type = 'GUEST'). Released-
-- seat session guests are in the Membership report. Revenue is collected
-- (paid payments), cash basis. Average booking value and collection rate
-- per spec §22 / §23 — cancelled and unpaid excluded from the divisors.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_guest_booking_analytics(
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
  revenue_minor bigint,
  avg_booking_value_minor bigint,
  collected_minor bigint,
  outstanding_minor bigint,
  collection_rate_pct numeric
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
      and (p_court_id is null or b.court_id = p_court_id)
  ),
  agg as (
    select
      count(*) as total,
      count(*) filter (where status = 'completed') as completed,
      count(*) filter (where status = 'confirmed') as confirmed,
      count(*) filter (where status = 'pending') as pending,
      count(*) filter (where status = 'cancelled') as cancelled,
      coalesce(sum(collected_minor), 0) as collected,
      coalesce(sum(amount_minor) filter (
        where payment_status = 'PAID' and status <> 'cancelled'
      ), 0) as paid_value,
      count(*) filter (where payment_status = 'PAID' and status <> 'cancelled') as paid_count,
      coalesce(sum(greatest(amount_minor - collected_minor, 0)) filter (where status <> 'cancelled'), 0) as outstanding
    from gb
  )
  select
    total::bigint,
    completed::bigint,
    confirmed::bigint,
    pending::bigint,
    cancelled::bigint,
    collected::bigint,
    case when paid_count > 0 then round(paid_value / paid_count)::bigint else 0 end,
    collected::bigint,
    outstanding::bigint,
    case when (collected + outstanding) > 0
      then round((collected::numeric / (collected + outstanding)) * 100, 1)
      else 0 end
  from agg;
end;
$$;

grant execute on function get_guest_booking_analytics(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_guest_bookings_by_sport(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  booking_count bigint,
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
  group by fs.id, coalesce(fs.custom_sport_name, sp.name)
  order by count(gb.facility_sport_id) desc, 2;
end;
$$;

grant execute on function get_guest_bookings_by_sport(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_guest_bookings_by_court(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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
    and (p_court_id is null or c.id = p_court_id)
  group by c.id, c.name, coalesce(fs.custom_sport_name, sp.name)
  order by count(gb.court_id) desc, c.name;
end;
$$;

grant execute on function get_guest_bookings_by_court(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_guest_peak_hours(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  hour smallint,
  booking_count bigint
)
language plpgsql
stable
as $$
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
    and (p_court_id is null or b.court_id = p_court_id)
  group by 1
  order by 1;
end;
$$;

grant execute on function get_guest_peak_hours(uuid, text, date, date, uuid, uuid) to authenticated;
