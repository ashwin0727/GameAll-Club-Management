-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching follows the top bar's sport selection.
--
-- Every coaching read function gains an optional list of sports (p_facility_sport_ids): null is All Sports (nothing is
-- filtered — exactly the old behaviour), a list narrows every figure and row to those sports. What "belongs to a
-- sport" means for each kind of record:
--   program      its own facility_sport_id
--   enrollment   its program's sport (so students, their payments and their fees follow the program)
--   session      the sport of the court it is held on
--   coach        a sport the coach is set up to coach (coach_sports)
-- The four helpers below say that once; the functions use them.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function coaching_sport_ok_program(p_program_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null or exists (
    select 1 from coaching_programs x where x.id = p_program_id and x.facility_sport_id = any (p_sports)
  )
$$;

create or replace function coaching_sport_ok_enrollment(p_enrollment_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null or exists (
    select 1 from coaching_enrollments e join coaching_programs x on x.id = e.program_id
    where e.id = p_enrollment_id and x.facility_sport_id = any (p_sports)
  )
$$;

create or replace function coaching_sport_ok_court(p_court_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null or exists (
    select 1 from courts c where c.id = p_court_id and c.facility_sport_id = any (p_sports)
  )
$$;

create or replace function coaching_sport_ok_coach(p_coach_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null or exists (
    select 1 from coach_sports cst where cst.coach_id = p_coach_id and cst.facility_sport_id = any (p_sports)
  )
$$;

drop function if exists _get_coaching_overview_base(uuid);
drop function if exists get_coaching_overview(uuid);
drop function if exists get_coaching_insights(uuid, integer);
drop function if exists get_coaching_card_stats(uuid);
drop function if exists get_coaching_reports(uuid, text, date, date);
drop function if exists list_coaches(uuid, text, text, text, integer, integer, uuid, text);
drop function if exists list_coaching_programs(uuid, text, text, integer, integer, uuid, text, text);
drop function if exists get_program_insights(uuid);
drop function if exists get_program_card_stats(uuid);
drop function if exists get_student_card_stats(uuid);
drop function if exists list_coaching_sessions(uuid, timestamptz, timestamptz, uuid, uuid, uuid, text, integer, integer);
drop function if exists list_coaching_enrollments(uuid, text, uuid, text, integer, integer, uuid, text);
drop function if exists list_active_coaching_batches_with_students(uuid);
drop function if exists get_coaching_total_revenue(uuid);

-- ── _get_coaching_overview_base
create or replace function _get_coaching_overview_base(p_facility_id uuid, p_facility_sport_ids uuid[] default null)
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
        where e.facility_id = p_facility_id and coaching_sport_ok_program(e.program_id, p_facility_sport_ids) and e.status = 'ACTIVE'
      ),
      'activePrograms', (
        select count(*) from coaching_programs where facility_id = p_facility_id and (p_facility_sport_ids is null or facility_sport_id = any (p_facility_sport_ids)) and status = 'ACTIVE'
      ),
      'activeCoaches', (
        select count(*) from coaches c
        where c.facility_id = p_facility_id and coaching_sport_ok_coach(c.id, p_facility_sport_ids) and c.status = 'ACTIVE'
          and not exists (
            select 1 from facility_users fu
            where fu.facility_id = c.facility_id and fu.user_id = c.user_id and fu.status = 'INACTIVE'
          )
      ),
      'coachesOnLeave', (
        select count(*) from coaches where facility_id = p_facility_id and coaching_sport_ok_coach(coaches.id, p_facility_sport_ids) and status = 'ON_LEAVE'
      ),
      'sessionsThisMonth', (
        select count(*) from coaching_sessions cs
        where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and cs.status <> 'CANCELLED' and month_ @> cs.start_at
      ),
      'upcomingSessions', (
        select count(*) from coaching_sessions cs
        where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and cs.status in ('SCHEDULED', 'CONFIRMED') and cs.start_at >= now()
      ),
      'revenueThisMonthMinor', (
        select coalesce(sum(p.amount_inr) * 100, 0)::bigint from payments p
        where p.facility_id = p_facility_id and p.status = 'paid'
          and p.coaching_enrollment_id is not null and coaching_sport_ok_enrollment(p.coaching_enrollment_id, p_facility_sport_ids)
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
        where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids)
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
        where cp.facility_id = p_facility_id and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids)) and cp.status = 'ACTIVE'
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
        where cp.facility_id = p_facility_id and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids)) and cp.status = 'ACTIVE'
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
            where e.facility_id = p_facility_id and coaching_sport_ok_program(e.program_id, p_facility_sport_ids)
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
        where e.facility_id = p_facility_id and coaching_sport_ok_program(e.program_id, p_facility_sport_ids)
        order by e.created_at desc
        limit 6
      ) s
    ), '[]'::jsonb)
  );

  return result;
