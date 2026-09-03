-- ═══════════════════════════════════════════════════════════════════════════
-- Payment-method breakdown for the Finance dashboard.
--
-- payment_method already rides on every captured payment and is surfaced per
-- row by finance_transactions_view; what was missing was the aggregate, so
-- the client would have had to pull every transaction and sum them itself.
-- That is the one thing Finance is not allowed to do.
--
-- Payments taken before the method was recorded come back as 'Unknown'
-- rather than being dropped, so the parts still add up to the whole.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function get_payment_method_breakdown(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null
)
returns table (
  payment_method text,
  amount_minor bigint,
  payment_count bigint
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
    coalesce(nullif(trim(p.payment_method), ''), 'Unknown') as payment_method,
    (coalesce(sum(p.amount_inr), 0) * 100)::bigint as amount_minor,
    count(*)::bigint as payment_count
  from payments p
  where p.facility_id = p_facility_id
    and p.status = 'paid'
    and range_ @> coalesce(p.paid_at, p.created_at)
  group by 1
  order by 2 desc;
end;
$$;

grant execute on function get_payment_method_breakdown(uuid, text, date, date) to authenticated;
