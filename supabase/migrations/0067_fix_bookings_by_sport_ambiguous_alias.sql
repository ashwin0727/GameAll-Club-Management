-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: get_bookings_by_sport (0058) referenced the output column name
-- `sport_name` bare in GROUP BY / ORDER BY, where it also exists as a
-- RETURNS TABLE variable → the same ambiguity class as 0066.
--
-- Rewritten to group/order by the underlying expression, and
-- `#variable_conflict use_column` added to match 0066. Logic unchanged.
-- ═══════════════════════════════════════════════════════════════════════════

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
  group by fs.id, coalesce(fs.custom_sport_name, sp.name)
  order by count(bk.id) desc, coalesce(fs.custom_sport_name, sp.name);
end;
$$;

grant execute on function get_bookings_by_sport(uuid, text, date, date, uuid, uuid) to authenticated;
