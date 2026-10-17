-- ═══════════════════════════════════════════════════════════════════════════
-- Delete a student's enrollment — only while no money has changed hands.
--
-- Refused when any payment has been received or refunded on it (that history must stay), and while an online
-- payment link / AutoPay is still live at Razorpay (cancel that first, or the student could still be charged).
-- Otherwise the enrollment is removed with its never-paid payment rows, its billing record, and its place in
-- sessions. The student (member) record itself is untouched.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function delete_coaching_enrollment(p_enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare existing coaching_enrollments;
begin
  select * into existing from coaching_enrollments where id = p_enrollment_id;
  if existing.id is null then
    raise exception 'Enrollment not found.' using errcode = 'P0002';
  end if;
  if not has_permission(existing.facility_id, 'COACHING_MANAGE_ENROLLMENTS') then
    raise exception 'You don''t have permission to manage enrollments.' using errcode = '42501';
  end if;

  if exists (
    select 1 from payments p
    where p.coaching_enrollment_id = p_enrollment_id and p.status in ('paid', 'refunded')
  ) then
    raise exception 'A payment has already been received for this student, so the enrollment can''t be deleted. Cancel it instead.' using errcode = '23514';
  end if;

  if exists (
    select 1 from coaching_enrollment_billing b
    where b.enrollment_id = p_enrollment_id and b.status in ('CREATED', 'AUTHENTICATED', 'ACTIVE', 'PENDING', 'HALTED')
  ) then
    raise exception 'An online payment link or auto-pay is still active for this student. Cancel it first, then delete.' using errcode = '23514';
  end if;

  delete from payments where coaching_enrollment_id = p_enrollment_id;
  delete from coaching_session_students where enrollment_id = p_enrollment_id;
  delete from coaching_enrollments where id = p_enrollment_id;
  perform log_coaching_event(existing.facility_id, 'ENROLLMENT_DELETED', 'Student enrollment deleted', null, existing.program_id);
end;
$$;

grant execute on function delete_coaching_enrollment(uuid) to authenticated;
