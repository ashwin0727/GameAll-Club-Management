-- Guest booking report: a booking counts as Completed once its time has ended without being cancelled.
-- Bookings stay 'confirmed' in the table after they finish, so status = 'completed' alone showed 0.
-- Confirmed now means confirmed and still upcoming / in progress; Cancelled is unchanged (status = 'cancelled').

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
      b.end_time,
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
      count(*) filter (where gb.status <> 'cancelled' and (gb.status = 'completed' or gb.end_time <= now())) as completed,
      count(*) filter (where gb.status = 'confirmed' and gb.end_time > now()) as confirmed,
      count(*) filter (where gb.status = 'pending' and gb.end_time > now()) as pending,
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
