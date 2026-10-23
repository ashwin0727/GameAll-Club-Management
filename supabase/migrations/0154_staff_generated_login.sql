-- Staff accounts no longer log in with the person's own email.
--
-- A new staff account is created with a generated login "<first name><DDMM of joining><MMSS of creation>@gameall.co"
-- (see the create-staff edge function). The email the owner typed is kept as a contact email only. Existing staff keep
-- logging in with their original email (staff_login stays null; the login shown falls back to profiles.email).
--
--   profiles.first_name / last_name  the name as entered (full_name = first + last)
--   profiles.contact_email           the email entered on the form — never used to sign in
--   profiles.staff_login             the generated login email (null for legacy staff)

alter table profiles
  add column if not exists first_name text,
  add column if not exists last_name text,
  add column if not exists contact_email text,
  add column if not exists staff_login text;

create unique index if not exists profiles_staff_login_idx on profiles (lower(staff_login)) where staff_login is not null;

-- list_staff / get_staff: "email" is now the contact email (falling back to the login for legacy staff); the login is
-- returned separately along with the split name.
drop function if exists list_staff(uuid, text, text, uuid, integer, integer);

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
  login_email text,
  first_name text,
  last_name text,
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
      coalesce(pr.contact_email, pr.email) as email,
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
      fu.created_at as joined_at,
      coalesce(pr.staff_login, pr.email) as login_email,
      pr.first_name,
      pr.last_name
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
        or coalesce(pr.contact_email, '') ilike '%' || trim(p_search) || '%'
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
    'email', coalesce(pr.contact_email, pr.email),
    'loginEmail', coalesce(pr.staff_login, pr.email),
    'firstName', pr.first_name,
    'lastName', pr.last_name,
    'hasGeneratedLogin', pr.staff_login is not null,
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
