-- ═══════════════════════════════════════════════════════════════════════════
-- Programs page cards: Total Programs, Active Programs, Enrolled Students, Available Seats.
--
-- Available Seats is the open capacity across ALL active programs, not one program:
--   * a program with active batches contributes its batches' open seats
--       (batch capacity − that batch's live enrollments), never below zero per batch;
--   * a program without batches contributes default_capacity − its live enrollments.
-- "Live" = ACTIVE or PAUSED, the same rule that enforces batch capacity when a student is enrolled (0107).
-- Inactive programs contribute nothing. Enrolled Students = students with an ACTIVE enrollment.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function get_program_card_stats(p_facility_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'totalPrograms', (select count(*) from coaching_programs where facility_id = p_facility_id),
    'activePrograms', (select count(*) from coaching_programs where facility_id = p_facility_id and status = 'ACTIVE'),
    'enrolledStudents', (select count(*) from coaching_enrollments where facility_id = p_facility_id and status = 'ACTIVE'),
    'availableSeats', (
      select coalesce(sum(seats), 0)::bigint from (
        select case
          when exists (select 1 from coaching_program_batches b where b.program_id = cp.id and b.status = 'ACTIVE')
          then (
            select coalesce(sum(greatest(
              b.capacity - (select count(*) from coaching_enrollments e
                            where e.batch_id = b.id and e.status in ('ACTIVE', 'PAUSED')), 0)), 0)
            from coaching_program_batches b
            where b.program_id = cp.id and b.status = 'ACTIVE'
          )
          else greatest(
            cp.default_capacity - (select count(*) from coaching_enrollments e
                                   where e.program_id = cp.id and e.status in ('ACTIVE', 'PAUSED')), 0)
        end as seats
        from coaching_programs cp
        where cp.facility_id = p_facility_id and cp.status = 'ACTIVE'
      ) s
    )
  );
end;
$$;

grant execute on function get_program_card_stats(uuid) to authenticated;
