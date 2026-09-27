-- get_program_insights' activeBatches counted every ACTIVE batch row regardless of its parent
-- program's own status — so a batch under a program the owner deactivated (or that's still a
-- DRAFT/COMPLETED/ARCHIVED) still counted as "active", overstating the figure. A batch is only
-- really active when both it and its program are.
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
      where cp.facility_id = p_facility_id and cp.status = 'ACTIVE' and b.status = 'ACTIVE'
    ),
    'featuredProgram', featured_json
  );
end;
$$;