end;
$$;

-- ── get_coaching_overview
create or replace function get_coaching_overview(p_facility_id uuid, p_facility_sport_ids uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base jsonb;
  v_tz text;
  v_today date;
  v_day tstzrange;
  v_active integer;
  v_upcoming jsonb;
begin
  -- The base function does the permission check.
  v_base := _get_coaching_overview_base(p_facility_id, p_facility_sport_ids);

  v_tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  v_today := (now() at time zone v_tz)::date;
  v_day := tstzrange(v_today::timestamp at time zone v_tz, (v_today + 1)::timestamp at time zone v_tz);

  -- Active sessions: today's sessions that are scheduled and in an active status.
  select count(*)::integer into v_active
  from coaching_sessions cs
  left join coaching_programs cp on cp.id = cs.program_id
  where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids)
    and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS')
    and v_day @> cs.start_at
    and (
      cs.program_id is null
      or (
        cp.start_date is not null
        and cp.start_date <= v_today
        and exists (select 1 from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')
      )
    );

  -- The next two sessions still to happen, today or on a later day.
  select coalesce(jsonb_agg(r.row order by r.start_at), '[]'::jsonb) into v_upcoming
  from (
    select cs.start_at,
      jsonb_build_object(
        'id', cs.id,
        'startAt', cs.start_at,
        'endAt', cs.end_at,
        'programName', coalesce(cp.name, cs.title, 'Coaching Session'),
        'coachName', pr.full_name,
        'courtName', c.name,
        'enrolled', (select count(*) from coaching_session_students css where css.session_id = cs.id and css.status = 'ENROLLED'),
        'capacity', cs.capacity,
        'status', cs.status
      ) as row
    from coaching_sessions cs
    left join coaching_programs cp on cp.id = cs.program_id
    join coaches co on co.id = cs.coach_id
    join profiles pr on pr.id = co.user_id
    join courts c on c.id = cs.court_id
    where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids)
      and cs.status in ('SCHEDULED', 'CONFIRMED')
      and cs.start_at >= now()
      and (
        cs.program_id is null
        or (
          cp.start_date is not null
          and cp.start_date <= v_today
          and exists (select 1 from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')
        )
      )
    order by cs.start_at
    limit 2
  ) r;

  return jsonb_set(
    jsonb_set(v_base, '{kpis,activeSessions}', to_jsonb(v_active), true),
    '{upcomingSessions}', v_upcoming, true
  );
end;
$$;

-- ── get_coaching_insights
create or replace function get_coaching_insights(p_facility_id uuid, p_days integer default 30, p_facility_sport_ids uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  tz text;
  window_ tstzrange;
  completed_count integer;
  concluded_count integer;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  if p_days not in (30, 60, 90) then
    raise exception 'Unsupported window — expected 30, 60 or 90 days.' using errcode = '22023';
  end if;
  tz := coalesce((select timezone from facilities where id = p_facility_id), 'Asia/Kolkata');
  window_ := tstzrange(
    (date_trunc('day', now() at time zone tz) - (p_days - 1) * interval '1 day') at time zone tz,
    (date_trunc('day', now() at time zone tz) + interval '1 day') at time zone tz
  );

  select
    count(*) filter (where cs.status = 'COMPLETED'),
    count(*) filter (where cs.status in ('COMPLETED', 'CANCELLED'))
  into completed_count, concluded_count
  from coaching_sessions cs
  where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and window_ @> cs.start_at;

  return jsonb_build_object(
    'windowDays', p_days,
    'totalStudents', (
      select count(distinct e.member_id)
      from coaching_session_students css
      join coaching_sessions cs on cs.id = css.session_id
      join coaching_enrollments e on e.id = css.enrollment_id
      where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and css.status = 'ENROLLED'
        and cs.status <> 'CANCELLED' and window_ @> cs.start_at
    ),
    'sessionAttendancePct', case when concluded_count > 0 then round(100.0 * completed_count / concluded_count, 1) else null end,
    'coachingRevenueMinor', (
      select coalesce(sum(p.amount_inr) * 100, 0)::bigint from payments p
      where p.facility_id = p_facility_id and p.status = 'paid'
        and p.coaching_enrollment_id is not null and coaching_sport_ok_enrollment(p.coaching_enrollment_id, p_facility_sport_ids)
        and window_ @> coalesce(p.paid_at, p.created_at)
    ),
    'averageRating', (
      select round(avg(c.rating), 1) from coaches c
      where c.facility_id = p_facility_id and coaching_sport_ok_coach(c.id, p_facility_sport_ids) and c.status = 'ACTIVE' and c.rating is not null
        and not exists (
          select 1 from facility_users fu
          where fu.facility_id = c.facility_id and fu.user_id = c.user_id and fu.status = 'INACTIVE'
        )
    )
  );
end;
$$;

-- ── get_coaching_card_stats
create or replace function get_coaching_card_stats(p_facility_id uuid, p_facility_sport_ids uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  tz text;
  month_start date;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  tz := coalesce((select timezone from facilities where id = p_facility_id), 'Asia/Kolkata');
  month_start := date_trunc('month', now() at time zone tz)::date;

  return jsonb_build_object(
    'totalCoaches', (select count(*) from coaches where facility_id = p_facility_id and coaching_sport_ok_coach(coaches.id, p_facility_sport_ids)),
    'coachingExpenseMinor', (
      select coalesce(sum(x.amount_minor), 0)::bigint
      from expenses x
      join expense_categories c on c.id = x.category_id
      where x.facility_id = p_facility_id
        and x.status = 'RECORDED'
        and lower(c.name) = 'coaching'
        and x.spent_on >= month_start
        and x.spent_on < (month_start + interval '1 month')::date
    )
  );
end;
$$;

-- ── get_coaching_reports
create or replace function get_coaching_reports(
  p_facility_id uuid,
  p_preset text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_ids uuid[] default null
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
      'activeStudents', (select count(distinct e.member_id) from coaching_enrollments e where e.facility_id = p_facility_id and coaching_sport_ok_program(e.program_id, p_facility_sport_ids) and e.status = 'ACTIVE'),
      'activePrograms', (select count(*) from coaching_programs where facility_id = p_facility_id and (p_facility_sport_ids is null or facility_sport_id = any (p_facility_sport_ids)) and status = 'ACTIVE'),
      'sessionsInRange', (select count(*) from coaching_sessions cs where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and cs.status <> 'CANCELLED' and range_ @> cs.start_at),
      'completedSessionsInRange', (select count(*) from coaching_sessions cs where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and cs.status = 'COMPLETED' and range_ @> cs.start_at),
      'coachingRevenueMinor', (
        select coalesce(sum(p.amount_inr) * 100, 0)::bigint from payments p
        where p.facility_id = p_facility_id and p.status = 'paid'
          and p.coaching_enrollment_id is not null and coaching_sport_ok_enrollment(p.coaching_enrollment_id, p_facility_sport_ids) and range_ @> coalesce(p.paid_at, p.created_at)
      ),
      'avgCapacityUtilization', (
        select coalesce(round(avg(
          case when cs.capacity > 0
            then 100.0 * (select count(*) from coaching_session_students css where css.session_id = cs.id and css.status = 'ENROLLED') / cs.capacity
            else 0 end
        ), 1), 0)
        from coaching_sessions cs
        where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and cs.status <> 'CANCELLED' and range_ @> cs.start_at
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
        where cp.facility_id = p_facility_id and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids))
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
            where cs.coach_id = co.id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and cs.status <> 'CANCELLED' and range_ @> cs.start_at
          )::numeric, 1), 0),
          -- Weekly recurring available hours (spec §30: from availability, not attendance).
          'weeklyAvailableHours', coalesce(round((
            select sum(extract(epoch from (ca.end_time - ca.start_time)) / 3600.0)
            from coach_availability ca where ca.coach_id = co.id
          )::numeric, 1), 0),
          'sessions', (select count(*) from coaching_sessions cs where cs.coach_id = co.id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and cs.status <> 'CANCELLED' and range_ @> cs.start_at)
        ) as row
        from coaches co join profiles pr on pr.id = co.user_id
        where co.facility_id = p_facility_id and coaching_sport_ok_coach(co.id, p_facility_sport_ids) and co.status = 'ACTIVE'
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
            where e.facility_id = p_facility_id and coaching_sport_ok_program(e.program_id, p_facility_sport_ids)
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

