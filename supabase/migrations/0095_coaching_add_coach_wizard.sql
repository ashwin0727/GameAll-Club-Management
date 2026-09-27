  -- ═══════════════════════════════════════════════════════════════════════════
  -- Coaching — Add Coach wizard support (v1, web only): structured sports and
  -- expertise levels on a coach (today only `specialization` free text exists),
  -- a coach-level default session duration, and the read/write RPCs extended
  -- to carry them. See docs/superpowers/specs/2026-09-25-coaching-add-coach-wizard-v1.md.
  -- ═══════════════════════════════════════════════════════════════════════════


  -- A coach can be capable of coaching more than one of the facility's sports.
  -- A junction table, not an array column, because facility_sport_id is a real
  -- FK and "coaches for this sport" is a join other coaching queries can reuse.
  -- facility_id is denormalized here rather than joined through coaches, same
  -- as every other coaching child table (coach_availability, 0082) — a direct
  -- column check in RLS rather than a per-row subquery.
  create table if not exists coach_sports (
    coach_id uuid not null references coaches (id) on delete cascade,
    facility_id uuid not null references facilities (id) on delete cascade,
    facility_sport_id uuid not null references facility_sports (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (coach_id, facility_sport_id)
  );

  create index if not exists coach_sports_sport_idx on coach_sports (facility_sport_id);

  alter table coach_sports enable row level security;

  drop policy if exists "coach_sports_select" on coach_sports;
  create policy "coach_sports_select" on coach_sports for select
    using (has_permission(facility_id, 'COACHING_VIEW'));
  -- Writes go through add_coach/update_coach below (SECURITY DEFINER, gated COACHING_MANAGE_COACHES).

  -- Expertise is a small, fixed vocabulary (Beginner/Intermediate/Advanced/All
  -- Levels — the same list program-wizard-page.tsx's LEVELS already uses), so a
  -- plain array column rather than a lookup table.
  alter table coaches add column if not exists expertise_levels text[] not null default '{}';

  -- The coach's default session length, used to prefill the (separate, existing)
  -- Schedule Session flow. Nullable: existing coaches have no default until set.
  alter table coaches add column if not exists default_session_duration_minutes integer
    check (default_session_duration_minutes is null or default_session_duration_minutes > 0);

  -- Same column name/type members.date_of_birth already uses (migration 0013) — the Add Coach
  -- wizard collects it, and there is no existing person-level DOB column anywhere to reuse instead
  -- (profiles has none).
  alter table coaches add column if not exists date_of_birth date;

  -- A manual, facility-set rating (out of 5) — there's no review/feedback system anywhere in the
  -- app to derive a real rating from, so this is deliberately simple: staff sets it from the Coach
  -- Profile (not part of onboarding — a brand-new coach has no track record yet to rate). Backs the
  -- Coaching Insights "Average Rating" tile with a real, if basic, number instead of a fabricated one.
  alter table coaches add column if not exists rating numeric(2, 1)
    check (rating is null or (rating >= 0 and rating <= 5));


  -- ─────────────────────────────────────────────────────────────────────────
  -- add_coach / update_coach — extended with sport ids, expertise levels and
  -- the default session duration. New params default to null ("don't touch");
  -- an explicit (possibly empty) array replaces the coach's whole set, same
  -- one-call-replaces-the-set convention set_coach_availability already uses.
  -- ─────────────────────────────────────────────────────────────────────────
  create or replace function add_coach(
    p_facility_id uuid,
    p_user_id uuid,
    p_specialization text default null,
    p_experience_years numeric default null,
    p_certifications text default null,
    p_bio text default null,
    p_hourly_rate_minor integer default null,
    p_status text default 'ACTIVE',
    p_joined_on date default null,
    p_sport_ids uuid[] default null,
    p_expertise_levels text[] default null,
    p_default_session_duration_minutes integer default null,
    p_date_of_birth date default null
  ) returns coaches
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare result coaches;
  begin
    if not has_permission(p_facility_id, 'COACHING_MANAGE_COACHES') then
      raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
    end if;
    if not exists (
      select 1 from facility_users
      where facility_id = p_facility_id and user_id = p_user_id and status = 'ACTIVE'
    ) then
      raise exception 'That person is not an active staff member of this facility. Add them as staff first.' using errcode = '23503';
    end if;
    if coalesce(p_status, 'ACTIVE') not in ('ACTIVE', 'INACTIVE', 'ON_LEAVE') then
      raise exception 'Unknown status.' using errcode = '22023';
    end if;
    if p_default_session_duration_minutes is not null and p_default_session_duration_minutes <= 0 then
      raise exception 'Default session duration must be a positive number of minutes.' using errcode = '22023';
    end if;

    insert into coaches (
      facility_id, user_id, specialization, experience_years, certifications, bio,
      hourly_rate_minor, status, joined_on, created_by, expertise_levels, default_session_duration_minutes,
      date_of_birth
    ) values (
      p_facility_id, p_user_id,
      nullif(trim(coalesce(p_specialization, '')), ''), p_experience_years,
      nullif(trim(coalesce(p_certifications, '')), ''), nullif(trim(coalesce(p_bio, '')), ''),
      p_hourly_rate_minor, coalesce(p_status, 'ACTIVE'), coalesce(p_joined_on, current_date), auth.uid(),
      coalesce(p_expertise_levels, '{}'), p_default_session_duration_minutes, p_date_of_birth
    )
    returning * into result;

    if p_sport_ids is not null and array_length(p_sport_ids, 1) > 0 then
      insert into coach_sports (coach_id, facility_id, facility_sport_id)
      select result.id, p_facility_id, s from unnest(p_sport_ids) as s;
    end if;

    perform log_coaching_event(p_facility_id, 'COACH_CREATED',
      'Coach profile added', result.id, null, null, null,
      jsonb_build_object('userId', p_user_id));
    return result;
  exception when unique_violation then
    raise exception 'This staff member already has a coaching profile.' using errcode = '23505';
  end;
  $$;

  grant execute on function add_coach(uuid, uuid, text, numeric, text, text, integer, text, date, uuid[], text[], integer, date) to authenticated;


  create or replace function update_coach(
    p_coach_id uuid,
    p_specialization text default null,
    p_experience_years numeric default null,
    p_certifications text default null,
    p_bio text default null,
    p_hourly_rate_minor integer default null,
    p_status text default null,
    p_joined_on date default null,
    p_sport_ids uuid[] default null,
    p_expertise_levels text[] default null,
    p_default_session_duration_minutes integer default null,
    p_date_of_birth date default null,
    p_rating numeric default null
  ) returns coaches
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare result coaches;
  begin
    select * into result from coaches where id = p_coach_id;
    if result.id is null then
      raise exception 'Coach not found.' using errcode = 'P0002';
    end if;
    if not has_permission(result.facility_id, 'COACHING_MANAGE_COACHES') then
      raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
    end if;
    if p_status is not null and p_status not in ('ACTIVE', 'INACTIVE', 'ON_LEAVE') then
      raise exception 'Unknown status.' using errcode = '22023';
    end if;
    if p_default_session_duration_minutes is not null and p_default_session_duration_minutes <= 0 then
      raise exception 'Default session duration must be a positive number of minutes.' using errcode = '22023';
    end if;
    if p_rating is not null and (p_rating < 0 or p_rating > 5) then
      raise exception 'Rating must be between 0 and 5.' using errcode = '22023';
    end if;

    update coaches set
      specialization = coalesce(p_specialization, specialization),
      experience_years = coalesce(p_experience_years, experience_years),
      certifications = coalesce(p_certifications, certifications),
      bio = coalesce(p_bio, bio),
      hourly_rate_minor = coalesce(p_hourly_rate_minor, hourly_rate_minor),
      status = coalesce(p_status, status),
      joined_on = coalesce(p_joined_on, joined_on),
      expertise_levels = coalesce(p_expertise_levels, expertise_levels),
      default_session_duration_minutes = coalesce(p_default_session_duration_minutes, default_session_duration_minutes),
      date_of_birth = coalesce(p_date_of_birth, date_of_birth),
      rating = coalesce(p_rating, rating)
    where id = p_coach_id
    returning * into result;

    if p_sport_ids is not null then
      delete from coach_sports where coach_id = p_coach_id;
      if array_length(p_sport_ids, 1) > 0 then
        insert into coach_sports (coach_id, facility_id, facility_sport_id)
        select p_coach_id, result.facility_id, s from unnest(p_sport_ids) as s;
      end if;
    end if;

    perform log_coaching_event(result.facility_id,
      case when p_status = 'INACTIVE' then 'COACH_DEACTIVATED' else 'COACH_UPDATED' end,
      'Coach profile updated', result.id);
    return result;
  end;
  $$;

  grant execute on function update_coach(uuid, text, numeric, text, text, integer, text, date, uuid[], text[], integer, date, numeric) to authenticated;


  -- ─────────────────────────────────────────────────────────────────────────
  -- Read RPCs — list_coaches / get_coach / list_coach_candidates gain sports,
  -- expertise levels and the default session duration. Adding output columns
  -- to a `returns table` function needs a drop first (create or replace can't
  -- change the OUT list); get_coach returns jsonb so it can stay a plain replace.
  -- ─────────────────────────────────────────────────────────────────────────
  drop function if exists list_coaches(uuid, text, text, text, integer, integer);

  create or replace function list_coaches(
    p_facility_id uuid,
    p_search text default null,
    p_status text default null,
    p_specialization text default null,
    p_limit integer default 20,
    p_offset integer default 0,
    p_sport_id uuid default null,
    -- 'name_asc' (default) | 'name_desc' | 'experience_desc' | 'sessions_desc'
    p_sort text default 'name_asc'
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
      (select count(distinct cs.program_id) from coaching_sessions cs where cs.coach_id = co.id and cs.status <> 'CANCELLED')::bigint,
      (select count(*) from coaching_sessions cs where cs.coach_id = co.id and cs.status <> 'CANCELLED' and month_ @> cs.start_at)::bigint,
      (select count(distinct e.member_id) from coaching_enrollments e where e.coach_id = co.id and e.status = 'ACTIVE')::bigint,
      count(*) over ()::bigint
    from coaches co
    join profiles pr on pr.id = co.user_id
    where co.facility_id = p_facility_id
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
        select count(*) from coaching_sessions cs where cs.coach_id = co.id and cs.status <> 'CANCELLED' and month_ @> cs.start_at
      ) end desc,
      pr.full_name asc
    limit greatest(p_limit, 1) offset greatest(p_offset, 0);
  end;
  $$;

  grant execute on function list_coaches(uuid, text, text, text, integer, integer, uuid, text) to authenticated;


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
        'expertiseLevels', co.expertise_levels,
        'defaultSessionDurationMinutes', co.default_session_duration_minutes,
        'dateOfBirth', co.date_of_birth,
        'rating', co.rating,
        'sports', coalesce((
          select jsonb_agg(jsonb_build_object('id', fs.id, 'name', coalesce(fs.custom_sport_name, s.name)) order by coalesce(fs.custom_sport_name, s.name))
          from coach_sports cst
          join facility_sports fs on fs.id = cst.facility_sport_id
          join sports s on s.id = fs.sport_id
          where cst.coach_id = co.id
        ), '[]'::jsonb),
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
  -- picker. Now also returns avatar/phone so the wizard's Step 1 can show a
  -- read-only preview once a candidate is picked, without a second round trip.
  drop function if exists list_coach_candidates(uuid);

  create or replace function list_coach_candidates(p_facility_id uuid)
  returns table (user_id uuid, full_name text, email text, phone text, avatar_url text, title text)
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
    select fu.user_id, pr.full_name, pr.email, pr.phone, pr.avatar_url, fu.title
    from facility_users fu
    join profiles pr on pr.id = fu.user_id
    where fu.facility_id = p_facility_id
      and fu.status = 'ACTIVE'
      and not exists (select 1 from coaches c where c.facility_id = p_facility_id and c.user_id = fu.user_id)
    order by pr.full_name;
  end;
  $$;

  grant execute on function list_coach_candidates(uuid) to authenticated;


  -- ─────────────────────────────────────────────────────────────────────────
  -- get_coaching_insights — the Coaching landing page's "Coaching Insights"
  -- panel, for its own Last 30/60/90 Days dropdown (independent of the KPI
  -- row above it, which stays pinned to the calendar month via
  -- get_coaching_overview). Total Students and Coaching Revenue are real
  -- windowed counts; Session Attendance is a genuine metric derived from
  -- existing session status data (completed vs. cancelled, not per-student
  -- attendance, since no check-in system exists); Average Rating is not
  -- windowed — a coach's rating is a current attribute, not a dated event —
  -- and reads the same manual `coaches.rating` field `update_coach` writes.
  -- ─────────────────────────────────────────────────────────────────────────
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
        select round(avg(rating), 1) from coaches where facility_id = p_facility_id and status = 'ACTIVE' and rating is not null
      )
    );
  end;
  $$;

  grant execute on function get_coaching_insights(uuid, integer) to authenticated;
