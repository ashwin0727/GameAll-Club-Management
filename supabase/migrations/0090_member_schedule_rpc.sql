-- ═══════════════════════════════════════════════════════════════════════════
-- list_member_schedules — read RPC for the new "Manage Member Schedule" page.
--
-- One row per (member, batch) they're enrolled in — a member with two
-- non-adjacent playing hours (two batches) gets two rows. The page groups
-- these client-side into "this member's weekly slots". Mirrors the shape and
-- style of list_assignable_batches (0027): plain SQL, STABLE, no SECURITY
-- DEFINER — it runs as the caller, so the existing members/membership_batches
-- RLS policies gate it exactly like every other staff-facing read.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function list_member_schedules(p_facility_id uuid)
returns table (
  member_id uuid,
  full_name text,
  phone text,
  status text,
  membership_id uuid,
  batch_id uuid,
  batch_name text,
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  days_of_week integer[],
  start_time time,
  end_time time
)
language sql
stable
as $$
  select
    m.id,
    m.full_name,
    m.phone,
    m.status::text,
    mbm.membership_id,
    mb.id,
    mb.name,
    mb.court_id,
    c.name,
    mb.facility_sport_id,
    coalesce(fs.custom_sport_name, s.name),
    mb.days_of_week,
    mb.start_time,
    mb.end_time
  from members m
  join membership_batch_members mbm on mbm.member_id = m.id
  join membership_batches mb on mb.id = mbm.batch_id and mb.is_active
  join courts c on c.id = mb.court_id
  join facility_sports fs on fs.id = mb.facility_sport_id
  join sports s on s.id = fs.sport_id
  where m.facility_id = p_facility_id
  order by m.full_name, mb.start_time;
$$;

grant execute on function list_member_schedules(uuid) to authenticated;
