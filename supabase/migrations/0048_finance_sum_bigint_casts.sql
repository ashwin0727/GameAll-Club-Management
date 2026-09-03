-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: 42804 "Returned type numeric does not match expected type bigint".
--
-- finance_transactions_view exposes amount_minor as (p.amount_inr * 100)::bigint.
-- In PostgreSQL, sum(bigint) returns NUMERIC — the accumulator widens to
-- avoid overflow. sum(integer) returns bigint, which is why every other
-- aggregate in this schema is fine and only the two that sum the *view*
-- are not.
--
-- Both declared bigint OUT columns and returned numeric ones, which
-- PostgreSQL only discovers when the function runs. Nothing catches it at
-- creation time, so the Finance dashboard failed on load rather than the
-- migration failing on apply.
--
-- Return shapes are unchanged here — only the casts — so these can be
-- replaced in place.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_revenue_breakdown(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null
) returns table (
  membership_revenue_minor bigint,
  member_booking_revenue_minor bigint,
  guest_booking_revenue_minor bigint,
  refunds_minor bigint,
  net_revenue_minor bigint,
  membership_included_usage_count bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  refunded bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  select coalesce(sum(r.amount_minor), 0)::bigint into refunded
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at;

  return query
  with classified as (
    select v.source_type, v.amount_minor
    from finance_transactions_view v
    where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
  )
  select
    coalesce(sum(amount_minor) filter (where source_type = 'MEMBERSHIP'), 0)::bigint,
    coalesce(sum(amount_minor) filter (where source_type = 'MEMBER_BOOKING'), 0)::bigint,
    coalesce(sum(amount_minor) filter (where source_type = 'GUEST_BOOKING'), 0)::bigint,
    refunded::bigint,
    (coalesce(sum(amount_minor), 0) - refunded)::bigint,
    (
      select count(*) from membership_session_bookings msb
      where msb.facility_id = p_facility_id and msb.participant_type = 'MEMBER'
        and msb.status = 'CONFIRMED' and range_ @> msb.created_at
    )::bigint
  from classified;
end;
$$;

grant execute on function get_revenue_breakdown(uuid, text, date, date) to authenticated;


-- The same fault, one column over: bucket_date is a date, so this one would
-- have reported column 2 rather than column 1.
create or replace function get_revenue_trend(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_granularity text default 'daily'
) returns table (
  bucket_date date,
  gross_minor bigint,
  refund_minor bigint,
  net_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  trunc_unit text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if p_granularity not in ('daily', 'weekly', 'monthly') then
    raise exception 'Unknown granularity: %', p_granularity using errcode = '22023';
  end if;
  trunc_unit := case p_granularity when 'daily' then 'day' when 'weekly' then 'week' else 'month' end;

  select timezone into tz from facilities where id = p_facility_id;
  tz := coalesce(tz, 'Asia/Kolkata');
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with gross as (
    select date_trunc(trunc_unit, v.effective_at at time zone tz)::date as bucket,
           coalesce(sum(v.amount_minor), 0)::bigint as amount
    from finance_transactions_view v
    where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
    group by 1
  ),
  refund as (
    select date_trunc(trunc_unit, r.processed_at at time zone tz)::date as bucket,
           coalesce(sum(r.amount_minor), 0)::bigint as amount
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at
    group by 1
  ),
  buckets as (
    select bucket from gross union select bucket from refund
  )
  select
    b.bucket,
    coalesce(g.amount, 0)::bigint,
    coalesce(rf.amount, 0)::bigint,
    (coalesce(g.amount, 0) - coalesce(rf.amount, 0))::bigint
  from buckets b
  left join gross g on g.bucket = b.bucket
  left join refund rf on rf.bucket = b.bucket
  order by b.bucket;
end;
$$;

grant execute on function get_revenue_trend(uuid, text, date, date, text) to authenticated;
