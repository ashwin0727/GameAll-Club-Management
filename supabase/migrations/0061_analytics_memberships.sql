-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 6: Memberships, sessions, guest release.
--
-- Membership revenue is Finance's (get_revenue_breakdown). Session usage is
-- never revenue — member_allocations counts confirmed MEMBER slot bookings,
-- and unused_capacity = capacity − member_allocations − guest_booked
-- (spec §19). New-membership / by-type / payment-completion figures cover
-- memberships created in the range; active_members and expiring_soon are a
-- current snapshot.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_membership_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null
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
    from get_revenue_breakdown(p_facility_id, p_preset, p_start_date, p_end_date) b;

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
  )
  select
    (select count(*) from memberships where facility_id = p_facility_id and status = 'active')::bigint,
    (select count(*) from new_m)::bigint,
    (select count(*) from memberships
       where facility_id = p_facility_id and status = 'active'
         and end_date >= today and end_date <= today + 30)::bigint,
    coalesce(v_rev, 0),
    (select count(*) from new_m where total_minor > 0 and paid_minor >= total_minor)::bigint,
    (select count(*) from new_m where paid_minor > 0 and paid_minor < total_minor)::bigint,
    (select count(*) from new_m where paid_minor = 0 and total_minor > 0)::bigint,
    (select coalesce(sum(greatest(total_minor - paid_minor, 0)), 0) from new_m)::bigint;
end;
$$;

grant execute on function get_membership_analytics(uuid, text, date, date) to authenticated;


create or replace function get_memberships_by_type(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null
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
  )
  select m.membership_type, m.plan_name, count(*)::bigint, coalesce(sum(m.paid_minor), 0)::bigint
  from m
  group by m.membership_type, m.plan_name
  order by count(*) desc, m.membership_type;
end;
$$;

grant execute on function get_memberships_by_type(uuid, text, date, date) to authenticated;


create or replace function get_membership_session_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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

grant execute on function get_membership_session_analytics(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_guest_release_analytics(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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
    and (p_court_id is null or ms.court_id = p_court_id);

  return query select
    v_released::bigint,
    v_booked::bigint,
    greatest(v_released - v_booked, 0)::bigint,
    v_rev::bigint;
end;
$$;

grant execute on function get_guest_release_analytics(uuid, text, date, date, uuid, uuid) to authenticated;
