-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: Session detail page failed with
--   column reference "cs.program_id" is ambiguous
--
-- 0105 rewrote get_coaching_session with "from coaching_sessions cs ...", but the
-- function also declares a plpgsql variable named cs. Inside the returning
-- query, cs.<column> could mean either the variable or the table alias, so
-- Postgres refused to pick. The variable is renamed to sess; the query (and so
-- the payload) is unchanged, with cs now unambiguously the table alias.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_coaching_session(p_session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  sess coaching_sessions;
  v_can_progress boolean;
begin
  select * into sess from coaching_sessions where id = p_session_id;
  if sess.id is null then
    raise exception 'Session not found.' using errcode = 'P0002';
  end if;
  if not has_permission(sess.facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  v_can_progress := has_permission(sess.facility_id, 'COACHING_VIEW_PROGRESS');

  return (
    select jsonb_build_object(
      'id', cs.id,
      'facilityId', cs.facility_id,
      'programId', cs.program_id,
      'programName', coalesce(cp.name, cs.title, 'Coaching Session'),
      'programLevel', coalesce(cp.level, cs.level),
      'coachId', cs.coach_id,
      'coachName', pr.full_name,
      'courtId', cs.court_id,
      'courtName', c.name,
      'startAt', cs.start_at,
      'endAt', cs.end_at,
      'capacity', cs.capacity,
      'status', cs.status,
      'notes', cs.notes,
      'objective', cs.objective,
      'objectiveResult', cs.objective_result,
      'completedAt', cs.completed_at,
      'cancelReason', cs.cancel_reason,
      'title', cs.title,
      'description', cs.description,
      'sessionType', cs.session_type,
      'facilitySportId', cs.facility_sport_id,
      'pricePerStudentMinor', cs.price_per_student_minor,
      'visibleForBooking', cs.visible_for_booking,
      'sendNotification', cs.send_notification,
      'allowWaitlist', cs.allow_waitlist,
      'enrolledCount', (select count(*) from coaching_session_students css where css.session_id = cs.id and css.status = 'ENROLLED'),
      'students', coalesce((
        select jsonb_agg(jsonb_build_object(
          'enrollmentId', e.id,
          'memberId', e.member_id,
          'name', m.full_name,
          'phone', m.phone,
          'status', css.status,
          'enrollmentStatus', e.status
        ) order by m.full_name)
        from coaching_session_students css
        join coaching_enrollments e on e.id = css.enrollment_id
        join members m on m.id = e.member_id
        where css.session_id = cs.id and css.status = 'ENROLLED'
      ), '[]'::jsonb),
      'progressNotes', case when v_can_progress then coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', spn.id, 'memberName', m.full_name, 'skillOrGoal', spn.skill_or_goal,
          'note', spn.note, 'progressStatus', spn.progress_status, 'createdAt', spn.created_at
        ) order by spn.created_at desc)
        from student_progress_notes spn
        join coaching_enrollments e on e.id = spn.enrollment_id
        join members m on m.id = e.member_id
        where spn.session_id = cs.id
      ), '[]'::jsonb) else null end,
      'events', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', ev.id, 'event', ev.event, 'summary', ev.summary,
          'actorName', ap.full_name, 'createdAt', ev.created_at
        ) order by ev.created_at desc)
        from coaching_events ev
        left join profiles ap on ap.id = ev.actor
        where ev.session_id = cs.id
      ), '[]'::jsonb)
    )
    from coaching_sessions cs
    left join coaching_programs cp on cp.id = cs.program_id
    join coaches co on co.id = cs.coach_id
    join profiles pr on pr.id = co.user_id
    join courts c on c.id = cs.court_id
    where cs.id = p_session_id
  );
end;
$$;


grant execute on function get_coaching_session(uuid) to authenticated;