-- ── list_coaches
create or replace function list_coaches(
    p_facility_id uuid,
    p_search text default null,
    p_status text default null,
    p_specialization text default null,
    p_limit integer default 20,
    p_offset integer default 0,
    p_sport_id uuid default null,
    -- 'name_asc' (default) | 'name_desc' | 'experience_desc' | 'sessions_desc'
    p_sort text default 'name_asc',
  p_facility_sport_ids uuid[] default null
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
    expertise_levels text[],
    rating numeric,
    sports jsonb,
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
      co.specialization, co.experience_years, co.status, co.expertise_levels, co.rating,
      coalesce((
        select jsonb_agg(jsonb_build_object('id', fs.id, 'name', coalesce(fs.custom_sport_name, s.name)) order by coalesce(fs.custom_sport_name, s.name))
        from coach_sports cst
        join facility_sports fs on fs.id = cst.facility_sport_id
        join sports s on s.id = fs.sport_id
        where cst.coach_id = co.id
      ), '[]'::jsonb),
      (select count(distinct cs.program_id) from coaching_sessions cs where cs.coach_id = co.id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and cs.status <> 'CANCELLED')::bigint,
      (select count(*) from coaching_sessions cs where cs.coach_id = co.id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and cs.status <> 'CANCELLED' and month_ @> cs.start_at)::bigint,
      (select count(distinct e.member_id) from coaching_enrollments e where e.coach_id = co.id and e.status = 'ACTIVE')::bigint,
      count(*) over ()::bigint
    from coaches co
    join profiles pr on pr.id = co.user_id
    where co.facility_id = p_facility_id and coaching_sport_ok_coach(co.id, p_facility_sport_ids)
      and (p_status is null or co.status = p_status)
      and (p_specialization is null or co.specialization ilike '%' || p_specialization || '%')
      and (p_sport_id is null or exists (select 1 from coach_sports cst where cst.coach_id = co.id and cst.facility_sport_id = p_sport_id))
      and (
        p_search is null or trim(p_search) = ''
        or pr.full_name ilike '%' || trim(p_search) || '%'
        or pr.email ilike '%' || trim(p_search) || '%'
        or pr.phone ilike '%' || trim(p_search) || '%'
      )
    -- Exactly one CASE below is non-null for every row (p_sort is a single constant for the whole
    -- query), so it alone drives the order; the rest evaluate to null-for-every-row and are
    -- effectively no-ops. full_name is always the final tiebreaker.
    order by
      case when p_sort = 'name_asc' then pr.full_name end asc,
      case when p_sort = 'name_desc' then pr.full_name end desc,
      case when p_sort = 'experience_desc' then co.experience_years end desc nulls last,
      case when p_sort = 'sessions_desc' then (
        select count(*) from coaching_sessions cs where cs.coach_id = co.id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids) and cs.status <> 'CANCELLED' and month_ @> cs.start_at
      ) end desc,
      pr.full_name asc
    limit greatest(p_limit, 1) offset greatest(p_offset, 0);
  end;
  $$;

