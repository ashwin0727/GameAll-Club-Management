-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching sessions — the scheduled instances that reserve a court and a
-- coach, and the wiring that makes them a first-class citizen of the
-- existing availability engine.
--
-- A coaching session is the availability-facing record, the same role
-- maintenance_blocks plays (0068). It gets TWO partial GiST exclusion
-- constraints (court, coach) so two live sessions can never overlap on the
-- same court OR the same coach — enforced by Postgres, not application code
-- (spec §51). court_has_active_coaching_session() is then folded into
-- create_booking / reschedule_booking / get_public_court_availability the
-- same way court_has_active_maintenance_block already is, so a normal
-- booking can never be taken over a coaching session (spec §10 / §50).
--
-- The one place the exclusion constraints don't reach is a booking and a
-- coaching session created at the same instant for the same court: both
-- write to different tables. _coaching_court_lock_key() + pg_advisory_xact_lock
-- in create_booking / reschedule_booking / create_coaching_session /
-- reschedule_coaching_session serialize exactly that pair (spec §50).
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- coaching_sessions
-- ─────────────────────────────────────────────────────────────────────────
create table coaching_sessions (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  program_id uuid not null references coaching_programs (id) on delete restrict,
  coach_id uuid not null references coaches (id) on delete restrict,
  court_id uuid not null references courts (id) on delete restrict,
  start_at timestamptz not null,
  end_at timestamptz not null,
  capacity integer not null default 1 check (capacity between 1 and 100),
  status text not null default 'SCHEDULED'
    check (status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')),
  notes text,
  objective text,
  objective_result text,
  completed_at timestamptz,
  completed_by uuid references profiles (id) on delete set null,
  cancelled_at timestamptz,
  cancel_reason text,
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coaching_sessions_time_check check (end_at > start_at),
  -- No two live sessions on the same court at overlapping times.
  constraint coaching_sessions_court_no_overlap exclude using gist (
    court_id with =,
    tstzrange(start_at, end_at) with &&
  ) where (status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS')),
  -- No two live sessions with the same coach at overlapping times (spec §51).
  constraint coaching_sessions_coach_no_overlap exclude using gist (
    coach_id with =,
    tstzrange(start_at, end_at) with &&
  ) where (status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS'))
);

create index coaching_sessions_facility_start_idx on coaching_sessions (facility_id, start_at);
create index coaching_sessions_court_start_idx on coaching_sessions (court_id, start_at);
create index coaching_sessions_coach_start_idx on coaching_sessions (coach_id, start_at);
create index coaching_sessions_program_idx on coaching_sessions (program_id);
create index coaching_sessions_status_idx on coaching_sessions (facility_id, status);

alter table coaching_sessions enable row level security;
drop policy if exists "coaching_sessions_select" on coaching_sessions;
create policy "coaching_sessions_select" on coaching_sessions for select
  using (has_permission(facility_id, 'COACHING_VIEW'));

drop trigger if exists coaching_sessions_set_updated_at on coaching_sessions;
create trigger coaching_sessions_set_updated_at
  before update on coaching_sessions
  for each row execute function set_updated_at();


-- The per-session roster table (coaching_session_students) and its add/
-- remove RPCs live in 0084, next to coaching_enrollments which it references.


-- ─────────────────────────────────────────────────────────────────────────
-- Predicates + the advisory-lock key.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function _coaching_court_lock_key(p_court_id uuid) returns bigint
language sql immutable
as $$ select hashtextextended('coaching_court:' || p_court_id::text, 0) $$;

create or replace function court_has_active_coaching_session(
  p_court_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_exclude_session_id uuid default null
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from coaching_sessions cs
    where cs.court_id = p_court_id
      and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS')
      and (p_exclude_session_id is null or cs.id <> p_exclude_session_id)
      and tstzrange(cs.start_at, cs.end_at) && tstzrange(p_start, p_end)
  );
$$;

grant execute on function court_has_active_coaching_session(uuid, timestamptz, timestamptz, uuid) to anon, authenticated;

create or replace function coach_has_active_coaching_session(
  p_coach_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_exclude_session_id uuid default null
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from coaching_sessions cs
    where cs.coach_id = p_coach_id
      and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS')
      and (p_exclude_session_id is null or cs.id <> p_exclude_session_id)
      and tstzrange(cs.start_at, cs.end_at) && tstzrange(p_start, p_end)
  );
$$;

grant execute on function coach_has_active_coaching_session(uuid, timestamptz, timestamptz, uuid) to authenticated;


-- court_has_overlapping_booking — a live (pending/confirmed) booking on the
-- court/time. Used only by coaching-session creation, which must hard-reject
-- (unlike maintenance, which overrides bookings). The bookings exclusion
-- constraint still owns booking-vs-booking; this is the coaching-vs-booking
-- read, serialized by _coaching_court_lock_key.
create or replace function court_has_overlapping_booking(
  p_court_id uuid,
  p_start timestamptz,
  p_end timestamptz
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from bookings b
    where b.court_id = p_court_id
      and b.status in ('pending', 'confirmed')
      and tstzrange(b.start_time, b.end_time) && tstzrange(p_start, p_end)
  );
$$;

grant execute on function court_has_overlapping_booking(uuid, timestamptz, timestamptz) to authenticated;


-- ═════════════════════════════════════════════════════════════════════════
-- Re-wire the three availability functions. Each is recreated verbatim from
-- 0068 with exactly two additions: an advisory-lock acquisition (writers
-- only) and the court_has_active_coaching_session check, placed right after
-- the maintenance-block check.
-- ═════════════════════════════════════════════════════════════════════════
create or replace function create_booking(
  p_facility_id uuid,
  p_court_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_customer_type text,
  p_member_id uuid,
  p_guest_name text,
  p_guest_phone text,
  p_notes text,
  p_payment_status text default 'PENDING',
  p_guest_player_id uuid default null,
  p_party_size integer default 1,
  p_payment_method text default null
) returns bookings
language plpgsql
as $$
declare
  result bookings;
  fac facilities;
  court courts;
  price integer;
  guest guest_players;
  v_guest_name text := p_guest_name;
  v_guest_phone text := p_guest_phone;
begin
  if p_end_time <= p_start_time then
    raise exception 'End time must be after start time.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    raise exception 'facility % does not exist', p_facility_id using errcode = '23503';
  end if;

  select * into court from courts where id = p_court_id and facility_id = p_facility_id;
  if court.id is null then
    raise exception 'court % does not exist for this facility', p_court_id using errcode = '23503';
  end if;

  -- Serialize against a coaching session being created for the same court at
  -- the same instant (spec §50). Released at transaction end.
  perform pg_advisory_xact_lock(_coaching_court_lock_key(p_court_id));

  if p_guest_player_id is not null then
    select * into guest from guest_players where id = p_guest_player_id and facility_id = p_facility_id;
    if guest.id is null then
      raise exception 'guest % does not exist for this facility', p_guest_player_id using errcode = '23503';
    end if;
    v_guest_name := guest.name;
    v_guest_phone := guest.phone;
  end if;

  if not booking_window_fits_operating_hours(p_facility_id, p_court_id, p_start_time, p_end_time) then
    raise exception 'Selected time is outside this court''s operating hours.' using errcode = '23514';
  end if;

  if court_has_active_membership_window(p_court_id, p_start_time, p_end_time, fac.timezone) then
    raise exception 'This time is reserved for a membership session. Use guest slot booking for this court/time instead.' using errcode = '23514';
  end if;

  if court_has_active_maintenance_block(p_court_id, p_start_time, p_end_time) then
    raise exception 'This court is under maintenance during the selected time.' using errcode = '23514';
  end if;

  if court_has_active_coaching_session(p_court_id, p_start_time, p_end_time) then
    raise exception 'This court is reserved for a coaching session during the selected time.' using errcode = '23514';
  end if;

  price := resolve_booking_price(court.facility_sport_id, p_court_id, p_start_time, p_end_time, fac.timezone);

  insert into bookings (
    facility_id, court_id, member_id, start_time, end_time, status,
    customer_type, guest_name, guest_phone, guest_player_id,
    amount_minor, currency, notes, created_by, payment_status,
    party_size, payment_method
  ) values (
    p_facility_id, p_court_id, p_member_id, p_start_time, p_end_time, 'confirmed',
    coalesce(p_customer_type, 'MEMBER'), v_guest_name, v_guest_phone, p_guest_player_id,
    price, fac.currency, p_notes, auth.uid(), coalesce(p_payment_status, 'PENDING'),
    greatest(coalesce(p_party_size, 1), 1), nullif(trim(p_payment_method), '')
  ) returning * into result;

  return result;
end;
$$;
grant execute on function create_booking(uuid, uuid, timestamptz, timestamptz, text, uuid, text, text, text, text, uuid, integer, text) to authenticated;


create or replace function reschedule_booking(
  p_booking_id uuid,
  p_new_court_id uuid,
  p_new_start_time timestamptz,
  p_new_end_time timestamptz
) returns bookings
language plpgsql
as $$
declare
  result bookings;
  fac facilities;
  court courts;
  price integer;
begin
  if p_new_end_time <= p_new_start_time then
    raise exception 'End time must be after start time.' using errcode = '23514';
  end if;

  select * into result from bookings where id = p_booking_id;
  if result.id is null then
    raise exception 'booking % does not exist', p_booking_id using errcode = '23503';
  end if;
  if result.status not in ('pending', 'confirmed') then
    raise exception 'Only a pending or confirmed booking can be rescheduled.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = result.facility_id;
  select * into court from courts where id = p_new_court_id and facility_id = result.facility_id;
  if court.id is null then
    raise exception 'court % does not exist for this facility', p_new_court_id using errcode = '23503';
  end if;

  perform pg_advisory_xact_lock(_coaching_court_lock_key(p_new_court_id));

  if not booking_window_fits_operating_hours(result.facility_id, p_new_court_id, p_new_start_time, p_new_end_time) then
    raise exception 'Selected time is outside this court''s operating hours.' using errcode = '23514';
  end if;

  if court_has_active_membership_window(p_new_court_id, p_new_start_time, p_new_end_time, fac.timezone) then
    raise exception 'This time is reserved for a membership session. Use guest slot booking for this court/time instead.' using errcode = '23514';
  end if;

  if court_has_active_maintenance_block(p_new_court_id, p_new_start_time, p_new_end_time) then
    raise exception 'This court is under maintenance during the selected time.' using errcode = '23514';
  end if;

  if court_has_active_coaching_session(p_new_court_id, p_new_start_time, p_new_end_time) then
    raise exception 'This court is reserved for a coaching session during the selected time.' using errcode = '23514';
  end if;

  price := resolve_booking_price(court.facility_sport_id, p_new_court_id, p_new_start_time, p_new_end_time, fac.timezone);

  update bookings
  set court_id = p_new_court_id,
      start_time = p_new_start_time,
      end_time = p_new_end_time,
      amount_minor = price
  where id = p_booking_id
  returning * into result;

  return result;
end;
$$;
grant execute on function reschedule_booking(uuid, uuid, timestamptz, timestamptz) to authenticated;


create or replace function get_public_court_availability(
  p_facility_id uuid,
  p_facility_sport_id uuid,
  p_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  fac facilities;
  tz text;
  result jsonb := '[]'::jsonb;
  c record;
  h integer;
  slot_start timestamptz;
  slot_end timestamptz;
  slots jsonb;
  released integer;
  guest_booked integer;
  is_available boolean;
  price integer;
begin
  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    return '[]'::jsonb;
  end if;
  tz := coalesce(fac.timezone, 'Asia/Kolkata');

  for c in
    select ct.id, ct.name
    from courts ct
    where ct.facility_id = p_facility_id
      and ct.facility_sport_id = p_facility_sport_id
      and not ct.archived
    order by ct.display_order, ct.name
  loop
    slots := '[]'::jsonb;

    for h in 0..23 loop
      slot_start := (p_date::text || ' ' || lpad(h::text, 2, '0') || ':00:00')::timestamp at time zone tz;
      slot_end := slot_start + interval '1 hour';

      continue when slot_end <= now();
      continue when not booking_window_fits_operating_hours(p_facility_id, c.id, slot_start, slot_end);

      is_available := not exists (
        select 1
        from bookings b
        where b.court_id = c.id
          and b.status in ('pending', 'confirmed')
          and tstzrange(b.start_time, b.end_time) && tstzrange(slot_start, slot_end)
      );

      if is_available and court_has_active_maintenance_block(c.id, slot_start, slot_end) then
        is_available := false;
      end if;

      if is_available and court_has_active_coaching_session(c.id, slot_start, slot_end) then
        is_available := false;
      end if;

      if is_available and court_has_active_membership_window(c.id, slot_start, slot_end, tz) then
        select
          coalesce(ms.released_capacity, 0),
          coalesce((
            select count(*)
            from membership_session_bookings msb
            where msb.session_id = ms.id
              and msb.participant_type = 'GUEST'
              and msb.status = 'CONFIRMED'
          ), 0)
        into released, guest_booked
        from membership_batches mb
        left join membership_sessions ms
          on ms.batch_id = mb.id and ms.session_date = p_date
        where mb.court_id = c.id
          and mb.status = 'ACTIVE'
          and extract(dow from (slot_start at time zone tz)) = any(mb.days_of_week)
          and mb.start_time < (slot_end at time zone tz)::time
          and mb.end_time > (slot_start at time zone tz)::time
          and mb.start_date <= p_date
          and (mb.end_date is null or mb.end_date >= p_date)
          and not exists (
            select 1 from membership_batch_blocked_dates bd
            where bd.batch_id = mb.id and bd.blocked_date = p_date
          )
        limit 1;

        is_available := coalesce(released, 0) > coalesce(guest_booked, 0);
      end if;

      price := resolve_booking_price(p_facility_sport_id, c.id, slot_start, slot_end, tz);

      slots := slots || jsonb_build_object(
        'startTime', slot_start,
        'endTime', slot_end,
        'available', is_available,
        'priceMinor', coalesce(price, 0)
      );
    end loop;

    if jsonb_array_length(slots) > 0 then
      result := result || jsonb_build_object(
        'courtId', c.id,
        'courtName', c.name,
        'slots', slots
      );
    end if;
  end loop;

  return result;
end;
$$;
grant execute on function get_public_court_availability(uuid, uuid, date) to anon, authenticated;


-- ═════════════════════════════════════════════════════════════════════════
-- Session write RPCs.
-- ═════════════════════════════════════════════════════════════════════════

-- _validate_coaching_slot — the shared conflict gate (spec §9-§13). Raises
-- on the first conflict; returns nothing on success. Caller must already
-- hold the court advisory lock.
create or replace function _validate_coaching_slot(
  p_facility_id uuid,
  p_coach_id uuid,
  p_court_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_exclude_session_id uuid default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  tz text;
  v_court courts;
begin
  select coalesce(timezone, 'Asia/Kolkata') into tz from facilities where id = p_facility_id;

  if p_end_at <= p_start_at then
    raise exception 'End time must be after start time.' using errcode = '23514';
  end if;

  select * into v_court from courts where id = p_court_id and facility_id = p_facility_id;
  if v_court.id is null then
    raise exception 'That court does not belong to this facility.' using errcode = '23503';
  end if;
  if v_court.archived or v_court.status <> 'ACTIVE' then
    raise exception 'This court is not available.' using errcode = '23514';
  end if;

  if not exists (select 1 from coaches where id = p_coach_id and facility_id = p_facility_id and status = 'ACTIVE') then
    raise exception 'That coach is not active at this facility.' using errcode = '23503';
  end if;

  if not booking_window_fits_operating_hours(p_facility_id, p_court_id, p_start_at, p_end_at) then
    raise exception 'That time is outside this court''s operating hours.' using errcode = '23514';
  end if;

  if not coach_is_available(p_coach_id, p_start_at, p_end_at) then
    raise exception 'The coach is not available during this time.' using errcode = '23514';
  end if;

  if coach_has_active_coaching_session(p_coach_id, p_start_at, p_end_at, p_exclude_session_id) then
    raise exception 'The coach already has a session during this time.' using errcode = '23514';
  end if;

  if court_has_active_coaching_session(p_court_id, p_start_at, p_end_at, p_exclude_session_id) then
    raise exception 'Another coaching session already uses this court during this time.' using errcode = '23514';
  end if;

  if court_has_overlapping_booking(p_court_id, p_start_at, p_end_at) then
    raise exception 'This court is already booked during this time.' using errcode = '23514';
  end if;

  if court_has_active_membership_window(p_court_id, p_start_at, p_end_at, tz) then
    raise exception 'This time is reserved for a membership session.' using errcode = '23514';
  end if;

  if court_has_active_maintenance_block(p_court_id, p_start_at, p_end_at) then
    raise exception 'This court is under maintenance during this time.' using errcode = '23514';
  end if;
end;
$$;


create or replace function create_coaching_session(
  p_facility_id uuid,
  p_program_id uuid,
  p_coach_id uuid,
  p_court_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_capacity integer default null,
  p_notes text default null,
  p_objective text default null,
  p_status text default 'SCHEDULED',
  p_auto_enroll boolean default true
) returns coaching_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  result coaching_sessions;
  v_program coaching_programs;
  v_capacity integer;
  v_added integer := 0;
  r record;
begin
  if not has_permission(p_facility_id, 'COACHING_CREATE_SESSION') then
    raise exception 'You don''t have permission to create coaching sessions.' using errcode = '42501';
  end if;
  if coalesce(p_status, 'SCHEDULED') not in ('SCHEDULED', 'CONFIRMED') then
    raise exception 'A session can only be created as scheduled or confirmed.' using errcode = '23514';
  end if;

  select * into v_program from coaching_programs where id = p_program_id and facility_id = p_facility_id;
  if v_program.id is null then
    raise exception 'That program does not belong to this facility.' using errcode = '23503';
  end if;
  if v_program.status <> 'ACTIVE' then
    raise exception 'That program is not active.' using errcode = '23514';
  end if;

  v_capacity := greatest(coalesce(p_capacity, v_program.default_capacity, 1), 1);

  perform pg_advisory_xact_lock(_coaching_court_lock_key(p_court_id));
  perform _validate_coaching_slot(p_facility_id, p_coach_id, p_court_id, p_start_at, p_end_at, null);

  begin
    insert into coaching_sessions (
      facility_id, program_id, coach_id, court_id, start_at, end_at, capacity, status, notes, objective, created_by
    ) values (
      p_facility_id, p_program_id, p_coach_id, p_court_id, p_start_at, p_end_at, v_capacity,
      coalesce(p_status, 'SCHEDULED'), nullif(trim(coalesce(p_notes, '')), ''), nullif(trim(coalesce(p_objective, '')), ''), auth.uid()
    ) returning * into result;
  exception when exclusion_violation then
    raise exception 'That court or coach is already booked during this time.' using errcode = '23514';
  end;

  -- Snapshot the program's active enrollments into the roster, up to
  -- capacity (spec §22 keeps program/enrollment/session distinct; this is
  -- just a convenience seed — students can be added/removed afterwards).
  if coalesce(p_auto_enroll, true) then
    for r in
      select e.id from coaching_enrollments e
      where e.program_id = p_program_id
        and e.facility_id = p_facility_id
        and e.status = 'ACTIVE'
        and e.start_date <= (p_start_at at time zone (select coalesce(timezone,'Asia/Kolkata') from facilities where id = p_facility_id))::date
        and (e.end_date is null or e.end_date >= (p_start_at at time zone (select coalesce(timezone,'Asia/Kolkata') from facilities where id = p_facility_id))::date)
      order by e.created_at
    loop
      exit when v_added >= v_capacity;
      insert into coaching_session_students (session_id, enrollment_id, facility_id, added_by)
      values (result.id, r.id, p_facility_id, auth.uid())
      on conflict do nothing;
      v_added := v_added + 1;
    end loop;
  end if;

  perform log_coaching_event(p_facility_id, 'SESSION_CREATED',
    'Session scheduled: ' || v_program.name, p_coach_id, p_program_id, result.id, null,
    jsonb_build_object('start', p_start_at, 'end', p_end_at, 'courtId', p_court_id, 'roster', v_added));
  return result;
end;
$$;

grant execute on function create_coaching_session(uuid, uuid, uuid, uuid, timestamptz, timestamptz, integer, text, text, text, boolean) to authenticated;


create or replace function reschedule_coaching_session(
  p_session_id uuid,
  p_coach_id uuid default null,
  p_court_id uuid default null,
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_capacity integer default null,
  p_notes text default null,
  p_objective text default null
) returns coaching_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  s coaching_sessions;
  result coaching_sessions;
  v_coach uuid;
  v_court uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_enrolled integer;
begin
  select * into s from coaching_sessions where id = p_session_id;
  if s.id is null then
    raise exception 'Session not found.' using errcode = 'P0002';
  end if;
  if not has_permission(s.facility_id, 'COACHING_EDIT_SESSION') then
    raise exception 'You don''t have permission to edit coaching sessions.' using errcode = '42501';
  end if;
  if s.status not in ('SCHEDULED', 'CONFIRMED') then
    raise exception 'Only a scheduled or confirmed session can be rescheduled.' using errcode = '23514';
  end if;

  v_coach := coalesce(p_coach_id, s.coach_id);
  v_court := coalesce(p_court_id, s.court_id);
  v_start := coalesce(p_start_at, s.start_at);
  v_end := coalesce(p_end_at, s.end_at);

  if p_capacity is not null then
    select count(*) into v_enrolled from coaching_session_students
      where session_id = p_session_id and status = 'ENROLLED';
    if p_capacity < v_enrolled then
      raise exception 'Capacity cannot be less than the % student(s) already on the roster.', v_enrolled using errcode = '23514';
    end if;
  end if;

  perform pg_advisory_xact_lock(_coaching_court_lock_key(v_court));
  perform _validate_coaching_slot(s.facility_id, v_coach, v_court, v_start, v_end, p_session_id);

  begin
    update coaching_sessions set
      coach_id = v_coach,
      court_id = v_court,
      start_at = v_start,
      end_at = v_end,
      capacity = coalesce(p_capacity, capacity),
      notes = coalesce(p_notes, notes),
      objective = coalesce(p_objective, objective)
    where id = p_session_id
    returning * into result;
  exception when exclusion_violation then
    raise exception 'That court or coach is already booked during this time.' using errcode = '23514';
  end;

  perform log_coaching_event(s.facility_id, 'SESSION_RESCHEDULED', 'Session rescheduled',
    result.coach_id, result.program_id, result.id, null,
    jsonb_build_object('start', v_start, 'end', v_end, 'courtId', v_court));
  return result;
end;
$$;

grant execute on function reschedule_coaching_session(uuid, uuid, uuid, timestamptz, timestamptz, integer, text, text) to authenticated;


create or replace function set_coaching_session_status(p_session_id uuid, p_status text)
returns coaching_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  s coaching_sessions;
  result coaching_sessions;
  v_event text;
begin
  select * into s from coaching_sessions where id = p_session_id;
  if s.id is null then
    raise exception 'Session not found.' using errcode = 'P0002';
  end if;
  if not has_permission(s.facility_id, 'COACHING_EDIT_SESSION') then
    raise exception 'You don''t have permission to edit coaching sessions.' using errcode = '42501';
  end if;

  -- Allowed transitions. Cancellation has its own RPC (permission + reason).
  if p_status = 'CONFIRMED' and s.status = 'SCHEDULED' then
    v_event := 'SESSION_CONFIRMED';
  elsif p_status = 'IN_PROGRESS' and s.status in ('SCHEDULED', 'CONFIRMED') then
    v_event := 'SESSION_STARTED';
  elsif p_status = 'COMPLETED' and s.status in ('CONFIRMED', 'IN_PROGRESS', 'SCHEDULED') then
    v_event := 'SESSION_COMPLETED';
  else
    raise exception 'Cannot move a % session to %.', s.status, p_status using errcode = '23514';
  end if;

  update coaching_sessions set
    status = p_status,
    completed_at = case when p_status = 'COMPLETED' then now() else completed_at end,
    completed_by = case when p_status = 'COMPLETED' then auth.uid() else completed_by end
  where id = p_session_id
  returning * into result;

  perform log_coaching_event(s.facility_id, v_event, 'Session ' || lower(replace(v_event, 'SESSION_', '')),
    result.coach_id, result.program_id, result.id);
  return result;
end;
$$;

grant execute on function set_coaching_session_status(uuid, text) to authenticated;


-- complete_coaching_session — records completion + coach notes / objective
-- result. Does NOT touch attendance for any student (spec §18 / §82).
create or replace function complete_coaching_session(
  p_session_id uuid,
  p_notes text default null,
  p_objective_result text default null
) returns coaching_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  s coaching_sessions;
  result coaching_sessions;
begin
  select * into s from coaching_sessions where id = p_session_id;
  if s.id is null then
    raise exception 'Session not found.' using errcode = 'P0002';
  end if;
  if not has_permission(s.facility_id, 'COACHING_EDIT_SESSION') then
    raise exception 'You don''t have permission to edit coaching sessions.' using errcode = '42501';
  end if;
  if s.status in ('COMPLETED', 'CANCELLED') then
    raise exception 'This session is already %.', lower(s.status) using errcode = '23514';
  end if;

  update coaching_sessions set
    status = 'COMPLETED',
    completed_at = now(),
    completed_by = auth.uid(),
    notes = coalesce(nullif(trim(coalesce(p_notes, '')), ''), notes),
    objective_result = coalesce(nullif(trim(coalesce(p_objective_result, '')), ''), objective_result)
  where id = p_session_id
  returning * into result;

  perform log_coaching_event(s.facility_id, 'SESSION_COMPLETED', 'Session completed',
    result.coach_id, result.program_id, result.id);
  return result;
end;
$$;

grant execute on function complete_coaching_session(uuid, text, text) to authenticated;


create or replace function cancel_coaching_session(p_session_id uuid, p_reason text)
returns coaching_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  s coaching_sessions;
  result coaching_sessions;
begin
  select * into s from coaching_sessions where id = p_session_id;
  if s.id is null then
    raise exception 'Session not found.' using errcode = 'P0002';
  end if;
  if not has_permission(s.facility_id, 'COACHING_CANCEL_SESSION') then
    raise exception 'You don''t have permission to cancel coaching sessions.' using errcode = '42501';
  end if;
  if s.status in ('COMPLETED', 'CANCELLED') then
    raise exception 'This session is already %.', lower(s.status) using errcode = '23514';
  end if;
  if trim(coalesce(p_reason, '')) = '' then
    raise exception 'A cancellation reason is required.' using errcode = '23514';
  end if;

  update coaching_sessions set
    status = 'CANCELLED',
    cancelled_at = now(),
    cancel_reason = trim(p_reason)
  where id = p_session_id
  returning * into result;

  perform log_coaching_event(s.facility_id, 'SESSION_CANCELLED',
    'Session cancelled: ' || trim(p_reason), result.coach_id, result.program_id, result.id);
  return result;
end;
$$;

grant execute on function cancel_coaching_session(uuid, text) to authenticated;

-- add_session_student / remove_session_student live in 0084 (they return /
-- reference coaching_session_students, created there).
