-- ═══════════════════════════════════════════════════════════════════════════
-- Overall coaching revenue — everything ever collected for coaching enrollments, not just this month.
-- Same definition as the overview's "revenue this month" (paid payments tied to a coaching enrollment),
-- without the month window. Returned in minor units (paise), like the rest of the coaching figures.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function get_coaching_total_revenue(p_facility_id uuid)
returns bigint
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  return (
    select coalesce(sum(p.amount_inr) * 100, 0)::bigint
    from payments p
    where p.facility_id = p_facility_id
      and p.status = 'paid'
      and p.coaching_enrollment_id is not null
  );
end;
$$;

grant execute on function get_coaching_total_revenue(uuid) to authenticated;