-- ── list_coaching_programs
create or replace function list_coaching_programs(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_facility_sport_id uuid default null,
  p_program_type text default null,
  p_level text default null,
  p_facility_sport_ids uuid[] default null
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
  image_url text,
  program_type text,
  sports_per_week integer,
  student_count bigint,
  scheduled_session_count bigint,
  batch_count bigint,
  facility_sport_id uuid,
  start_date date,
  end_date date,
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
    cp.image_url, cp.program_type, cp.sessions_per_week,
    (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')::bigint,
    (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status <> 'CANCELLED')::bigint,
    (select count(*) from coaching_program_batches b where b.program_id = cp.id and b.status = 'ACTIVE')::bigint,
    cp.facility_sport_id, cp.start_date, cp.end_date,
    count(*) over ()::bigint
  from coaching_programs cp
  where cp.facility_id = p_facility_id and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids))
    and (p_status is null or cp.status = p_status)
    and (p_facility_sport_id is null or cp.facility_sport_id = p_facility_sport_id)
    and (p_program_type is null or cp.program_type = p_program_type)
    and (p_level is null or cp.level = p_level)
    and (p_search is null or trim(p_search) = '' or cp.name ilike '%' || trim(p_search) || '%')
  order by cp.status, cp.name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

-- ── get_program_insights
create or replace function get_program_insights(p_facility_id uuid, p_facility_sport_ids uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  enrolled_recent integer;
  enrolled_prior integer;
  featured coaching_programs;
  featured_json jsonb;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;

  select count(*) into enrolled_recent from coaching_enrollments e
  where e.facility_id = p_facility_id and coaching_sport_ok_program(e.program_id, p_facility_sport_ids) and e.created_at >= now() - interval '30 days';
  select count(*) into enrolled_prior from coaching_enrollments e
  where e.facility_id = p_facility_id and coaching_sport_ok_program(e.program_id, p_facility_sport_ids) and e.created_at >= now() - interval '60 days' and e.created_at < now() - interval '30 days';

  select * into featured from coaching_programs
  where facility_id = p_facility_id and status = 'ACTIVE' and (p_facility_sport_ids is null or facility_sport_id = any (p_facility_sport_ids))
  order by (select count(*) from coaching_enrollments e where e.program_id = coaching_programs.id and e.status = 'ACTIVE') desc, name
  limit 1;

  if featured.id is not null then
    featured_json := jsonb_build_object(
      'id', featured.id,
      'name', featured.name,
      'imageUrl', featured.image_url,
      'level', featured.level,
      'ageGroup', featured.age_group,
      'defaultCapacity', featured.default_capacity,
      'studentCount', (select count(*) from coaching_enrollments e where e.program_id = featured.id and e.status = 'ACTIVE'),
      'defaultPriceMinor', featured.default_price_minor,
      'isMembershipIncluded', featured.is_membership_included,
      'durationWeeks', case when featured.start_date is not null and featured.end_date is not null
        then greatest(1, round((featured.end_date - featured.start_date) / 7.0)::int) else null end
    );
  else
    featured_json := null;
  end if;

  return jsonb_build_object(
    'totalPrograms', (select count(*) from coaching_programs where facility_id = p_facility_id and (p_facility_sport_ids is null or facility_sport_id = any (p_facility_sport_ids))),
    'newProgramsThisMonth', (
      select count(*) from coaching_programs
      where facility_id = p_facility_id and created_at >= date_trunc('month', now())
    ),
    'enrolledStudents', (select count(*) from coaching_enrollments where facility_id = p_facility_id and coaching_sport_ok_program(program_id, p_facility_sport_ids) and status = 'ACTIVE'),
    'enrolledStudentsPctChange', case when enrolled_prior > 0 then round(100.0 * (enrolled_recent - enrolled_prior) / enrolled_prior) else null end,
    'avgCompletionPct', (
      select round(avg(
        (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')::numeric
        / nullif(cp.default_capacity, 0) * 100
      ), 0)
      from coaching_programs cp
      where cp.facility_id = p_facility_id and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids)) and cp.status = 'ACTIVE' and cp.default_capacity > 0
    ),
    'averageRating', (
      select round(avg(c.rating), 1) from coaches c
      where c.facility_id = p_facility_id and coaching_sport_ok_coach(c.id, p_facility_sport_ids) and c.status = 'ACTIVE' and c.rating is not null
        and not exists (
          select 1 from facility_users fu
          where fu.facility_id = c.facility_id and fu.user_id = c.user_id and fu.status = 'INACTIVE'
        )
    ),
    'activeBatches', (
      select count(*) from coaching_program_batches b
      join coaching_programs cp on cp.id = b.program_id
      where cp.facility_id = p_facility_id and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids)) and cp.status = 'ACTIVE' and b.status = 'ACTIVE'
    ),
    'featuredProgram', featured_json
  );
