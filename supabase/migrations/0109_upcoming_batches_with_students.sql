-- ═══════════════════════════════════════════════════════════════════════════
-- Manage Students' "Upcoming Coaching Sessions" card needs the facility's
-- recurring program batches that actually have students enrolled — students
-- are enrolled straight into a Program + Batch (0107), with no per-occurrence
-- coaching_sessions row created for the ordinary weekly schedule (that table
-- is only for the separate Coach Scheduler ad-hoc flow), so there was nothing
-- for the card to read. This lists every ACTIVE batch, under an ACTIVE
-- program, that has at least one ACTIVE/PAUSED enrollment — the frontend
-- projects each one's next weekly occurrence from days_of_week/start_time.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function list_active_coaching_batches_with_students(p_facility_id uuid)
returns table (
  id uuid,
  program_id uuid,
  program_name text,
  batch_name text,
  days_of_week smallint[],
  start_time time,
  end_time time,
  court_name text,
  coach_name text,
  enrolled_count bigint,
  capacity integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  return query
  select
    b.id, b.program_id, cp.name, b.name, b.days_of_week, b.start_time, b.end_time,
    c.name, pr.full_name,
    (select count(*) from coaching_enrollments e where e.batch_id = b.id and e.status in ('ACTIVE', 'PAUSED'))::bigint,
    b.capacity
  from coaching_program_batches b
  join coaching_programs cp on cp.id = b.program_id
  join courts c on c.id = b.court_id
  left join coaches co on co.id = b.coach_id
  left join profiles pr on pr.id = co.user_id
  where cp.facility_id = p_facility_id
    and cp.status = 'ACTIVE'
    and b.status = 'ACTIVE'
    and exists (select 1 from coaching_enrollments e where e.batch_id = b.id and e.status in ('ACTIVE', 'PAUSED'))
  order by b.name;
end;
$$;

grant execute on function list_active_coaching_batches_with_students(uuid) to authenticated;
