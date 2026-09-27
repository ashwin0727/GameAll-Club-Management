-- ═══════════════════════════════════════════════════════════════════════════
-- Manage Students list — matches the reference design's table/filters. Adds
-- Age (from members.date_of_birth — already collected at Add Student, never
-- stored twice), the program's Skill Level, and the coach's avatar, plus
-- Coach/Level filters and an "Inactive" (not-ACTIVE) status grouping for the
-- All/Active/Inactive tabs — same "tabs + dropdown are two views of one
-- filter" pattern the Coaches roster already uses. No attendance column
-- here: there is no per-student check-in system in the app, so that stays a
-- frontend-only "—" rather than a fabricated number.
-- ═══════════════════════════════════════════════════════════════════════════

drop function if exists list_coaching_enrollments(uuid, text, uuid, text, integer, integer);

create or replace function list_coaching_enrollments(
  p_facility_id uuid,
  p_search text default null,
  p_program_id uuid default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_coach_id uuid default null,
  p_level text default null
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
    where e.facility_id = p_facility_id
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

grant execute on function list_coaching_enrollments(uuid, text, uuid, text, integer, integer, uuid, text) to authenticated;