end;
$$;

-- ── get_program_card_stats
create or replace function get_program_card_stats(p_facility_id uuid, p_facility_sport_ids uuid[] default null)
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
    'totalPrograms', (select count(*) from coaching_programs where facility_id = p_facility_id and (p_facility_sport_ids is null or facility_sport_id = any (p_facility_sport_ids))),
    'activePrograms', (select count(*) from coaching_programs where facility_id = p_facility_id and (p_facility_sport_ids is null or facility_sport_id = any (p_facility_sport_ids)) and status = 'ACTIVE'),
    'enrolledStudents', (select count(*) from coaching_enrollments where facility_id = p_facility_id and coaching_sport_ok_program(program_id, p_facility_sport_ids) and status = 'ACTIVE'),
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
        where cp.facility_id = p_facility_id and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids)) and cp.status = 'ACTIVE'
      ) s
    )
  );
end;
$$;

-- ── get_student_card_stats
create or replace function get_student_card_stats(p_facility_id uuid, p_facility_sport_ids uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  tz text;
  month_start timestamptz;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  tz := coalesce((select timezone from facilities where id = p_facility_id), 'Asia/Kolkata');
  month_start := date_trunc('month', now() at time zone tz) at time zone tz;

  return jsonb_build_object(
    'totalStudents', (select count(distinct member_id) from coaching_enrollments where facility_id = p_facility_id and coaching_sport_ok_program(program_id, p_facility_sport_ids)),
    'enrolledStudents', (
      select count(distinct member_id) from coaching_enrollments where facility_id = p_facility_id and coaching_sport_ok_program(program_id, p_facility_sport_ids) and status = 'ACTIVE'
    ),
    'revenueMinor', (
      select coalesce(sum(p.amount_inr) * 100, 0)::bigint from payments p
      where p.facility_id = p_facility_id and p.status = 'paid' and p.coaching_enrollment_id is not null and coaching_sport_ok_enrollment(p.coaching_enrollment_id, p_facility_sport_ids)
        and coalesce(p.paid_at, p.created_at) >= month_start
        and coalesce(p.paid_at, p.created_at) < month_start + interval '1 month'
    ),
    'pendingMinor', (
      select coalesce(sum(greatest(e.price_minor - coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.coaching_enrollment_id = e.id and p.status = 'paid'), 0), 0)), 0)::bigint
      from coaching_enrollments e
      where e.facility_id = p_facility_id and coaching_sport_ok_program(e.program_id, p_facility_sport_ids) and e.status <> 'CANCELLED' and e.pricing_type <> 'MEMBERSHIP_INCLUDED'
    )
  );
