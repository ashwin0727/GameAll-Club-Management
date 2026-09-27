-- ═══════════════════════════════════════════════════════════════════════════
-- Same class of bug as 0103's active-batches fix, on the coaches side: a
-- coach's own `status` stays 'ACTIVE' forever unless someone manually edits
-- the Coach Profile, even after that person is removed as staff
-- (facility_users.status set to 'INACTIVE' elsewhere). Every "active coaches"
-- aggregate or picker that only checked coaches.status therefore kept
-- counting/offering coaches whose underlying staff membership is gone.
-- Fixed everywhere that matters: the Coaching dashboard's Active Coaches KPI,
-- the Coaching Insights / Program Insights average-rating figures (both only
-- meant to reflect coaches actually still on staff), and the coach picker
-- used to assign a coach to a session or batch.
-- ═══════════════════════════════════════════════════════════════════════════

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
        select count(*) from coaches c
        where c.facility_id = p_facility_id and c.status = 'ACTIVE'
          and not exists (
            select 1 from facility_users fu
            where fu.facility_id = c.facility_id and fu.user_id = c.user_id and fu.status = 'INACTIVE'
          )
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
    and not exists (
      select 1 from facility_users fu
      where fu.facility_id = c.facility_id and fu.user_id = c.user_id and fu.status = 'INACTIVE'
    )
  order by pr.full_name;
end;
$$;

create or replace function get_coaching_insights(p_facility_id uuid, p_days integer default 30)
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
  where cs.facility_id = p_facility_id and window_ @> cs.start_at;

  return jsonb_build_object(
    'windowDays', p_days,
    'totalStudents', (
      select count(distinct e.member_id)
      from coaching_session_students css
      join coaching_sessions cs on cs.id = css.session_id
      join coaching_enrollments e on e.id = css.enrollment_id
      where cs.facility_id = p_facility_id and css.status = 'ENROLLED'
        and cs.status <> 'CANCELLED' and window_ @> cs.start_at
    ),
    'sessionAttendancePct', case when concluded_count > 0 then round(100.0 * completed_count / concluded_count, 1) else null end,
    'coachingRevenueMinor', (
      select coalesce(sum(p.amount_inr) * 100, 0)::bigint from payments p
      where p.facility_id = p_facility_id and p.status = 'paid'
        and p.coaching_enrollment_id is not null
        and window_ @> coalesce(p.paid_at, p.created_at)
    ),
    'averageRating', (
      select round(avg(c.rating), 1) from coaches c
      where c.facility_id = p_facility_id and c.status = 'ACTIVE' and c.rating is not null
        and not exists (
          select 1 from facility_users fu
          where fu.facility_id = c.facility_id and fu.user_id = c.user_id and fu.status = 'INACTIVE'
        )
    )
  );
end;
$$;

create or replace function get_program_insights(p_facility_id uuid)
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
  where e.facility_id = p_facility_id and e.created_at >= now() - interval '30 days';
  select count(*) into enrolled_prior from coaching_enrollments e
  where e.facility_id = p_facility_id and e.created_at >= now() - interval '60 days' and e.created_at < now() - interval '30 days';

  select * into featured from coaching_programs
  where facility_id = p_facility_id and status = 'ACTIVE'
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
    'totalPrograms', (select count(*) from coaching_programs where facility_id = p_facility_id),
    'newProgramsThisMonth', (
      select count(*) from coaching_programs
      where facility_id = p_facility_id and created_at >= date_trunc('month', now())
    ),
    'enrolledStudents', (select count(*) from coaching_enrollments where facility_id = p_facility_id and status = 'ACTIVE'),
    'enrolledStudentsPctChange', case when enrolled_prior > 0 then round(100.0 * (enrolled_recent - enrolled_prior) / enrolled_prior) else null end,
    'avgCompletionPct', (
      select round(avg(
        (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')::numeric
        / nullif(cp.default_capacity, 0) * 100
      ), 0)
      from coaching_programs cp
      where cp.facility_id = p_facility_id and cp.status = 'ACTIVE' and cp.default_capacity > 0
    ),
    'averageRating', (
      select round(avg(c.rating), 1) from coaches c
      where c.facility_id = p_facility_id and c.status = 'ACTIVE' and c.rating is not null
        and not exists (
          select 1 from facility_users fu
          where fu.facility_id = c.facility_id and fu.user_id = c.user_id and fu.status = 'INACTIVE'
        )
    ),
    'activeBatches', (
      select count(*) from coaching_program_batches b
      join coaching_programs cp on cp.id = b.program_id
      where cp.facility_id = p_facility_id and cp.status = 'ACTIVE' and b.status = 'ACTIVE'
    ),
    'featuredProgram', featured_json
  );
end;
$$;
