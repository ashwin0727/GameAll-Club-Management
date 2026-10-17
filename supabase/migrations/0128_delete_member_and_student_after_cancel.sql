-- ═══════════════════════════════════════════════════════════════════════════
-- Deleting a member / a student after AutoPay is cancelled.
--
-- The apps now walk the owner through: Delete → (if AutoPay is still running) "Cancel AutoPay and the
-- membership / coaching first" → that cancels but does NOT delete → choose Delete again → it deletes.
-- These two functions are the server side of that last step.
--
-- delete_member (replaces 0030's, which refused ANY booking or settled payment):
--   * still owner / manager only;
--   * refused while AutoPay is live (created / authenticated / active / pending / halted) — the member could
--     still be charged — and while they have an upcoming booking, or a coaching enrollment (delete or cancel
--     that on the Students page first);
--   * otherwise the member goes, with their memberships, bookings and batch places. Payments that were
--     received or refunded are KEPT (detached from the member) so Finance totals don't change.
--
-- delete_coaching_enrollment (replaces 0127's, which refused any received payment):
--   * refused while an online link / AutoPay is live;
--   * refused when money was received and the enrollment is not yet CANCELLED (cancel coaching first);
--   * received / refunded payments are KEPT (detached), never-paid ones are removed.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function delete_member(p_member_id uuid) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_facility uuid;
begin
  select facility_id into v_facility from members where id = p_member_id;
  if v_facility is null then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(v_facility, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized to delete members.' using errcode = '42501';
  end if;

  if exists (
    select 1 from membership_subscriptions s
    where s.member_id = p_member_id and s.status in ('created', 'authenticated', 'active', 'pending', 'halted')
  ) then
    raise exception 'AutoPay is still active for this member. Cancel AutoPay first, then delete.' using errcode = '23514';
  end if;

  if exists (
    select 1 from bookings b
    where b.member_id = p_member_id and b.status in ('pending', 'confirmed') and b.start_time > now()
  ) then
    raise exception 'This member has upcoming bookings. Cancel them first, then delete.' using errcode = '23514';
  end if;

  if exists (select 1 from coaching_enrollments e where e.member_id = p_member_id) then
    raise exception 'This member is enrolled in coaching. Delete that student on the Students page first.' using errcode = '23514';
  end if;

  -- Money that changed hands stays on the books, just no longer tied to a deleted person.
  update payments set member_id = null where member_id = p_member_id and status in ('paid', 'refunded');

  delete from members where id = p_member_id;
end;
$$;

grant execute on function delete_member(uuid) to authenticated;

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
    select 1 from coaching_enrollment_billing b
    where b.enrollment_id = p_enrollment_id and b.status in ('CREATED', 'AUTHENTICATED', 'ACTIVE', 'PENDING', 'HALTED')
  ) then
    raise exception 'An online payment link or auto-pay is still active for this student. Cancel it first, then delete.' using errcode = '23514';
  end if;

  if existing.status <> 'CANCELLED' and exists (
    select 1 from payments p
    where p.coaching_enrollment_id = p_enrollment_id and p.status in ('paid', 'refunded')
  ) then
    raise exception 'A payment has been received for this student. Cancel coaching first, then delete.' using errcode = '23514';
  end if;

  -- Received / refunded payments stay (their enrollment link is cleared by the foreign key); the rest go.
  delete from payments where coaching_enrollment_id = p_enrollment_id and status not in ('paid', 'refunded');
  delete from coaching_session_students where enrollment_id = p_enrollment_id;
  delete from coaching_enrollments where id = p_enrollment_id;
  perform log_coaching_event(existing.facility_id, 'ENROLLMENT_DELETED', 'Student enrollment deleted', null, existing.program_id);
end;
$$;

grant execute on function delete_coaching_enrollment(uuid) to authenticated;
