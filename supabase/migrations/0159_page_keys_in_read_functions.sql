-- Page-level access, round two: read functions that still demanded a SIBLING page's key.
--
-- A role built in the page-access matrix holds exactly the keys of the pages it was given. Several read functions were never
-- moved onto their own page's key, so a role with, say, only "Roles & Permissions: View" or only "Coaching Schedule: View" was
-- refused by the database even though the page was allowed. Each function below is its latest definition, unchanged, except
-- that the single permission check now accepts the page keys that should be enough:
--   list_roles / get_role                          Roles & Permissions page (or Staff, for the role pickers)
--   list_security_events                           Access History page
--   list_coaches, list_coach_options, ...          any Coaching page (these feed pickers and filters on every Coaching page)
--   get_expense / get_expense_summary              Expenses page (or Finance Overview)

-- list_roles (was 0098_fix_list_roles_duplicate_custom_role.sql)
create or replace function list_roles(p_facility_id uuid)
returns table (
  id uuid,
  key text,
  name text,
  description text,
  is_system boolean,
  is_custom boolean,
  is_active boolean,
  version integer,
  staff_count bigint,
  permission_count bigint
)
language plpgsql
stable
as $$
begin
  if not (has_permission(p_facility_id, 'USERS_VIEW') or has_permission(p_facility_id, 'ROLES_VIEW')) then
    raise exception 'You don''t have permission to view roles.' using errcode = '42501';
  end if;

  return query
  with resolved as (
    -- the effective row for each of the three base tiers — only a role
    -- explicitly keyed to that tier (a system template, or this facility's
    -- own override of it) can stand in for it; a plain custom role that
    -- merely inherits base_role='staff' for permission-fallback purposes
    -- must never be picked up here.
    select distinct on (t.tier)
      r.id, r.key, r.name, r.description, r.is_system, false as is_custom, r.is_active, r.version, t.tier
    from (values ('owner'::facility_role), ('manager'), ('staff')) t(tier)
    join roles r on
      r.key = t.tier::text
      and not r.is_template
      and (r.facility_id = p_facility_id or r.facility_id is null)
    order by t.tier, (r.facility_id is not null) desc
  ),
  customs as (
    select r.id, r.key, r.name, r.description, r.is_system, true as is_custom, r.is_active, r.version, null::facility_role as tier
    from roles r
    where r.facility_id = p_facility_id and not r.is_system and not r.is_template
  ),
  all_roles as (
    select resolved.id, resolved.key, resolved.name, resolved.description, resolved.is_system,
           resolved.is_custom, resolved.is_active, resolved.version, resolved.tier
    from resolved
    union all
    select customs.id, customs.key, customs.name, customs.description, customs.is_system,
           customs.is_custom, customs.is_active, customs.version, customs.tier
    from customs
  )
  select
    ar.id, ar.key, ar.name, ar.description, ar.is_system, ar.is_custom, ar.is_active, ar.version,
    (
      select count(*) from facility_users fu
      where fu.facility_id = p_facility_id
        and (
          fu.role_id = ar.id
          or (fu.role_id is null and ar.key is not null and fu.role::text = ar.key)
        )
    ) as staff_count,
    (select count(*) from role_permissions rp where rp.role_id = ar.id) as permission_count
  from all_roles ar
  order by
    case ar.key when 'owner' then 0 when 'manager' then 1 when 'staff' then 2 else 3 end,
    ar.name;
end;
$$;

