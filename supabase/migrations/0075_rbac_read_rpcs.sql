-- ═══════════════════════════════════════════════════════════════════════════
-- Staff / Roles / Permissions — read RPCs.
--
-- All of these gate on USERS_VIEW (has_permission) so a staff member without
-- that permission cannot enumerate the team, roles or the audit trail — even
-- with a hand-crafted request.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- The number of facilities a person is assigned to (any status), regardless
-- of whether the caller is a member of those other facilities. SECURITY
-- DEFINER because facility_users RLS would otherwise hide the other rows.
-- Only ever exposed as a count, never the other facilities' details.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function staff_facility_count(p_user_id uuid) returns integer
language sql security definer stable
set search_path = public
as $$
  select count(*)::integer from facility_users where user_id = p_user_id;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- list_staff — one row per person assigned to this facility.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_staff(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,      -- ACTIVE | INACTIVE | INVITED
  p_role_id uuid default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  assignment_id uuid,
  user_id uuid,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  role_id uuid,
  role_name text,
  base_role facility_role,
  status text,
  is_primary boolean,
  title text,
  facility_count integer,
  last_login_at timestamptz,
  joined_at timestamptz,
  total_count bigint
)
language plpgsql
stable
as $$
begin
  if not has_permission(p_facility_id, 'USERS_VIEW') then
    raise exception 'You don''t have permission to view staff.' using errcode = '42501';
  end if;

  return query
  with rows as (
    select
      fu.id as assignment_id,
      fu.user_id,
      pr.full_name,
      pr.email,
      pr.phone,
      pr.avatar_url,
      fu.role_id,
      coalesce(cr.name, tpl.name, initcap(fu.role::text)) as role_name,
      fu.role as base_role,
      fu.status,
      fu.is_primary,
      fu.title,
      staff_facility_count(fu.user_id) as facility_count,
      fu.last_login_at,
      fu.created_at as joined_at
    from facility_users fu
    join profiles pr on pr.id = fu.user_id
    left join roles cr on cr.id = fu.role_id
    left join roles tpl on tpl.facility_id is null and tpl.key = fu.role::text and not tpl.is_template
    where fu.facility_id = p_facility_id
      and (p_status is null or fu.status = p_status)
      and (
        p_role_id is null
        or fu.role_id = p_role_id
        or (fu.role_id is null and exists (
              select 1 from roles r where r.id = p_role_id and r.key = fu.role::text))
      )
      and (
        p_search is null or trim(p_search) = ''
        or pr.full_name ilike '%' || trim(p_search) || '%'
        or pr.email ilike '%' || trim(p_search) || '%'
        or coalesce(pr.phone, '') ilike '%' || trim(p_search) || '%'
      )
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by
    case r.status when 'INVITED' then 0 when 'ACTIVE' then 1 else 2 end,
    r.full_name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_staff(uuid, text, text, uuid, integer, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_staff — one staff member in full for the details screen.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_staff(p_facility_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  result jsonb;
begin
  if not has_permission(p_facility_id, 'USERS_VIEW') then
    raise exception 'You don''t have permission to view staff.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'userId', pr.id,
    'fullName', pr.full_name,
    'email', pr.email,
    'phone', pr.phone,
    'avatarUrl', pr.avatar_url,
    'mustResetPassword', pr.must_reset_password,
    'assignment', (
      select jsonb_build_object(
        'assignmentId', fu.id,
        'roleId', fu.role_id,
        'roleName', coalesce(cr.name, initcap(fu.role::text)),
        'baseRole', fu.role,
        'status', fu.status,
        'isPrimary', fu.is_primary,
        'title', fu.title,
        'notes', fu.notes,
        'joinedAt', fu.created_at,
        'invitedAt', fu.invited_at,
        'activatedAt', fu.activated_at,
        'lastLoginAt', fu.last_login_at
      )
      from facility_users fu
      left join roles cr on cr.id = fu.role_id
      where fu.facility_id = p_facility_id and fu.user_id = p_user_id
    ),
    'facilityAccess', coalesce((
      select jsonb_agg(jsonb_build_object(
        'facilityId', f.id,
        'facilityName', f.name,
        'roleId', a.role_id,
        'roleName', coalesce(acr.name, initcap(a.role::text)),
        'baseRole', a.role,
        'status', a.status,
        'isPrimary', a.is_primary
      ) order by a.is_primary desc, f.name)
      from facility_users a
      join facilities f on f.id = a.facility_id
      left join roles acr on acr.id = a.role_id
      where a.user_id = p_user_id
        -- only facilities the caller can also administer
        and has_permission(a.facility_id, 'USERS_VIEW')
    ), '[]'::jsonb),
    'permissions', coalesce((
      select jsonb_agg(k order by k) from my_facility_permissions_for(p_facility_id, p_user_id) k
    ), '[]'::jsonb),
    'recentActivity', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'event', e.event, 'summary', e.summary,
        'actorName', ap.full_name, 'createdAt', e.created_at, 'detail', e.detail
      ) order by e.created_at desc)
      from (
        select * from security_events se
        where se.facility_id = p_facility_id and se.target_user_id = p_user_id
        order by se.created_at desc limit 20
      ) e
      left join profiles ap on ap.id = e.actor
    ), '[]'::jsonb)
  ) into result
  from profiles pr
  where pr.id = p_user_id
    and exists (select 1 from facility_users fu where fu.facility_id = p_facility_id and fu.user_id = p_user_id);

  if result is null then
    raise exception 'Staff member not found.' using errcode = 'P0002';
  end if;
  return result;
