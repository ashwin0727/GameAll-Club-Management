-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching Programs list page rebuild — adds the fields/insights the new
-- dashboard-style Programs list needs (facility_sport_id + dates per row for
-- the Sport badge/Duration/Upcoming filtering, a level filter, and a
-- get_program_insights RPC for the KPI row / Featured Program / Program
-- Insights panel). All figures are genuine, computed from real rows — no
-- fabricated deltas.
-- ═══════════════════════════════════════════════════════════════════════════

-- list_coaching_programs' output columns change, so it needs a drop first
-- (create or replace can't change a `returns table` OUT list).
drop function if exists list_coaching_programs(uuid, text, text, integer, integer, uuid, text);

create or replace function list_coaching_programs(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_facility_sport_id uuid default null,
  p_program_type text default null,
  p_level text default null
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
  where cp.facility_id = p_facility_id
    and (p_status is null or cp.status = p_status)
    and (p_facility_sport_id is null or cp.facility_sport_id = p_facility_sport_id)
    and (p_program_type is null or cp.program_type = p_program_type)
    and (p_level is null or cp.level = p_level)
    and (p_search is null or trim(p_search) = '' or cp.name ilike '%' || trim(p_search) || '%')
  order by cp.status, cp.name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_coaching_programs(uuid, text, text, integer, integer, uuid, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_program_insights — the Coaching Programs list page's KPI row, Featured
-- Program card and Program Insights panel. Every figure is a real, current
-- (or created_at-derived) count; "vs last month" deltas compare to the prior
-- equal-length period rather than being invented.
-- ─────────────────────────────────────────────────────────────────────────
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
    'averageRating', (select round(avg(rating), 1) from coaches where facility_id = p_facility_id and status = 'ACTIVE' and rating is not null),
    'activeBatches', (
      select count(*) from coaching_program_batches b
      join coaching_programs cp on cp.id = b.program_id
      where cp.facility_id = p_facility_id and b.status = 'ACTIVE'
    ),
    'featuredProgram', featured_json
  );
end;
$$;

grant execute on function get_program_insights(uuid) to authenticated;
