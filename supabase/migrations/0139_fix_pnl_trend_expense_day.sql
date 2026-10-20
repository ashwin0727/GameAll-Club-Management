-- ═══════════════════════════════════════════════════════════════════════════
-- Profit & Loss trend: an expense was drawn on the day BEFORE the day it was spent.
--
-- get_pnl_trend bucketed expenses with
--     date_trunc(unit, e.spent_on::timestamp at time zone tz)::date
-- `spent_on` is a plain date. Reading it "at time zone tz" turns it into a moment (18 Oct 00:00 in Asia/Kolkata is
-- 17 Oct 18:30 UTC), and date_trunc on that moment uses the database session's zone (UTC) — so an expense of 18 Oct
-- landed in the 17 Oct bucket. Revenue and refunds were right (they start as moments); the totals were right (they
-- compare ranges, not buckets). Only the trend chart's expense bars were a day early.
--
-- A date needs no zone: bucket it as the date it is. Same signature and columns as 0137; nothing else changes.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_pnl_trend(
  p_facility_id uuid, p_preset text default 'THIS_MONTH', p_start_date date default null,
  p_end_date date default null, p_granularity text default 'daily',
  p_facility_sport_ids uuid[] default null
) returns table (bucket_date date, revenue_minor bigint, expense_minor bigint, net_minor bigint)
language plpgsql stable as $$
declare range_ tstzrange; tz text; unit text;
begin
  if not has_permission(p_facility_id, 'FINANCE_VIEW_PNL') then
    raise exception 'You don''t have permission to view Profit & Loss.' using errcode = '42501';
  end if;
  if p_granularity not in ('daily', 'weekly', 'monthly') then
    raise exception 'Unknown granularity: %', p_granularity using errcode = '22023';
  end if;
  unit := case p_granularity when 'daily' then 'day' when 'weekly' then 'week' else 'month' end;
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  range_ := resolve_finance_date_range(p_facility_id, coalesce(p_preset, 'THIS_MONTH'), p_start_date, p_end_date);
  return query
  with rev as (
    select date_trunc(unit, v.effective_at at time zone tz)::date as bucket, sum(v.amount_minor) as amt
    from finance_transactions_view v
    where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
      and payment_in_sports(v.id, p_facility_sport_ids) group by 1
  ),
  ref as (
    select date_trunc(unit, r.processed_at at time zone tz)::date as bucket, sum(r.amount_minor) as amt
    from refunds r where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at
      and payment_order_in_sports(r.payment_order_id, p_facility_sport_ids) group by 1
  ),
  exp as (
    select date_trunc(unit, e.spent_on::timestamp)::date as bucket, sum(e.amount_minor) as amt
    from expenses e where e.facility_id = p_facility_id and e.status = 'RECORDED'
      and range_ @> (e.spent_on::timestamp at time zone tz) group by 1
  ),
  buckets as (select bucket from rev union select bucket from ref union select bucket from exp)
  select b.bucket, (coalesce(rev.amt, 0) - coalesce(ref.amt, 0))::bigint, coalesce(exp.amt, 0)::bigint,
    (coalesce(rev.amt, 0) - coalesce(ref.amt, 0) - coalesce(exp.amt, 0))::bigint
  from buckets b
  left join rev on rev.bucket = b.bucket
  left join ref on ref.bucket = b.bucket
  left join exp on exp.bucket = b.bucket
  order by b.bucket;
end; $$;

grant execute on function get_pnl_trend(uuid, text, date, date, text, uuid[]) to authenticated;