end;
$$;

grant execute on function get_staff(uuid, uuid) to authenticated;


-- Resolve another user's permission keys for a facility (for the details
-- screen's "Permission summary"). SECURITY DEFINER; the caller has already
-- been checked for USERS_VIEW by get_staff.
create or replace function my_facility_permissions_for(p_facility uuid, p_user uuid) returns setof text
language sql security definer stable
set search_path = public
as $$
  select rp.permission_key
  from role_permissions rp
  where rp.role_id = effective_role_id(p_facility, p_user)
  union
  -- a facility owner implicitly holds everything
  select p.key from permissions p
  where exists (
    select 1 from facility_users fu
    where fu.facility_id = p_facility and fu.user_id = p_user
      and fu.status = 'ACTIVE' and fu.role = 'owner'
  );
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- list_roles — the Roles tab. System templates (resolved to this facility's
-- override where one exists) plus the facility's custom roles.
-- ─────────────────────────────────────────────────────────────────────────
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
  if not has_permission(p_facility_id, 'USERS_VIEW') then
    raise exception 'You don''t have permission to view roles.' using errcode = '42501';
  end if;

  return query
  with resolved as (
    -- the effective row for each of the three base tiers
    select distinct on (t.tier)
      r.id, r.key, r.name, r.description, r.is_system, false as is_custom, r.is_active, r.version, t.tier
    from (values ('owner'::facility_role), ('manager'), ('staff')) t(tier)
    join roles r on
      (r.facility_id = p_facility_id and r.base_role = t.tier and not r.is_template)
      or (r.facility_id is null and r.key = t.tier::text and not r.is_template)
    order by t.tier, (r.facility_id is not null) desc
  ),
  customs as (
    select r.id, r.key, r.name, r.description, r.is_system, true as is_custom, r.is_active, r.version, null::facility_role as tier
    from roles r
    where r.facility_id = p_facility_id and not r.is_system and not r.is_template
  ),
  all_roles as (
    select id, key, name, description, is_system, is_custom, is_active, version, tier from resolved
    union all
    select id, key, name, description, is_system, is_custom, is_active, version, tier from customs
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

grant execute on function list_roles(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_role — a role plus its permission keys.
-- ─────────────────────────────────────────────────────────────────────────
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
  if r.facility_id is not null and not has_permission(r.facility_id, 'USERS_VIEW') then
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

grant execute on function get_role(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- list_role_templates — the "Pre-configured" presets on Create Role.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_role_templates()
returns table (id uuid, name text, description text, permission_keys jsonb)
language sql
stable
as $$
  select r.id, r.name, r.description,
    coalesce((select jsonb_agg(rp.permission_key order by rp.permission_key)
              from role_permissions rp where rp.role_id = r.id), '[]'::jsonb)
  from roles r
  where r.facility_id is null and r.is_template
  order by r.name;
$$;

grant execute on function list_role_templates() to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- The full permission catalogue for the matrix UI, grouped by module.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_permissions()
returns table (key text, module text, action text, label text, description text, is_dangerous boolean, sort_order integer)
language sql
stable
as $$
  select key, module, action, label, description, is_dangerous, sort_order
  from permissions order by sort_order, key;
$$;

grant execute on function list_permissions() to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- list_security_events — the Access History screen.
-- ─────────────────────────────────────────────────────────────────────────
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
  if not has_permission(p_facility_id, 'USERS_VIEW') then
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

grant execute on function list_security_events(uuid, text, uuid, timestamptz, timestamptz, integer, integer) to authenticated;
