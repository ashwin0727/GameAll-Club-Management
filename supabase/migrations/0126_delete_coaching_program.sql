-- ═══════════════════════════════════════════════════════════════════════════
-- Delete a coaching program — only while nobody has ever joined it.
--
-- A program with any enrollment (active, paused, completed or cancelled) carries fee obligations, payments
-- and history that must not vanish, so it can only be deactivated, never deleted. A program nobody joined
-- is removed together with its batches (cascade) and the sessions generated for it (none of which can have
-- students). The audit trail keeps a "program deleted" line.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function delete_coaching_program(p_program_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare existing coaching_programs;
begin
  select * into existing from coaching_programs where id = p_program_id;
  if existing.id is null then
    raise exception 'Program not found.' using errcode = 'P0002';
  end if;
  if not has_permission(existing.facility_id, 'COACHING_MANAGE_PROGRAMS') then
    raise exception 'You don''t have permission to manage programs.' using errcode = '42501';
  end if;
  if exists (select 1 from coaching_enrollments where program_id = p_program_id) then
    raise exception 'This program has students enrolled, so it can''t be deleted. Deactivate it instead.' using errcode = '23514';
  end if;

  delete from coaching_sessions where program_id = p_program_id;
  delete from coaching_programs where id = p_program_id;
  perform log_coaching_event(existing.facility_id, 'PROGRAM_DELETED', 'Program deleted: ' || existing.name);
end;
$$;

grant execute on function delete_coaching_program(uuid) to authenticated;
