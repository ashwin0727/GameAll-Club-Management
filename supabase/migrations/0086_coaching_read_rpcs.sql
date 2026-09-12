-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching read RPCs — everything the web and Flutter UIs render, plus the
-- coaching analytics the Reports page consumes (spec §29 / §35: Reports is a
-- read layer over the authoritative sources — sessions, enrollments,
-- payments — never a second store).
--
-- Every RPC is facility-scoped (has_permission COACHING_VIEW) and paginates
-- / aggregates server-side (spec §70).
-- ═══════════════════════════════════════════════════════════════════════════


-- The current local calendar month as a UTC instant range, for "this month"
-- KPIs over the facility timezone.
create or replace function _coaching_month_range(p_facility_id uuid)
returns tstzrange
language plpgsql stable
set search_path = public
as $$
declare
  tz text := coalesce((select timezone from facilities where id = p_facility_id), 'Asia/Kolkata');
  local_month_start timestamp := date_trunc('month', now() at time zone tz);
begin
  return tstzrange(
    local_month_start at time zone tz,
    (local_month_start + interval '1 month') at time zone tz
  );
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- get_coaching_overview — the dashboard (spec §1).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_coaching_overview(p_facility_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  tz text;
  month_ tstzrange;
  result jsonb;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  tz := coalesce((select timezone from facilities where id = p_facility_id), 'Asia/Kolkata');
  month_ := _coaching_month_range(p_facility_id);

  result := jsonb_build_object(
    'kpis', jsonb_build_object(
      'activeStudents', (
        select count(distinct e.member_id) from coaching_enrollments e
        where e.facility_id = p_facility_id and e.status = 'ACTIVE'
      ),
      'activePrograms', (
        select count(*) from coaching_programs where facility_id = p_facility_id and status = 'ACTIVE'
      ),
      'activeCoaches', (
        select count(*) from coaches where facility_id = p_facility_id and status = 'ACTIVE'
      ),
      'coachesOnLeave', (
        select count(*) from coaches where facility_id = p_facility_id and status = 'ON_LEAVE'
      ),
      'sessionsThisMonth', (
        select count(*) from coaching_sessions cs
        where cs.facility_id = p_facility_id and cs.status <> 'CANCELLED' and month_ @> cs.start_at
      ),
      'upcomingSessions', (
        select count(*) from coaching_sessions cs
        where cs.facility_id = p_facility_id and cs.status in ('SCHEDULED', 'CONFIRMED') and cs.start_at >= now()
      ),
      'revenueThisMonthMinor', (
        select coalesce(sum(p.amount_inr) * 100, 0)::bigint from payments p
        where p.facility_id = p_facility_id and p.status = 'paid'
          and p.coaching_enrollment_id is not null
          and month_ @> coalesce(p.paid_at, p.created_at)
      )
    ),
    'upcomingSessions', coalesce((
      select jsonb_agg(row) from (
        select jsonb_build_object(
          'id', cs.id,
          'startAt', cs.start_at,
          'endAt', cs.end_at,
          'programName', cp.name,
          'coachName', pr.full_name,
          'courtName', c.name,
          'enrolled', (select count(*) from coaching_session_students css where css.session_id = cs.id and css.status = 'ENROLLED'),
          'capacity', cs.capacity,
          'status', cs.status
        ) as row
        from coaching_sessions cs
        join coaching_programs cp on cp.id = cs.program_id
        join coaches co on co.id = cs.coach_id
        join profiles pr on pr.id = co.user_id
        join courts c on c.id = cs.court_id
        where cs.facility_id = p_facility_id
          and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS')
          and cs.end_at >= now()
        order by cs.start_at
        limit 8
      ) s
    ), '[]'::jsonb),
    'activePrograms', coalesce((
      select jsonb_agg(row) from (
        select jsonb_build_object(
          'id', cp.id,
          'name', cp.name,
          'level', cp.level,
          'studentCount', (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE'),
          'sessionCount', (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status <> 'CANCELLED' and month_ @> cs.start_at),
          'status', cp.status
        ) as row
        from coaching_programs cp
        where cp.facility_id = p_facility_id and cp.status = 'ACTIVE'
        order by (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE') desc, cp.name
        limit 6
      ) s
    ), '[]'::jsonb),
    'studentsByProgram', coalesce((
      select jsonb_agg(row) from (
        select jsonb_build_object(
          'programId', cp.id,
          'programName', cp.name,
          'students', count(e.id)
        ) as row
        from coaching_programs cp
        left join coaching_enrollments e on e.program_id = cp.id and e.status = 'ACTIVE'
        where cp.facility_id = p_facility_id and cp.status = 'ACTIVE'
        group by cp.id, cp.name
        having count(e.id) > 0
        order by count(e.id) desc
      ) s
    ), '[]'::jsonb),
    'studentGrowth', coalesce((
      select jsonb_agg(row order by (row->>'month')) from (
        select jsonb_build_object(
          'month', to_char(gs.m, 'Mon'),
          'monthKey', to_char(gs.m, 'YYYY-MM'),
          'students', (
            select count(distinct e.member_id) from coaching_enrollments e
            where e.facility_id = p_facility_id
              and e.start_date <= (gs.m + interval '1 month' - interval '1 day')::date
              and (e.end_date is null or e.end_date >= gs.m::date)
              and e.status <> 'CANCELLED'
          )
        ) as row
        from generate_series(
          date_trunc('month', (now() at time zone tz)) - interval '5 months',
          date_trunc('month', (now() at time zone tz)),
          interval '1 month'
        ) as gs(m)
      ) s
    ), '[]'::jsonb),
    'recentEnrollments', coalesce((
      select jsonb_agg(row) from (
        select jsonb_build_object(
          'id', e.id,
          'studentName', m.full_name,
          'programName', cp.name,
          'enrolledAt', e.created_at,
          'status', e.status
        ) as row
        from coaching_enrollments e
        join members m on m.id = e.member_id
        join coaching_programs cp on cp.id = e.program_id
        where e.facility_id = p_facility_id
        order by e.created_at desc
        limit 6
      ) s
    ), '[]'::jsonb)
  );

  return result;
end;
$$;

grant execute on function get_coaching_overview(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Coaches.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_coaches(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,
  p_specialization text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  user_id uuid,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  specialization text,
  experience_years numeric,
  status text,
  program_count bigint,
  session_count bigint,
  student_count bigint,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare month_ tstzrange;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  month_ := _coaching_month_range(p_facility_id);

  return query
  select
    co.id, co.user_id, pr.full_name, pr.email, pr.phone, pr.avatar_url,
    co.specialization, co.experience_years, co.status,
    (select count(distinct cs.program_id) from coaching_sessions cs where cs.coach_id = co.id and cs.status <> 'CANCELLED')::bigint,
    (select count(*) from coaching_sessions cs where cs.coach_id = co.id and cs.status <> 'CANCELLED' and month_ @> cs.start_at)::bigint,
    (select count(distinct e.member_id) from coaching_enrollments e where e.coach_id = co.id and e.status = 'ACTIVE')::bigint,
    count(*) over ()::bigint
  from coaches co
  join profiles pr on pr.id = co.user_id
  where co.facility_id = p_facility_id
    and (p_status is null or co.status = p_status)
    and (p_specialization is null or co.specialization ilike '%' || p_specialization || '%')
    and (
      p_search is null or trim(p_search) = ''
      or pr.full_name ilike '%' || trim(p_search) || '%'
      or pr.email ilike '%' || trim(p_search) || '%'
      or pr.phone ilike '%' || trim(p_search) || '%'
    )
  order by pr.full_name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_coaches(uuid, text, text, text, integer, integer) to authenticated;


create or replace function get_coach(p_coach_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  co coaches;
  tz text;
  month_ tstzrange;
begin
  select * into co from coaches where id = p_coach_id;
  if co.id is null then
    raise exception 'Coach not found.' using errcode = 'P0002';
  end if;
  if not has_permission(co.facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  tz := coalesce((select timezone from facilities where id = co.facility_id), 'Asia/Kolkata');
  month_ := _coaching_month_range(co.facility_id);

  return (
    select jsonb_build_object(
      'id', co.id,
      'userId', co.user_id,
      'fullName', pr.full_name,
      'email', pr.email,
      'phone', pr.phone,
      'avatarUrl', pr.avatar_url,
      'specialization', co.specialization,
      'experienceYears', co.experience_years,
      'certifications', co.certifications,
      'bio', co.bio,
      'hourlyRateMinor', co.hourly_rate_minor,
      'status', co.status,
      'joinedOn', co.joined_on,
      'title', (select title from facility_users fu where fu.facility_id = co.facility_id and fu.user_id = co.user_id),
      'stats', jsonb_build_object(
        'sessionsThisMonth', (select count(*) from coaching_sessions cs where cs.coach_id = co.id and cs.status <> 'CANCELLED' and month_ @> cs.start_at),
        'activeStudents', (select count(distinct e.member_id) from coaching_enrollments e where e.coach_id = co.id and e.status = 'ACTIVE'),
        'programs', (select count(distinct cs.program_id) from coaching_sessions cs where cs.coach_id = co.id and cs.status <> 'CANCELLED')
      ),
      'todaySchedule', coalesce((
        select jsonb_agg(row order by (row->>'startAt')) from (
          select jsonb_build_object(
            'id', cs.id, 'startAt', cs.start_at, 'endAt', cs.end_at,
            'programName', cp.name, 'courtName', c.name, 'status', cs.status
          ) as row
          from coaching_sessions cs
          join coaching_programs cp on cp.id = cs.program_id
          join courts c on c.id = cs.court_id
          where cs.coach_id = co.id
            and cs.status <> 'CANCELLED'
            and (cs.start_at at time zone tz)::date = (now() at time zone tz)::date
        ) s
      ), '[]'::jsonb),
      'programs', coalesce((
        select jsonb_agg(distinct jsonb_build_object('id', cp.id, 'name', cp.name, 'level', cp.level))
        from coaching_sessions cs join coaching_programs cp on cp.id = cs.program_id
        where cs.coach_id = co.id and cs.status <> 'CANCELLED'
      ), '[]'::jsonb),
      'students', coalesce((
        select jsonb_agg(jsonb_build_object(
          'enrollmentId', e.id, 'memberId', e.member_id, 'name', m.full_name,
          'programName', cp.name, 'status', e.status
        ))
        from coaching_enrollments e
        join members m on m.id = e.member_id
        join coaching_programs cp on cp.id = e.program_id
        where e.coach_id = co.id and e.status = 'ACTIVE'
      ), '[]'::jsonb),
      'availability', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', ca.id, 'dayOfWeek', ca.day_of_week, 'startTime', ca.start_time, 'endTime', ca.end_time
        ) order by ca.day_of_week, ca.start_time)
        from coach_availability ca where ca.coach_id = co.id
      ), '[]'::jsonb),
      'availabilityExceptions', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', ce.id, 'date', ce.exception_date, 'isAvailable', ce.is_available,
          'startTime', ce.start_time, 'endTime', ce.end_time, 'reason', ce.reason
        ) order by ce.exception_date)
        from coach_availability_exceptions ce
        where ce.coach_id = co.id and ce.exception_date >= (now() at time zone tz)::date
      ), '[]'::jsonb)
    )
    from profiles pr where pr.id = co.user_id
  );
