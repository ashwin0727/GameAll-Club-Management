-- ═══════════════════════════════════════════════════════════════════════════
-- "Active Sessions" — the coaching sessions still to be delivered.
--
-- NOTE: superseded. Active Sessions is now simply the current day's session count, worked out from the
-- session list, so nothing calls this function any more. It stays here because the migration was already
-- applied; 0117 drops the function.
--
-- Counted across every ACTIVE program that has at least one ACTIVE student. A program that is already
-- running counts, and so does one that starts in a few days — only programs nobody is enrolled in are
-- left out. For each such program:
--
--     pending = the program's session total  −  sessions already completed      (never below 0)
--
-- The session total is the program's own session_count (the "Sessions" column of the programs table),
-- falling back to the planned_sessions figure migration 0113 calculates from its batches and dates.
-- (planned_sessions is read through to_jsonb so this still installs if 0113 hasn't been applied yet.)
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function get_coaching_active_sessions(p_facility_id uuid)
returns integer
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
    select coalesce(sum(greatest(
      coalesce(cp.session_count, nullif(to_jsonb(cp) ->> 'planned_sessions', '')::integer, 0)
        - (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status = 'COMPLETED'),
      0
    )), 0)::integer
    from coaching_programs cp
    where cp.facility_id = p_facility_id
      and cp.status = 'ACTIVE'
      and exists (
        select 1 from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE'
      )
  );
end;
$$;

grant execute on function get_coaching_active_sessions(uuid) to authenticated;
