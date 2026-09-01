-- ═══════════════════════════════════════════════════════════════════════════
-- Membership Session detail page — replaces the slide-over drawer with a
-- full page. Adds the data the page shows that the drawer never did:
--   • membership_batches.notes        — free-text "Session Notes"
--   • membership_batches.created_by    — who created the session
--   • list_membership_session_members  — roster with name / phone / status
--   • get_membership_session_detail    — + facility name/address, notes,
--                                        created-by name, start date
--   • set_membership_batch_notes       — edit the notes
-- ═══════════════════════════════════════════════════════════════════════════

alter table membership_batches add column if not exists notes text;
alter table membership_batches add column if not exists created_by uuid references profiles (id) on delete set null;

-- ─────────────────────────────────────────────────────────────────────────
-- create_membership_batch — stamp created_by from the caller.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function create_membership_batch(
  p_facility_id uuid,
  p_plan_id uuid,
  p_facility_sport_id uuid,
  p_court_id uuid,
  p_name text,
  p_days_of_week smallint[],
  p_start_time time,
  p_end_time time,
  p_capacity integer
) returns membership_batches
language plpgsql
as $$
declare
  result membership_batches;
  court courts;
begin
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Batch name is required.' using errcode = '23514';
  end if;

  select * into court from courts where id = p_court_id and facility_id = p_facility_id and facility_sport_id = p_facility_sport_id;
  if court.id is null then
    raise exception 'That court does not belong to this facility/sport.' using errcode = '23503';
  end if;

  insert into membership_batches (
    facility_id, plan_id, facility_sport_id, court_id, name, days_of_week, start_time, end_time, capacity, created_by
  ) values (
    p_facility_id, p_plan_id, p_facility_sport_id, p_court_id, trim(p_name), p_days_of_week, p_start_time, p_end_time, p_capacity, auth.uid()
  ) returning * into result;

  return result;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- set_membership_batch_notes
-- ─────────────────────────────────────────────────────────────────────────
create or replace function set_membership_batch_notes(p_batch_id uuid, p_notes text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b membership_batches;
begin
  select * into b from membership_batches where id = p_batch_id;
  if b.id is null then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(b.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized.' using errcode = '42501';
  end if;
  update membership_batches
    set notes = nullif(trim(p_notes), ''), updated_at = now()
    where id = p_batch_id;
end;
$$;
grant execute on function set_membership_batch_notes(uuid, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_membership_session_members — the "Members Assigned" table.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_membership_session_members(p_batch_id uuid)
returns table (
  id uuid,
  member_id uuid,
  full_name text,
  phone text,
  status text,
  added_on timestamptz
)
language sql
stable
as $$
  select bm.id, bm.member_id, m.full_name, m.phone, m.status, bm.created_at
  from membership_batch_members bm
  join members m on m.id = bm.member_id
  where bm.batch_id = p_batch_id
  order by bm.created_at asc;
$$;
grant execute on function list_membership_session_members(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_membership_session_detail — + facility name/address, notes,
-- created-by name, start date.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_membership_session_detail(p_batch_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  b membership_batches;
  court_name text;
  sport_name text;
  plan_name text;
  creator text;
  facility_name text;
  facility_address text;
  roster integer;
  today_guests integer;
  today_mat_id uuid;
  today_released integer;
  next_date date;
  d date;
begin
  select * into b from membership_batches where id = p_batch_id;
  if b.id is null then
    raise exception 'Session not found' using errcode = 'P0002';
  end if;

  select c.name into court_name from courts c where c.id = b.court_id;
  select coalesce(fs.custom_sport_name, sp.name) into sport_name
    from facility_sports fs join sports sp on sp.id = fs.sport_id where fs.id = b.facility_sport_id;
  if b.plan_id is not null then
    select name into plan_name from membership_plans where id = b.plan_id;
  end if;
  if b.created_by is not null then
    select full_name into creator from profiles where id = b.created_by;
  end if;
  select f.name,
         nullif(concat_ws(', ', nullif(trim(f.address), ''), nullif(trim(f.city), '')), '')
    into facility_name, facility_address
    from facilities f where f.id = b.facility_id;

  roster := membership_batch_roster_count(b.id);

  select s.id, s.released_capacity into today_mat_id, today_released
    from membership_sessions s where s.batch_id = b.id and s.session_date = current_date;
  select count(*) into today_guests from membership_session_bookings mb
    where mb.session_id = today_mat_id and mb.participant_type = 'GUEST' and mb.status = 'CONFIRMED';

  next_date := null;
  for i in 1..14 loop
    d := current_date + i;
    if extract(dow from d)::smallint = any(b.days_of_week)
       and not exists (select 1 from membership_batch_blocked_dates x where x.batch_id = b.id and x.blocked_date = d) then
      next_date := d;
      exit;
    end if;
  end loop;

  return jsonb_build_object(
    'batchId', b.id,
    'facilityId', b.facility_id,
    'facilityName', facility_name,
    'facilityAddress', facility_address,
    'name', b.name,
    'notes', b.notes,
    'courtId', b.court_id,
    'courtName', court_name,
    'facilitySportId', b.facility_sport_id,
    'sportName', sport_name,
    'planName', plan_name,
    'daysOfWeek', b.days_of_week,
    'startTime', b.start_time,
    'endTime', b.end_time,
    'capacity', b.capacity,
    'isActive', b.is_active,
    'createdByName', creator,
    'createdAt', b.created_at,
    'updatedAt', b.updated_at,
    'rosterCount', roster,
    'guestsBookedToday', coalesce(today_guests, 0),
    'releasedToday', coalesce(today_released, 0),
    'availableToRelease', greatest(b.capacity - roster - coalesce(today_released, 0), 0),
    'runsToday', (extract(dow from current_date)::smallint = any(b.days_of_week)
      and not exists (select 1 from membership_batch_blocked_dates x where x.batch_id = b.id and x.blocked_date = current_date)),
    'nextOccurrenceDate', next_date
  );
end;
$$;
grant execute on function get_membership_session_detail(uuid) to authenticated;