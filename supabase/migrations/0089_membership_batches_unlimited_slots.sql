-- ═══════════════════════════════════════════════════════════════════════════
-- Membership batches: stop restricting how many members can share a court's
-- day/time slot.
--
-- Two things were blocking it:
--   1. membership_batches_no_conflict (0045) raised on ANY new/updated batch
--      that overlapped another active batch on the same court, even when
--      that was exactly what the owner wanted — several members sharing the
--      same recurring slot. The Add Member wizard always created its own
--      capacity-1 batch per member, so this fired for literally the second
--      member on any slot ("This court is already reserved by ... at an
--      overlapping time").
--   2. assign_batch_member (0027) additionally capped enrolment at the
--      batch's own `capacity` column.
--
-- Both are removed: a court/day/time slot can now hold as many members as
-- the owner assigns to it. (The wizard itself is changed separately to
-- join an existing matching batch instead of creating a new one each time,
-- so the roster stays on one batch rather than fragmenting.)
-- ═══════════════════════════════════════════════════════════════════════════

drop trigger if exists membership_batches_no_conflict on membership_batches;
drop function if exists check_membership_batch_conflict();

create or replace function assign_batch_member(p_batch_id uuid, p_member_id uuid, p_membership_id uuid default null)
returns membership_batch_members
language plpgsql
as $$
declare
  batch membership_batches;
  member members;
  result membership_batch_members;
begin
  select * into batch from membership_batches where id = p_batch_id;
  if batch.id is null then
    raise exception 'Membership batch not found' using errcode = 'P0002';
  end if;

  select * into member from members where id = p_member_id and facility_id = batch.facility_id;
  if member.id is null then
    raise exception 'That member does not belong to this facility.' using errcode = '23503';
  end if;

  -- Already in this batch? Idempotent no-op — return the existing row.
  select * into result from membership_batch_members
    where batch_id = p_batch_id and member_id = p_member_id;
  if result.id is not null then
    return result;
  end if;

  -- No capacity check — a slot can hold as many members as are assigned to it.
  insert into membership_batch_members (batch_id, member_id, membership_id)
  values (p_batch_id, p_member_id, p_membership_id)
  returning * into result;

  return result;
end;
$$;