-- get_role (was 0075_rbac_read_rpcs.sql)
create or replace function get_role(p_role_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  r roles;
  result jsonb;
begin
  select * into r from roles where id = p_role_id;
  if r.id is null then
    raise exception 'Role not found.' using errcode = 'P0002';
  end if;
  if r.facility_id is not null and not (has_permission(r.facility_id, 'USERS_VIEW') or has_permission(r.facility_id, 'ROLES_VIEW')) then
    raise exception 'You don''t have permission to view this role.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', r.id, 'key', r.key, 'name', r.name, 'description', r.description,
    'isSystem', r.is_system, 'isTemplate', r.is_template, 'isActive', r.is_active,
    'baseRole', r.base_role, 'version', r.version, 'facilityId', r.facility_id,
    'permissionKeys', coalesce((
      select jsonb_agg(rp.permission_key order by rp.permission_key)
      from role_permissions rp where rp.role_id = r.id
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

-- list_security_events (was 0075_rbac_read_rpcs.sql)
create or replace function list_security_events(
  p_facility_id uuid,
  p_event text default null,
  p_target_user_id uuid default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default 25,
  p_offset integer default 0
)
returns table (
  id uuid,
  event text,
  summary text,
  actor_name text,
  target_name text,
  detail jsonb,
  created_at timestamptz,
  total_count bigint
)
language plpgsql
stable
as $$
begin
  if not has_permission(p_facility_id, 'ACCESS_HISTORY_VIEW') then
    raise exception 'You don''t have permission to view access history.' using errcode = '42501';
  end if;

  return query
  with rows as (
    select e.id, e.event, e.summary, ap.full_name as actor_name, tp.full_name as target_name,
           e.detail, e.created_at
    from security_events e
    left join profiles ap on ap.id = e.actor
    left join profiles tp on tp.id = e.target_user_id
    where e.facility_id = p_facility_id
      and (p_event is null or e.event = p_event)
      and (p_target_user_id is null or e.target_user_id = p_target_user_id)
      and (p_from is null or e.created_at >= p_from)
      and (p_to is null or e.created_at <= p_to)
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by r.created_at desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

-- list_coaches (was 0156_page_access_enforcement.sql)
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
    if not (has_permission(p_facility_id, 'COACHING_VIEW') or has_permission(p_facility_id, 'COACHING_PROGRAMS_VIEW') or has_permission(p_facility_id, 'COACHING_STUDENTS_VIEW') or has_permission(p_facility_id, 'COACHING_SESSIONS_VIEW') or has_permission(p_facility_id, 'COACHING_SCHEDULE_VIEW') or has_permission(p_facility_id, 'COACHING_REPORTS_VIEW')) then
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
    where co.facility_id = p_facility_id and (not coaching_scope_own(p_facility_id) or co.id = my_coach_id(p_facility_id)) and coaching_sport_ok_coach(co.id, p_facility_sport_ids)
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

-- list_coach_options (was 0156_page_access_enforcement.sql)
create or replace function list_coach_options(p_facility_id uuid)
returns table (id uuid, name text, specialization text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (has_permission(p_facility_id, 'COACHING_VIEW') or has_permission(p_facility_id, 'COACHING_PROGRAMS_VIEW') or has_permission(p_facility_id, 'COACHING_STUDENTS_VIEW') or has_permission(p_facility_id, 'COACHING_SESSIONS_VIEW') or has_permission(p_facility_id, 'COACHING_SCHEDULE_VIEW') or has_permission(p_facility_id, 'COACHING_REPORTS_VIEW')) then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  return query
  select c.id, pr.full_name, c.specialization
  from coaches c join profiles pr on pr.id = c.user_id
  where c.facility_id = p_facility_id and (not coaching_scope_own(p_facility_id) or c.id = my_coach_id(p_facility_id)) and c.status = 'ACTIVE'
    and not exists (
      select 1 from facility_users fu
      where fu.facility_id = c.facility_id and fu.user_id = c.user_id and fu.status = 'INACTIVE'
    )
  order by pr.full_name;
end;
$$;

-- list_coaching_program_batches (was 0107_coaching_enrollment_batch.sql)
create or replace function list_coaching_program_batches(p_program_id uuid)
returns table (
  id uuid,
  court_id uuid,
  court_name text,
  coach_id uuid,
  coach_name text,
  name text,
  days_of_week smallint[],
  start_time time,
  end_time time,
  capacity integer,
  enrolled_count bigint,
  status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare program coaching_programs;
begin
  select * into program from coaching_programs where id = p_program_id;
  if program.id is null then
    raise exception 'Program not found.' using errcode = 'P0002';
  end if;
  if not (has_permission(program.facility_id, 'COACHING_VIEW') or has_permission(program.facility_id, 'COACHING_PROGRAMS_VIEW') or has_permission(program.facility_id, 'COACHING_STUDENTS_VIEW') or has_permission(program.facility_id, 'COACHING_SESSIONS_VIEW') or has_permission(program.facility_id, 'COACHING_SCHEDULE_VIEW') or has_permission(program.facility_id, 'COACHING_REPORTS_VIEW')) then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;

  return query
  select
    b.id, b.court_id, c.name, b.coach_id, pr.full_name, b.name, b.days_of_week, b.start_time, b.end_time,
    b.capacity,
    (select count(*) from coaching_enrollments e where e.batch_id = b.id and e.status in ('ACTIVE', 'PAUSED'))::bigint,
    b.status
  from coaching_program_batches b
  join courts c on c.id = b.court_id
  left join coaches co on co.id = b.coach_id
  left join profiles pr on pr.id = co.user_id
  where b.program_id = p_program_id
  order by b.created_at;
end;
$$;

-- list_active_coaching_batches_with_students (was 0134_coaching_sport_selection.sql)
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
  if not (has_permission(p_facility_id, 'COACHING_VIEW') or has_permission(p_facility_id, 'COACHING_PROGRAMS_VIEW') or has_permission(p_facility_id, 'COACHING_STUDENTS_VIEW') or has_permission(p_facility_id, 'COACHING_SESSIONS_VIEW') or has_permission(p_facility_id, 'COACHING_SCHEDULE_VIEW') or has_permission(p_facility_id, 'COACHING_REPORTS_VIEW')) then
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

-- get_coaching_active_sessions (was 0116_coaching_active_sessions.sql)
create or replace function get_coaching_active_sessions(p_facility_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (has_permission(p_facility_id, 'COACHING_VIEW') or has_permission(p_facility_id, 'COACHING_PROGRAMS_VIEW') or has_permission(p_facility_id, 'COACHING_STUDENTS_VIEW') or has_permission(p_facility_id, 'COACHING_SESSIONS_VIEW') or has_permission(p_facility_id, 'COACHING_SCHEDULE_VIEW') or has_permission(p_facility_id, 'COACHING_REPORTS_VIEW')) then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  return (
    select coalesce(sum(greatest(
      coalesce(cp.session_count, nullif(to_jsonb(cp) ->> 'planned_sessions', '')::integer, 0)
        - (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status = 'COMPLETED'),
      0
    )), 0)::integer
    from coaching_programs cp
    where cp.facility_id = p_facility_id
      and cp.status = 'ACTIVE'
      and exists (
        select 1 from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE'
      )
  );
end;
$$;

-- get_expense (was 0077_rbac_wire_permissions.sql)
create or replace function get_expense(p_expense_id uuid)
returns table (
  id uuid, facility_id uuid, category_id uuid, category_name text, amount_minor integer,
  amount_paid_minor integer, tax_minor integer, currency text, payment_status text, payment_method text,
  spent_on date, due_on date, vendor text, reference text, notes text, receipt_path text, status text,
  created_by uuid, created_by_name text, created_at timestamptz, updated_at timestamptz,
  voided_at timestamptz, void_reason text, source_maintenance_ticket_id uuid, payments jsonb
) language plpgsql stable as $$
begin
  return query
  select
    e.id, e.facility_id, e.category_id, c.name, e.amount_minor, e.amount_paid_minor,
    e.tax_minor, e.currency, e.payment_status, e.payment_method, e.spent_on, e.due_on,
    e.vendor, e.reference, e.notes, e.receipt_path, e.status,
    e.created_by, pr.full_name, e.created_at, e.updated_at, e.voided_at, e.void_reason,
    (select mt.id from maintenance_tickets mt where mt.expense_id = e.id limit 1),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ep.id, 'amountMinor', ep.amount_minor, 'paidOn', ep.paid_on,
        'paymentMethod', ep.payment_method, 'reference', ep.reference, 'note', ep.note,
        'createdAt', ep.created_at
      ) order by ep.paid_on, ep.created_at)
      from expense_payments ep where ep.expense_id = e.id
        and coalesce(ep.reference, '') not like 'IDEMP:%'
    ), '[]'::jsonb)
  from expenses e
  join expense_categories c on c.id = e.category_id
  left join profiles pr on pr.id = e.created_by
  where e.id = p_expense_id
    and (has_permission(e.facility_id, 'FINANCE_VIEW') or has_permission(e.facility_id, 'FINANCE_EXPENSES_VIEW'));
end; $$;

-- get_expense_summary (was 0077_rbac_wire_permissions.sql)
create or replace function get_expense_summary(
  p_facility_id uuid, p_preset text default 'THIS_MONTH', p_start_date date default null, p_end_date date default null
) returns table (
  total_minor bigint, this_month_minor bigint, this_week_minor bigint, pending_minor bigint,
  pending_count bigint, maintenance_minor bigint, other_minor bigint
) language plpgsql stable as $$
declare range_ tstzrange; month_ tstzrange; week_ tstzrange; tz text;
begin
  if not (has_permission(p_facility_id, 'FINANCE_VIEW') or has_permission(p_facility_id, 'FINANCE_EXPENSES_VIEW')) then
    raise exception 'You don''t have permission to view finance.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  month_ := resolve_finance_date_range(p_facility_id, 'THIS_MONTH', null, null);
  week_ := resolve_finance_date_range(p_facility_id, 'THIS_WEEK', null, null);
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  return query
  with ex as (
    select e.amount_minor as amt, e.amount_paid_minor as paid, e.payment_status as pstatus,
           lower(c.name) as cat, (e.spent_on::timestamp at time zone tz) as spent_at
    from expenses e join expense_categories c on c.id = e.category_id
    where e.facility_id = p_facility_id and e.status = 'RECORDED'
  )
  select
    coalesce(sum(amt) filter (where range_ @> spent_at), 0)::bigint,
    coalesce(sum(amt) filter (where month_ @> spent_at), 0)::bigint,
    coalesce(sum(amt) filter (where week_ @> spent_at), 0)::bigint,
    coalesce(sum(amt - paid) filter (where pstatus <> 'PAID'), 0)::bigint,
    coalesce(count(*) filter (where pstatus <> 'PAID'), 0)::bigint,
    coalesce(sum(amt) filter (where range_ @> spent_at and cat = 'maintenance'), 0)::bigint,
    coalesce(sum(amt) filter (where range_ @> spent_at and cat <> 'maintenance'), 0)::bigint
  from ex;
end; $$;