end;
$$;

-- ── list_coaching_sessions
create or replace function list_coaching_sessions(
  p_facility_id uuid,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_coach_id uuid default null,
  p_program_id uuid default null,
  p_court_id uuid default null,
  p_status text default null,
  p_limit integer default 200,
  p_offset integer default 0,
  p_facility_sport_ids uuid[] default null
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
declare
  v_today date;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  v_today := (now() at time zone coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata'))::date;
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
  where cs.facility_id = p_facility_id and coaching_sport_ok_court(cs.court_id, p_facility_sport_ids)
    and (
      cs.program_id is null
      or (
        cp.start_date is not null
        and cp.start_date <= v_today
        and exists (select 1 from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')
      )
    )
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

-- ── list_coaching_enrollments
create or replace function list_coaching_enrollments(
  p_facility_id uuid,
  p_search text default null,
  p_program_id uuid default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_coach_id uuid default null,
  p_level text default null,
  p_facility_sport_ids uuid[] default null
)
returns table (
  id uuid,
  member_id uuid,
  student_name text,
  student_phone text,
  student_age integer,
  program_id uuid,
  program_name text,
  program_level text,
  coach_id uuid,
  coach_name text,
  coach_avatar_url text,
  start_date date,
  end_date date,
  sessions_total integer,
  price_minor integer,
  paid_minor bigint,
  status text,
  payment_status text,
  batch_id uuid,
  batch_name text,
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
      case when m.date_of_birth is null then null else extract(year from age(current_date, m.date_of_birth))::int end as student_age,
      e.program_id, cp.name as program_name, cp.level as program_level,
      e.coach_id, pr.full_name as coach_name, pr.avatar_url as coach_avatar_url,
      e.start_date, e.end_date, e.sessions_total, e.price_minor,
      coalesce((select sum(p.amount_inr) * 100 from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid'), 0)::bigint as paid_minor,
      e.status, e.batch_id, b.name as batch_name
    from coaching_enrollments e
    join members m on m.id = e.member_id
    join coaching_programs cp on cp.id = e.program_id
    left join coaches co on co.id = e.coach_id
    left join profiles pr on pr.id = co.user_id
    left join coaching_program_batches b on b.id = e.batch_id
    where e.facility_id = p_facility_id and coaching_sport_ok_program(e.program_id, p_facility_sport_ids)
      and (p_program_id is null or e.program_id = p_program_id)
      and (p_coach_id is null or e.coach_id = p_coach_id)
      and (p_level is null or cp.level = p_level)
      and (
        p_status is null
        or (p_status = 'NOT_ACTIVE' and e.status <> 'ACTIVE')
        or e.status = p_status
      )
      and (
        p_search is null or trim(p_search) = ''
        or m.full_name ilike '%' || trim(p_search) || '%'
        or m.phone ilike '%' || trim(p_search) || '%'
        or m.email ilike '%' || trim(p_search) || '%'
        or cp.name ilike '%' || trim(p_search) || '%'
      )
  )
  select
    r.id, r.member_id, r.student_name, r.student_phone, r.student_age,
    r.program_id, r.program_name, r.program_level, r.coach_id, r.coach_name, r.coach_avatar_url,
    r.start_date, r.end_date, r.sessions_total, r.price_minor, r.paid_minor, r.status,
    case
      when r.price_minor = 0 then 'INCLUDED'
      when r.paid_minor >= r.price_minor then 'PAID'
      when r.paid_minor > 0 then 'PARTIAL'
      else 'PENDING'
    end as payment_status,
    r.batch_id, r.batch_name,
    count(*) over ()::bigint as total_count
  from rows r
  order by r.start_date desc, r.student_name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

-- ── list_active_coaching_batches_with_students
create or replace function list_active_coaching_batches_with_students(p_facility_id uuid, p_facility_sport_ids uuid[] default null)
returns table (
  id uuid,
  program_id uuid,
  program_name text,
  batch_name text,
  days_of_week smallint[],
  start_time time,
  end_time time,
  court_name text,
  coach_name text,
  enrolled_count bigint,
  capacity integer
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
    b.id, b.program_id, cp.name, b.name, b.days_of_week, b.start_time, b.end_time,
    c.name, pr.full_name,
    (select count(*) from coaching_enrollments e where e.batch_id = b.id and e.status in ('ACTIVE', 'PAUSED'))::bigint,
    b.capacity
  from coaching_program_batches b
  join coaching_programs cp on cp.id = b.program_id
  join courts c on c.id = b.court_id
  left join coaches co on co.id = b.coach_id
  left join profiles pr on pr.id = co.user_id
  where cp.facility_id = p_facility_id and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids))
    and cp.status = 'ACTIVE'
    and b.status = 'ACTIVE'
    and exists (select 1 from coaching_enrollments e where e.batch_id = b.id and e.status in ('ACTIVE', 'PAUSED'))
  order by b.name;
end;
$$;

-- ── get_coaching_total_revenue
create or replace function get_coaching_total_revenue(p_facility_id uuid, p_facility_sport_ids uuid[] default null)
returns bigint
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
    select coalesce(sum(p.amount_inr) * 100, 0)::bigint
    from payments p
    where p.facility_id = p_facility_id
      and p.status = 'paid'
      and p.coaching_enrollment_id is not null and coaching_sport_ok_enrollment(p.coaching_enrollment_id, p_facility_sport_ids)
  );
end;
$$;

grant execute on function _get_coaching_overview_base(uuid, uuid[]) to authenticated;
grant execute on function get_coaching_overview(uuid, uuid[]) to authenticated;
grant execute on function get_coaching_insights(uuid, integer, uuid[]) to authenticated;
grant execute on function get_coaching_card_stats(uuid, uuid[]) to authenticated;
grant execute on function get_coaching_reports(uuid, text, date, date, uuid[]) to authenticated;
grant execute on function list_coaches(uuid, text, text, text, integer, integer, uuid, text, uuid[]) to authenticated;
grant execute on function list_coaching_programs(uuid, text, text, integer, integer, uuid, text, text, uuid[]) to authenticated;
grant execute on function get_program_insights(uuid, uuid[]) to authenticated;
grant execute on function get_program_card_stats(uuid, uuid[]) to authenticated;
grant execute on function get_student_card_stats(uuid, uuid[]) to authenticated;
grant execute on function list_coaching_sessions(uuid, timestamptz, timestamptz, uuid, uuid, uuid, text, integer, integer, uuid[]) to authenticated;
grant execute on function list_coaching_enrollments(uuid, text, uuid, text, integer, integer, uuid, text, uuid[]) to authenticated;
grant execute on function list_active_coaching_batches_with_students(uuid, uuid[]) to authenticated;
grant execute on function get_coaching_total_revenue(uuid, uuid[]) to authenticated;
