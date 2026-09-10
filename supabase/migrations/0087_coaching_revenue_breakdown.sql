-- ═══════════════════════════════════════════════════════════════════════════
-- Revenue by Source — break out coaching as its own line.
--
-- finance_transactions_view already classifies a coaching payment as
-- source_type 'COACHING' (0085), so it was correctly EXCLUDED from
-- member_booking_revenue_minor and INCLUDED in net_revenue_minor — it just
-- had no dedicated line. This adds coaching_revenue_minor as a trailing
-- column.
--
-- Postgres won't let CREATE OR REPLACE change a function's RETURNS TABLE
-- shape, so the old definition is dropped first. Nothing depends on it by
-- row type (callers are late-bound plpgsql; no view is `returns setof` it).
--
-- Recreated verbatim from 0048 with one added output column and one added
-- filtered sum.
-- ═══════════════════════════════════════════════════════════════════════════

drop function if exists get_revenue_breakdown(uuid, text, date, date);

create function get_revenue_breakdown(
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
  membership_included_usage_count bigint,
  coaching_revenue_minor bigint
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
    )::bigint,
    coalesce(sum(amount_minor) filter (where source_type = 'COACHING'), 0)::bigint
  from classified;
end;
$$;

grant execute on function get_revenue_breakdown(uuid, text, date, date) to authenticated;