end;
$$;

grant execute on function get_coach(uuid) to authenticated;


-- Active staff members who don't yet have a coaching profile — the Add Coach
-- picker (spec §3: select an existing staff member, never a new account).
create or replace function list_coach_candidates(p_facility_id uuid)
returns table (user_id uuid, full_name text, email text, title text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_permission(p_facility_id, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;
  return query
  select fu.user_id, pr.full_name, pr.email, fu.title
  from facility_users fu
  join profiles pr on pr.id = fu.user_id
  where fu.facility_id = p_facility_id
    and fu.status = 'ACTIVE'
    and not exists (select 1 from coaches c where c.facility_id = p_facility_id and c.user_id = fu.user_id)
  order by pr.full_name;
end;
$$;

grant execute on function list_coach_candidates(uuid) to authenticated;


create or replace function list_coach_options(p_facility_id uuid)
returns table (id uuid, name text, specialization text)
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
  select c.id, pr.full_name, c.specialization
  from coaches c join profiles pr on pr.id = c.user_id
  where c.facility_id = p_facility_id and c.status = 'ACTIVE'
  order by pr.full_name;
end;
$$;

grant execute on function list_coach_options(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Programs.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_coaching_programs(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  name text,
  level text,
  age_group text,
  category text,
  default_duration_minutes integer,
  default_capacity integer,
  session_count integer,
  default_price_minor integer,
  is_membership_included boolean,
  status text,
  student_count bigint,
  scheduled_session_count bigint,
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
    cp.id, cp.name, cp.level, cp.age_group, cp.category,
    cp.default_duration_minutes, cp.default_capacity, cp.session_count,
    cp.default_price_minor, cp.is_membership_included, cp.status,
    (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')::bigint,
    (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status <> 'CANCELLED')::bigint,
    count(*) over ()::bigint
  from coaching_programs cp
  where cp.facility_id = p_facility_id
    and (p_status is null or cp.status = p_status)
    and (p_search is null or trim(p_search) = '' or cp.name ilike '%' || trim(p_search) || '%')
  order by cp.status, cp.name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_coaching_programs(uuid, text, text, integer, integer) to authenticated;


create or replace function get_coaching_program(p_program_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare cp coaching_programs;
begin
  select * into cp from coaching_programs where id = p_program_id;
  if cp.id is null then
    raise exception 'Program not found.' using errcode = 'P0002';
  end if;
  if not has_permission(cp.facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'id', cp.id, 'facilityId', cp.facility_id, 'name', cp.name, 'level', cp.level,
    'ageGroup', cp.age_group, 'category', cp.category, 'description', cp.description,
    'facilitySportId', cp.facility_sport_id,
    'defaultDurationMinutes', cp.default_duration_minutes, 'defaultCapacity', cp.default_capacity,
    'sessionCount', cp.session_count, 'defaultPriceMinor', cp.default_price_minor,
    'isMembershipIncluded', cp.is_membership_included, 'status', cp.status,
    'createdAt', cp.created_at,
    'stats', jsonb_build_object(
      'activeStudents', (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE'),
      'totalEnrollments', (select count(*) from coaching_enrollments e where e.program_id = cp.id),
      'scheduledSessions', (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status in ('SCHEDULED','CONFIRMED')),
      'completedSessions', (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status = 'COMPLETED')
    )
  );
end;
$$;

grant execute on function get_coaching_program(uuid) to authenticated;


create or replace function list_coaching_program_options(p_facility_id uuid)
returns table (id uuid, name text, default_capacity integer, default_duration_minutes integer, default_price_minor integer, is_membership_included boolean, session_count integer)
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
  select cp.id, cp.name, cp.default_capacity, cp.default_duration_minutes,
         cp.default_price_minor, cp.is_membership_included, cp.session_count
  from coaching_programs cp
  where cp.facility_id = p_facility_id and cp.status = 'ACTIVE'
  order by cp.name;
end;
$$;

grant execute on function list_coaching_program_options(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Sessions / schedule.
-- ─────────────────────────────────────────────────────────────────────────
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
    cs.id, cs.program_id, cp.name, cs.coach_id, pr.full_name, cs.court_id, c.name,
    cs.start_at, cs.end_at, cs.capacity,
    (select count(*) from coaching_session_students css where css.session_id = cs.id and css.status = 'ENROLLED')::bigint,
    cs.status,
    count(*) over ()::bigint
  from coaching_sessions cs
  join coaching_programs cp on cp.id = cs.program_id
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
      'programName', cp.name,
      'programLevel', cp.level,
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
    from coaching_programs cp, coaches co, profiles pr, courts c
    where cp.id = cs.program_id and co.id = cs.coach_id and pr.id = co.user_id and c.id = cs.court_id
  );
end;
$$;

grant execute on function get_coaching_session(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Enrollments.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_coaching_enrollments(
  p_facility_id uuid,
  p_search text default null,
  p_program_id uuid default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  member_id uuid,
  student_name text,
  student_phone text,
  program_id uuid,
  program_name text,
  coach_name text,
  start_date date,
  end_date date,
  sessions_total integer,
  price_minor integer,
  paid_minor bigint,
  status text,
  payment_status text,
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
  with rows as (
    select
      e.id, e.member_id, m.full_name as student_name, m.phone as student_phone,
      e.program_id, cp.name as program_name, pr.full_name as coach_name,
      e.start_date, e.end_date, e.sessions_total, e.price_minor,
      coalesce((select sum(p.amount_inr) * 100 from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid'), 0)::bigint as paid_minor,
      e.status
    from coaching_enrollments e
    join members m on m.id = e.member_id
    join coaching_programs cp on cp.id = e.program_id
    left join coaches co on co.id = e.coach_id
    left join profiles pr on pr.id = co.user_id
    where e.facility_id = p_facility_id
      and (p_program_id is null or e.program_id = p_program_id)
      and (p_status is null or e.status = p_status)
      and (
        p_search is null or trim(p_search) = ''
        or m.full_name ilike '%' || trim(p_search) || '%'
        or m.phone ilike '%' || trim(p_search) || '%'
      )
  )
  select
    r.*,
    case
      when r.price_minor = 0 then 'INCLUDED'
      when r.paid_minor >= r.price_minor then 'PAID'
      when r.paid_minor > 0 then 'PARTIAL'
      else 'PENDING'
    end as payment_status,
    count(*) over ()::bigint as total_count
  from rows r
  order by r.start_date desc, r.student_name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_coaching_enrollments(uuid, text, uuid, text, integer, integer) to authenticated;


create or replace function get_coaching_enrollment(p_enrollment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  e coaching_enrollments;
  v_can_progress boolean;
  v_paid bigint;
begin
  select * into e from coaching_enrollments where id = p_enrollment_id;
  if e.id is null then
    raise exception 'Enrollment not found.' using errcode = 'P0002';
  end if;
  if not has_permission(e.facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  v_can_progress := has_permission(e.facility_id, 'COACHING_VIEW_PROGRESS');
  select coalesce(sum(p.amount_inr) * 100, 0)::bigint into v_paid
    from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid';

  return (
      jsonb_build_object(
      'id', e.id,
      'facilityId', e.facility_id,
      'memberId', e.member_id,
      'studentName', (select full_name from members where id = e.member_id),
      'studentPhone', (select phone from members where id = e.member_id),
      'studentEmail', (select email from members where id = e.member_id),
      'programId', e.program_id,
      'programName', (select name from coaching_programs where id = e.program_id),
      'programLevel', (select level from coaching_programs where id = e.program_id),
      'coachId', e.coach_id,
      'coachName', (select pr.full_name from coaches co join profiles pr on pr.id = co.user_id where co.id = e.coach_id),
      'startDate', e.start_date,
      'endDate', e.end_date,
      'sessionsTotal', e.sessions_total,
      'priceMinor', e.price_minor,
      'paidMinor', v_paid,
      'outstandingMinor', greatest(e.price_minor - v_paid, 0),
      'pricingType', e.pricing_type,
      'status', e.status,
      'notes', e.notes,
      'cancelReason', e.cancel_reason,
      'createdAt', e.created_at,
      'sessions', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', cs.id, 'startAt', cs.start_at, 'endAt', cs.end_at,
          'programName', cp2.name, 'courtName', c.name, 'status', cs.status
        ) order by cs.start_at desc)
        from coaching_session_students css
        join coaching_sessions cs on cs.id = css.session_id
        join coaching_programs cp2 on cp2.id = cs.program_id
        join courts c on c.id = cs.court_id
        where css.enrollment_id = e.id and css.status = 'ENROLLED'
      ), '[]'::jsonb),
      'payments', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', p.id, 'amountMinor', (p.amount_inr * 100), 'paidAt', coalesce(p.paid_at, p.created_at),
          'method', p.payment_method, 'reference', p.reference
        ) order by coalesce(p.paid_at, p.created_at) desc)
        from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid'
      ), '[]'::jsonb),
      'progressNotes', case when v_can_progress then coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', spn.id, 'skillOrGoal', spn.skill_or_goal, 'note', spn.note,
          'progressStatus', spn.progress_status, 'coachName', cpr.full_name,
          'sessionId', spn.session_id, 'createdAt', spn.created_at
        ) order by spn.created_at desc)
        from student_progress_notes spn
        left join coaches sco on sco.id = spn.coach_id
        left join profiles cpr on cpr.id = sco.user_id
        where spn.enrollment_id = e.id
      ), '[]'::jsonb) else null end
    )
  );
end;
$$;

grant execute on function get_coaching_enrollment(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_coaching_reports — the analytics the Reports page renders (spec §29 /
-- §35). Read-only aggregation over sessions / enrollments / payments /
-- coach availability. Attendance is never a metric (spec §30 / §31).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_coaching_reports(
  p_facility_id uuid,
  p_preset text default null,
  p_start_date date default null,
  p_end_date date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  range_ tstzrange;
  tz text;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, coalesce(p_preset, 'THIS_MONTH'), p_start_date, p_end_date);
  tz := coalesce((select timezone from facilities where id = p_facility_id), 'Asia/Kolkata');

  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'activeStudents', (select count(distinct e.member_id) from coaching_enrollments e where e.facility_id = p_facility_id and e.status = 'ACTIVE'),
      'activePrograms', (select count(*) from coaching_programs where facility_id = p_facility_id and status = 'ACTIVE'),
      'sessionsInRange', (select count(*) from coaching_sessions cs where cs.facility_id = p_facility_id and cs.status <> 'CANCELLED' and range_ @> cs.start_at),
      'completedSessionsInRange', (select count(*) from coaching_sessions cs where cs.facility_id = p_facility_id and cs.status = 'COMPLETED' and range_ @> cs.start_at),
      'coachingRevenueMinor', (
        select coalesce(sum(p.amount_inr) * 100, 0)::bigint from payments p
        where p.facility_id = p_facility_id and p.status = 'paid'
          and p.coaching_enrollment_id is not null and range_ @> coalesce(p.paid_at, p.created_at)
      ),
      'avgCapacityUtilization', (
        select coalesce(round(avg(
          case when cs.capacity > 0
            then 100.0 * (select count(*) from coaching_session_students css where css.session_id = cs.id and css.status = 'ENROLLED') / cs.capacity
            else 0 end
        ), 1), 0)
        from coaching_sessions cs
        where cs.facility_id = p_facility_id and cs.status <> 'CANCELLED' and range_ @> cs.start_at
      )
    ),
    'programPerformance', coalesce((
      select jsonb_agg(row) from (
        select jsonb_build_object(
          'programId', cp.id,
          'programName', cp.name,
          'activeStudents', (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE'),
          'sessions', (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status <> 'CANCELLED' and range_ @> cs.start_at),
          'capacityUtilization', (
            select coalesce(round(avg(
              case when cs.capacity > 0
                then 100.0 * (select count(*) from coaching_session_students css where css.session_id = cs.id and css.status = 'ENROLLED') / cs.capacity
                else 0 end), 1), 0)
            from coaching_sessions cs where cs.program_id = cp.id and cs.status <> 'CANCELLED' and range_ @> cs.start_at
          ),
          'revenueMinor', (
            select coalesce(sum(p.amount_inr) * 100, 0)::bigint from payments p
            join coaching_enrollments e on e.id = p.coaching_enrollment_id
            where e.program_id = cp.id and p.status = 'paid' and range_ @> coalesce(p.paid_at, p.created_at)
          )
        ) as row
        from coaching_programs cp
        where cp.facility_id = p_facility_id
        order by (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE') desc
      ) s
    ), '[]'::jsonb),
    'coachUtilization', coalesce((
      select jsonb_agg(row) from (
        select jsonb_build_object(
          'coachId', co.id,
          'coachName', pr.full_name,
          -- Scheduled coaching hours in range.
          'scheduledHours', coalesce(round((
            select sum(extract(epoch from (cs.end_at - cs.start_at)) / 3600.0)
            from coaching_sessions cs
            where cs.coach_id = co.id and cs.status <> 'CANCELLED' and range_ @> cs.start_at
          )::numeric, 1), 0),
          -- Weekly recurring available hours (spec §30: from availability, not attendance).
          'weeklyAvailableHours', coalesce(round((
            select sum(extract(epoch from (ca.end_time - ca.start_time)) / 3600.0)
            from coach_availability ca where ca.coach_id = co.id
          )::numeric, 1), 0),
          'sessions', (select count(*) from coaching_sessions cs where cs.coach_id = co.id and cs.status <> 'CANCELLED' and range_ @> cs.start_at)
        ) as row
        from coaches co join profiles pr on pr.id = co.user_id
        where co.facility_id = p_facility_id and co.status = 'ACTIVE'
        order by pr.full_name
      ) s
    ), '[]'::jsonb),
    'studentGrowth', coalesce((
      select jsonb_agg(row order by (row->>'monthKey')) from (
        select jsonb_build_object(
          'month', to_char(gs.m, 'Mon'),
          'monthKey', to_char(gs.m, 'YYYY-MM'),
          'students', (
            select count(distinct e.member_id) from coaching_enrollments e
            where e.facility_id = p_facility_id
              and e.start_date <= (gs.m + interval '1 month' - interval '1 day')::date
              and (e.end_date is null or e.end_date >= gs.m::date)
              and e.status <> 'CANCELLED'
          )
        ) as row
        from generate_series(
          date_trunc('month', (now() at time zone tz)) - interval '5 months',
          date_trunc('month', (now() at time zone tz)),
          interval '1 month'
        ) as gs(m)
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function get_coaching_reports(uuid, text, date, date) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Audit read (spec §56) — the coaching activity feed.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_coaching_events(
  p_facility_id uuid,
  p_event text default null,
  p_limit integer default 30,
  p_offset integer default 0
)
returns table (
  id uuid, event text, summary text, actor_name text, detail jsonb, created_at timestamptz, total_count bigint
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
  select ev.id, ev.event, ev.summary, ap.full_name, ev.detail, ev.created_at, count(*) over ()::bigint
  from coaching_events ev
  left join profiles ap on ap.id = ev.actor
  where ev.facility_id = p_facility_id
    and (p_event is null or ev.event = p_event)
  order by ev.created_at desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_coaching_events(uuid, text, integer, integer) to authenticated;
