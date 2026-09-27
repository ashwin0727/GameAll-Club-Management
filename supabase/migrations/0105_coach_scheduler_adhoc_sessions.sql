-- ═══════════════════════════════════════════════════════════════════════════
-- Coach Scheduler — the "Schedule Coaching Session" page's redesign turns the
-- existing program-only session wizard into a coach-first, directly
-- member-bookable session (sport/session type/level/title/description/price/
-- visibility), matching the reference design. This does NOT introduce a new
-- scheduling, availability, booking or calendar engine — it only lets
-- coaching_sessions exist without a coaching_programs parent, and carries the
-- handful of new display/booking fields the design needs. Every conflict
-- check (coach availability, court availability, operating hours, membership
-- protection, maintenance) already lives in _validate_coaching_slot and is
-- reused unchanged.
-- ═══════════════════════════════════════════════════════════════════════════

alter table coaching_sessions alter column program_id drop not null;
alter table coaching_sessions add column if not exists title text;
alter table coaching_sessions add column if not exists description text;
alter table coaching_sessions add column if not exists level text;
alter table coaching_sessions add column if not exists facility_sport_id uuid references facility_sports (id) on delete set null;
alter table coaching_sessions add column if not exists session_type text not null default 'GROUP'
  check (session_type in ('GROUP', 'ONE_ON_ONE', 'TRIAL'));
alter table coaching_sessions add column if not exists price_per_student_minor integer check (price_per_student_minor is null or price_per_student_minor >= 0);
alter table coaching_sessions add column if not exists visible_for_booking boolean not null default true;
alter table coaching_sessions add column if not exists send_notification boolean not null default true;
alter table coaching_sessions add column if not exists allow_waitlist boolean not null default false;

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
  p_auto_enroll boolean default true,
  p_title text default null,
  p_description text default null,
  p_level text default null,
  p_facility_sport_id uuid default null,
  p_session_type text default 'GROUP',
  p_price_per_student_minor integer default null,
  p_visible_for_booking boolean default true,
  p_send_notification boolean default true,
  p_allow_waitlist boolean default false
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
  if coalesce(p_session_type, 'GROUP') not in ('GROUP', 'ONE_ON_ONE', 'TRIAL') then
    raise exception 'Unknown session type.' using errcode = '22023';
  end if;

  -- A coach-scheduled session is standalone (no program) unless one is explicitly given —
  -- the design's "Schedule Coaching Session" flow never selects a program at all.
  if p_program_id is not null then
    select * into v_program from coaching_programs where id = p_program_id and facility_id = p_facility_id;
    if v_program.id is null then
      raise exception 'That program does not belong to this facility.' using errcode = '23503';
    end if;
    if v_program.status <> 'ACTIVE' then
      raise exception 'That program is not active.' using errcode = '23514';
    end if;
  end if;

  v_capacity := greatest(coalesce(p_capacity, v_program.default_capacity, 1), 1);

  perform pg_advisory_xact_lock(_coaching_court_lock_key(p_court_id));
  perform _validate_coaching_slot(p_facility_id, p_coach_id, p_court_id, p_start_at, p_end_at, null);

  begin
    insert into coaching_sessions (
      facility_id, program_id, coach_id, court_id, start_at, end_at, capacity, status, notes, objective, created_by,
      title, description, level, facility_sport_id, session_type, price_per_student_minor,
      visible_for_booking, send_notification, allow_waitlist
    ) values (
      p_facility_id, p_program_id, p_coach_id, p_court_id, p_start_at, p_end_at, v_capacity,
      coalesce(p_status, 'SCHEDULED'), nullif(trim(coalesce(p_notes, '')), ''), nullif(trim(coalesce(p_objective, '')), ''), auth.uid(),
      nullif(trim(coalesce(p_title, '')), ''), nullif(trim(coalesce(p_description, '')), ''), nullif(trim(coalesce(p_level, '')), ''),
      p_facility_sport_id, coalesce(p_session_type, 'GROUP'), p_price_per_student_minor,
      coalesce(p_visible_for_booking, true), coalesce(p_send_notification, true), coalesce(p_allow_waitlist, false)
    ) returning * into result;
  exception when exclusion_violation then
    raise exception 'That court or coach is already booked during this time.' using errcode = '23514';
  end;

  -- Snapshot the program's active enrollments into the roster, up to capacity — only meaningful
  -- when this session actually belongs to a program.
  if p_program_id is not null and coalesce(p_auto_enroll, true) then
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
    'Session scheduled: ' || coalesce(v_program.name, result.title, 'Coaching session'), p_coach_id, p_program_id, result.id, null,
    jsonb_build_object('start', p_start_at, 'end', p_end_at, 'courtId', p_court_id, 'roster', v_added));
  return result;
end;
$$;

grant execute on function create_coaching_session(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, integer, text, text, text, boolean,
  text, text, text, uuid, text, integer, boolean, boolean, boolean
) to authenticated;

-- list_coaching_sessions' output gains session_type; program is now an optional left join.
drop function if exists list_coaching_sessions(uuid, timestamptz, timestamptz, uuid, uuid, uuid, text, integer, integer);

create or replace function list_coaching_sessions(
  p_facility_id uuid,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_coach_id uuid default null,
  p_program_id uuid default null,
  p_court_id uuid default null,
  p_status text default null,
  p_limit integer default 200,
  p_offset integer default 0
)
returns table (
  id uuid,
  program_id uuid,
  program_name text,
  coach_id uuid,
  coach_name text,
  court_id uuid,
  court_name text,
  start_at timestamptz,
  end_at timestamptz,
  capacity integer,
  enrolled_count bigint,
  status text,
  session_type text,
  total_count bigint
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
    cs.id, cs.program_id, coalesce(cp.name, cs.title, 'Coaching Session'), cs.coach_id, pr.full_name, cs.court_id, c.name,
    cs.start_at, cs.end_at, cs.capacity,
    (select count(*) from coaching_session_students css where css.session_id = cs.id and css.status = 'ENROLLED')::bigint,
    cs.status, cs.session_type,
    count(*) over ()::bigint
  from coaching_sessions cs
  left join coaching_programs cp on cp.id = cs.program_id
  join coaches co on co.id = cs.coach_id
  join profiles pr on pr.id = co.user_id
  join courts c on c.id = cs.court_id
  where cs.facility_id = p_facility_id
    and (p_from is null or cs.end_at >= p_from)
    and (p_to is null or cs.start_at < p_to)
    and (p_coach_id is null or cs.coach_id = p_coach_id)
    and (p_program_id is null or cs.program_id = p_program_id)
    and (p_court_id is null or cs.court_id = p_court_id)
    and (p_status is null or cs.status = p_status)
  order by cs.start_at
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_coaching_sessions(uuid, timestamptz, timestamptz, uuid, uuid, uuid, text, integer, integer) to authenticated;

create or replace function get_coaching_session(p_session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cs coaching_sessions;
  v_can_progress boolean;
begin
  select * into cs from coaching_sessions where id = p_session_id;
  if cs.id is null then
    raise exception 'Session not found.' using errcode = 'P0002';
  end if;
  if not has_permission(cs.facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  v_can_progress := has_permission(cs.facility_id, 'COACHING_VIEW_PROGRESS');

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
