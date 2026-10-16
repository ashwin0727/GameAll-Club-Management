-- ═══════════════════════════════════════════════════════════════════════════
-- Students page cards: Total Students, Enrolled Students, Revenue Collected (this month), Payments Pending.
--
--   totalStudents    unique students (members) with any enrollment — not enrollment rows
--   enrolledStudents unique students with an ACTIVE enrollment
--   revenueMinor     paid coaching payments this month (facility timezone) — same rule as the Coaching overview
--   pendingMinor     what is still owed on enrollments that are not cancelled and not membership-included:
--                    fee − confirmed payments, never below zero per enrollment
-- Money is in minor units (paise).
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function get_student_card_stats(p_facility_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  tz text;
  month_start timestamptz;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  tz := coalesce((select timezone from facilities where id = p_facility_id), 'Asia/Kolkata');
  month_start := date_trunc('month', now() at time zone tz) at time zone tz;

  return jsonb_build_object(
    'totalStudents', (select count(distinct member_id) from coaching_enrollments where facility_id = p_facility_id),
    'enrolledStudents', (
      select count(distinct member_id) from coaching_enrollments where facility_id = p_facility_id and status = 'ACTIVE'
    ),
    'revenueMinor', (
      select coalesce(sum(p.amount_inr) * 100, 0)::bigint from payments p
      where p.facility_id = p_facility_id and p.status = 'paid' and p.coaching_enrollment_id is not null
        and coalesce(p.paid_at, p.created_at) >= month_start
        and coalesce(p.paid_at, p.created_at) < month_start + interval '1 month'
    ),
    'pendingMinor', (
      select coalesce(sum(greatest(e.price_minor - coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.coaching_enrollment_id = e.id and p.status = 'paid'), 0), 0)), 0)::bigint
      from coaching_enrollments e
      where e.facility_id = p_facility_id and e.status <> 'CANCELLED' and e.pricing_type <> 'MEMBERSHIP_INCLUDED'
    )
  );
end;
$$;

grant execute on function get_student_card_stats(uuid) to authenticated;
