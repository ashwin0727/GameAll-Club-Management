-- ═══════════════════════════════════════════════════════════════════════════
-- Membership slot "X / N members" counts the batch roster.
--
-- Since the Create Membership time-slot flow (Phase 5), enrolling a member
-- into a batch (membership_batch_members) reserves their slot for every
-- recurring occurrence — they don't book each date individually. But the
-- membership-slot card / release logic only counted per-date
-- membership_session_bookings, so a batch with 2 enrolled members showed
-- "0 / 8" and offered to release all 8 for guests.
--
-- Count = GREATEST(per-date member bookings, batch roster size). GREATEST
-- keeps the older per-session book_membership_slot path working without
-- double-counting a member who is both enrolled and has a booking.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function list_membership_sessions_for_date(p_facility_id uuid, p_date date) returns table (
  batch_id uuid,
  session_id uuid,
  batch_name text,
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  session_date date,
  start_time time,
  end_time time,
  capacity integer,
  released_capacity integer,
  member_booked_count integer,
  guest_booked_count integer
)
language sql
stable
as $$
  select
    b.id,
    s.id,
    b.name,
    b.court_id,
    c.name,
    b.facility_sport_id,
    coalesce(fs.custom_sport_name, sp.name),
    p_date,
    b.start_time,
    b.end_time,
    b.capacity,
    coalesce(s.released_capacity, 0),
    greatest(
      coalesce((select count(*) from membership_session_bookings mb where mb.session_id = s.id and mb.participant_type = 'MEMBER' and mb.status = 'CONFIRMED'), 0),
      (select count(*) from membership_batch_members bm where bm.batch_id = b.id)
    )::integer,
    coalesce((select count(*) from membership_session_bookings mb where mb.session_id = s.id and mb.participant_type = 'GUEST' and mb.status = 'CONFIRMED'), 0)::integer
  from membership_batches b
  join courts c on c.id = b.court_id
  join facility_sports fs on fs.id = b.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  left join membership_sessions s on s.batch_id = b.id and s.session_date = p_date
  where b.facility_id = p_facility_id
    and b.is_active
    and extract(dow from p_date)::smallint = any(b.days_of_week)
  order by b.start_time;
$$;

grant execute on function list_membership_sessions_for_date(uuid, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- release_membership_capacity — the unused pool is capacity minus the
-- roster (not just per-date bookings), so an owner can't release a slot
-- that belongs to an enrolled member.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function release_membership_capacity(p_session_id uuid, p_count integer) returns membership_sessions
language plpgsql
as $$
declare
  session membership_sessions;
  used integer;
  unused integer;
  result membership_sessions;
begin
  if p_count <= 0 then
    raise exception 'Release count must be positive.' using errcode = '23514';
  end if;

  select * into session from membership_sessions where id = p_session_id for update;
  if session.id is null then
    raise exception 'Membership session not found' using errcode = 'P0002';
  end if;

  select greatest(
    (select count(*) from membership_session_bookings
       where session_id = session.id and participant_type = 'MEMBER' and status = 'CONFIRMED'),
    (select count(*) from membership_batch_members where batch_id = session.batch_id)
  ) into used;
  unused := session.capacity - used;

  if session.released_capacity + p_count > unused then
    raise exception 'Cannot release more than the unused membership capacity.' using errcode = '23514';
  end if;

  update membership_sessions set released_capacity = released_capacity + p_count, updated_at = now()
  where id = p_session_id
  returning * into result;

  return result;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- book_membership_slot — same roster-aware capacity guard so the old
-- per-session path can't push a batch past its capacity either.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function book_membership_slot(p_batch_id uuid, p_session_date date, p_member_id uuid)
returns membership_session_bookings
language plpgsql
as $$
declare
  session membership_sessions;
  used integer;
  result membership_session_bookings;
begin
  if not exists (select 1 from membership_batch_members where batch_id = p_batch_id and member_id = p_member_id) then
    raise exception 'This member is not assigned to this membership batch.' using errcode = '23514';
  end if;

  session := get_or_create_membership_session(p_batch_id, p_session_date);
  select * into session from membership_sessions where id = session.id for update;

  select greatest(
    (select count(*) from membership_session_bookings
       where session_id = session.id and participant_type = 'MEMBER' and status = 'CONFIRMED'),
    (select count(*) from membership_batch_members where batch_id = p_batch_id)
  ) into used;

  if used >= session.capacity then
    raise exception 'Membership capacity is full for this session.' using errcode = '23514';
  end if;

  insert into membership_session_bookings (session_id, facility_id, participant_type, member_id, status, slot_source, created_by)
  values (session.id, session.facility_id, 'MEMBER', p_member_id, 'CONFIRMED', 'MEMBERSHIP', auth.uid())
  returning * into result;

  return result;
end;
$$;