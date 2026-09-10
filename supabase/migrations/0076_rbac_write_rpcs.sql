-- ═══════════════════════════════════════════════════════════════════════════
-- Staff / Roles / Permissions — write RPCs.
--
-- Every mutation is SECURITY DEFINER and self-enforces:
--   * the caller's permission (USERS_MANAGE_ROLES / USERS_MANAGE_FACILITY_
--     ACCESS / USERS_DEACTIVATE / USERS_EDIT) via has_permission,
--   * no privilege escalation — a non-owner can only grant permissions they
--     themselves hold,
--   * last-active-owner protection,
--   * optimistic locking on role edits,
--   * an audit row via log_security_event.
-- ═══════════════════════════════════════════════════════════════════════════


create or replace function is_last_active_owner(p_facility uuid, p_user uuid) returns boolean
language sql security definer stable
set search_path = public
as $$
  select
    exists (select 1 from facility_users where facility_id = p_facility and user_id = p_user and role = 'owner' and status = 'ACTIVE')
    and (select count(*) from facility_users where facility_id = p_facility and role = 'owner' and status = 'ACTIVE') <= 1;
$$;


-- A non-owner caller may only assign a permission set that is a subset of
-- their own permissions for the facility (spec §18).
create or replace function caller_may_grant(p_facility uuid, p_permission_keys text[]) returns boolean
language sql security definer stable
set search_path = public
as $$
  select
    exists (
      select 1 from facility_users
      where facility_id = p_facility and user_id = auth.uid() and status = 'ACTIVE' and role = 'owner'
    )
    or coalesce(role() = 'admin', false)
    or not exists (
      select 1 from unnest(coalesce(p_permission_keys, array[]::text[])) k
      where not has_permission(p_facility, k)
    );
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- The facility-scoped, editable copy of a base-tier role. If the facility
-- already has its own override it is returned; otherwise the shared system
-- template is copied (permissions and all) and the copy returned.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function ensure_facility_role_copy(p_facility uuid, p_system_role_id uuid) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  sys roles;
  copy_id uuid;
begin
  select * into sys from roles where id = p_system_role_id;
  if sys.id is null or sys.facility_id is not null then
    return p_system_role_id; -- already facility-scoped (or bad id)
  end if;

  select id into copy_id from roles
    where facility_id = p_facility and key = sys.key and not is_template;
  if copy_id is not null then
    return copy_id;
  end if;

  insert into roles (facility_id, key, base_role, name, description, is_system, is_active, created_by)
  values (p_facility, sys.key, sys.base_role, sys.name, sys.description, true, sys.is_active, auth.uid())
  returning id into copy_id;

  insert into role_permissions (role_id, permission_key)
  select copy_id, permission_key from role_permissions where role_id = sys.id;

  return copy_id;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- create_role — a new custom role, optionally seeded from a template.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function create_role(
  p_facility_id uuid,
  p_name text,
  p_description text default null,
  p_permission_keys text[] default array[]::text[],
  p_from_template_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  keys text[];
begin
  if not has_permission(p_facility_id, 'USERS_MANAGE_ROLES') then
    raise exception 'You don''t have permission to manage roles.' using errcode = '42501';
  end if;
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'A role needs a name.' using errcode = '23514';
  end if;

  keys := p_permission_keys;
  if p_from_template_id is not null and (keys is null or array_length(keys, 1) is null) then
    select array_agg(permission_key) into keys from role_permissions where role_id = p_from_template_id;
  end if;
  keys := coalesce(keys, array[]::text[]);

  if not caller_may_grant(p_facility_id, keys) then
    raise exception 'You can only grant permissions you hold yourself.' using errcode = '42501';
  end if;

  insert into roles (facility_id, key, base_role, name, description, is_system, is_active, created_by)
  values (p_facility_id, null, 'staff', trim(p_name), nullif(trim(coalesce(p_description, '')), ''), false, true, auth.uid())
  returning id into new_id;

  insert into role_permissions (role_id, permission_key)
  select new_id, k from unnest(keys) k
  where exists (select 1 from permissions p where p.key = k)
  on conflict do nothing;

  perform log_security_event(p_facility_id, 'ROLE_CREATED', 'New role created: ' || trim(p_name),
    null, new_id, jsonb_build_object('permissionCount', array_length(keys, 1)));

  return new_id;
end;
$$;

grant execute on function create_role(uuid, text, text, text[], uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- update_role — rename / re-describe / toggle active / replace permissions.
-- A system template is edited per-facility via copy-on-write; its name and
-- description stay fixed.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function update_role(
  p_role_id uuid,
  p_facility_id uuid,
  p_name text default null,
  p_description text default null,
  p_is_active boolean default null,
  p_permission_keys text[] default null,
  p_expected_version integer default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  r roles;
  target_id uuid;
  keys text[];
begin
  if not has_permission(p_facility_id, 'USERS_MANAGE_ROLES') then
    raise exception 'You don''t have permission to manage roles.' using errcode = '42501';
  end if;

  select * into r from roles where id = p_role_id;
  if r.id is null then
    raise exception 'Role not found.' using errcode = 'P0002';
  end if;
  if r.facility_id is not null and r.facility_id <> p_facility_id then
    raise exception 'That role belongs to another facility.' using errcode = '42501';
  end if;
  if p_expected_version is not null and r.facility_id is not null and r.version <> p_expected_version then
    raise exception 'Another administrator updated this role. Refresh and try again.' using errcode = '40001';
  end if;

  -- Editing a shared system template: work on this facility's own copy.
  target_id := case when r.facility_id is null then ensure_facility_role_copy(p_facility_id, p_role_id) else p_role_id end;
  select * into r from roles where id = target_id;

  keys := p_permission_keys;
  if keys is not null and not caller_may_grant(p_facility_id, keys) then
    raise exception 'You can only grant permissions you hold yourself.' using errcode = '42501';
  end if;

  -- Deactivating a role that active staff still use is blocked (spec §15).
  if p_is_active = false and exists (
    select 1 from facility_users fu
    where fu.facility_id = p_facility_id and fu.status = 'ACTIVE'
      and (fu.role_id = target_id or (fu.role_id is null and r.key is not null and fu.role::text = r.key))
  ) then
    raise exception 'This role cannot be deactivated because it is assigned to active staff.' using errcode = '23503';
  end if;

  update roles set
    name = case when is_system then name else coalesce(nullif(trim(coalesce(p_name, '')), ''), name) end,
    description = case when is_system then description else coalesce(p_description, description) end,
    is_active = coalesce(p_is_active, is_active),
    version = version + 1,
    updated_at = now()
  where id = target_id
  returning * into r;

  if keys is not null then
    delete from role_permissions where role_id = target_id;
    insert into role_permissions (role_id, permission_key)
    select target_id, k from unnest(keys) k
    where exists (select 1 from permissions p where p.key = k);

    perform log_security_event(p_facility_id, 'ROLE_PERMISSIONS_UPDATED',
      'Permissions updated for ' || r.name, null, target_id,
      jsonb_build_object('permissionCount', array_length(keys, 1)));
  else
    perform log_security_event(p_facility_id, 'ROLE_UPDATED', r.name || ' role updated', null, target_id, '{}'::jsonb);
  end if;

  return target_id;
end;
$$;

grant execute on function update_role(uuid, uuid, text, text, boolean, text[], integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- delete_role — only a custom role with no assignments, ever.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function delete_role(p_role_id uuid, p_facility_id uuid) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r roles;
begin
  if not has_permission(p_facility_id, 'USERS_MANAGE_ROLES') then
    raise exception 'You don''t have permission to manage roles.' using errcode = '42501';
  end if;
  select * into r from roles where id = p_role_id;
  if r.id is null then
    raise exception 'Role not found.' using errcode = 'P0002';
  end if;
  if r.is_system or r.facility_id is null then
    raise exception 'System roles cannot be deleted.' using errcode = '42501';
  end if;
  if r.facility_id <> p_facility_id then
    raise exception 'That role belongs to another facility.' using errcode = '42501';
  end if;
  if exists (select 1 from facility_users where role_id = p_role_id) then
    raise exception 'This role cannot be removed because it is assigned to staff.' using errcode = '23503';
  end if;

  delete from roles where id = p_role_id;
  perform log_security_event(p_facility_id, 'ROLE_DELETED', 'Role removed: ' || r.name, null, null, '{}'::jsonb);
end;
$$;

grant execute on function delete_role(uuid, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- assign_staff_role — change what a staff member's role is in this facility.
-- p_role_id may be a system template or a facility custom role.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function assign_staff_role(
  p_facility_id uuid,
  p_user_id uuid,
  p_role_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_role roles;
  fu facility_users;
  new_role facility_role;
  new_role_id uuid;
begin
  if not has_permission(p_facility_id, 'USERS_MANAGE_ROLES') then
    raise exception 'You don''t have permission to manage roles.' using errcode = '42501';
  end if;

  select * into fu from facility_users where facility_id = p_facility_id and user_id = p_user_id;
  if fu.user_id is null then
    raise exception 'That staff member is not part of this facility.' using errcode = 'P0002';
  end if;

  select * into target_role from roles where id = p_role_id;
  if target_role.id is null or target_role.is_template then
    raise exception 'Choose a valid role.' using errcode = '23503';
  end if;
  if target_role.facility_id is not null and target_role.facility_id <> p_facility_id then
    raise exception 'That role belongs to another facility.' using errcode = '42501';
  end if;

  -- Moving the last active owner off 'owner' would lock the facility out.
  if fu.role = 'owner' and coalesce(target_role.base_role, 'staff') <> 'owner'
     and is_last_active_owner(p_facility_id, p_user_id) then
    raise exception 'You can''t change the role of the last active owner.' using errcode = '23514';
  end if;

  -- A non-owner cannot hand out more than they hold.
  if not caller_may_grant(p_facility_id,
       (select coalesce(array_agg(permission_key), array[]::text[]) from role_permissions where role_id = p_role_id)) then
    raise exception 'You can only assign a role whose permissions you hold yourself.' using errcode = '42501';
  end if;

  if target_role.facility_id is null and not target_role.is_system then
    -- shouldn't happen (templates excluded above), guard anyway
    raise exception 'Choose a valid role.' using errcode = '23503';
  end if;

  new_role := coalesce(target_role.base_role, 'staff');
  new_role_id := case when target_role.is_system then null else target_role.id end;

  update facility_users
    set role = new_role, role_id = new_role_id, updated_at = now()
    where facility_id = p_facility_id and user_id = p_user_id;

  perform log_security_event(p_facility_id, 'STAFF_ROLE_CHANGED',
    'Role changed to ' || target_role.name, p_user_id, target_role.id,
    jsonb_build_object('from', coalesce((select name from roles where id = fu.role_id), initcap(fu.role::text)),
                       'to', target_role.name));
end;
$$;

grant execute on function assign_staff_role(uuid, uuid, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- set_staff_status — activate / deactivate a staff member's access.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function set_staff_status(
  p_facility_id uuid,
  p_user_id uuid,
  p_status text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  fu facility_users;
begin
  if not has_permission(p_facility_id, 'USERS_DEACTIVATE') then
    raise exception 'You don''t have permission to change staff status.' using errcode = '42501';
  end if;
  if p_status not in ('ACTIVE', 'INACTIVE') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  select * into fu from facility_users where facility_id = p_facility_id and user_id = p_user_id;
  if fu.user_id is null then
    raise exception 'That staff member is not part of this facility.' using errcode = 'P0002';
  end if;

  if p_status = 'INACTIVE' and is_last_active_owner(p_facility_id, p_user_id) then
    raise exception 'You can''t deactivate the last active owner.' using errcode = '23514';
  end if;

  update facility_users
    set status = p_status,
        activated_at = case when p_status = 'ACTIVE' then coalesce(activated_at, now()) else activated_at end,
        updated_at = now()
    where facility_id = p_facility_id and user_id = p_user_id;

  perform log_security_event(p_facility_id,
    case when p_status = 'ACTIVE' then 'STAFF_ACTIVATED' else 'STAFF_DEACTIVATED' end,
    case when p_status = 'ACTIVE' then 'Staff account reactivated' else 'Staff account deactivated' end,
    p_user_id, null, '{}'::jsonb);
end;
$$;

grant execute on function set_staff_status(uuid, uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- update_staff_profile — the assignment's title / notes (the Edit action).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function update_staff_profile(
  p_facility_id uuid,
  p_user_id uuid,
  p_title text default null,
  p_notes text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not has_permission(p_facility_id, 'USERS_EDIT') then
    raise exception 'You don''t have permission to edit staff.' using errcode = '42501';
  end if;
  update facility_users
    set title = nullif(trim(coalesce(p_title, '')), ''),
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        updated_at = now()
    where facility_id = p_facility_id and user_id = p_user_id;
  if not found then
    raise exception 'That staff member is not part of this facility.' using errcode = 'P0002';
  end if;
  perform log_security_event(p_facility_id, 'STAFF_PROFILE_UPDATED', 'Staff profile updated', p_user_id, null, '{}'::jsonb);
end;
$$;

grant execute on function update_staff_profile(uuid, uuid, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- add_facility_access / remove_facility_access — a staff member's access to
-- one facility. Granting to a *new* person (no auth account) goes through the
-- create-staff edge function; this links someone who already has an account
-- and is visible to the caller.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function add_facility_access(
  p_facility_id uuid,
  p_user_id uuid,
  p_role_id uuid,
  p_is_primary boolean default false
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_role roles;
begin
  if not has_permission(p_facility_id, 'USERS_MANAGE_FACILITY_ACCESS') then
    raise exception 'You don''t have permission to manage facility access.' using errcode = '42501';
  end if;
  if not exists (select 1 from profiles where id = p_user_id) then
    raise exception 'That person does not have a GameAll account.' using errcode = 'P0002';
  end if;
  if exists (select 1 from facility_users where facility_id = p_facility_id and user_id = p_user_id) then
    raise exception 'That person already has access to this facility.' using errcode = '23505';
  end if;

  select * into target_role from roles where id = p_role_id;
  if target_role.id is null or target_role.is_template then
    raise exception 'Choose a valid role.' using errcode = '23503';
  end if;
  if not caller_may_grant(p_facility_id,
       (select coalesce(array_agg(permission_key), array[]::text[]) from role_permissions where role_id = p_role_id)) then
    raise exception 'You can only assign a role whose permissions you hold yourself.' using errcode = '42501';
  end if;

  if p_is_primary then
    update facility_users set is_primary = false, updated_at = now() where user_id = p_user_id;
  end if;

  insert into facility_users (facility_id, user_id, role, role_id, status, is_primary, invited_by, invited_at, activated_at)
  values (
    p_facility_id, p_user_id, coalesce(target_role.base_role, 'staff'),
    case when target_role.is_system then null else target_role.id end,
    'ACTIVE', p_is_primary, auth.uid(), now(), now()
  );

  perform log_security_event(p_facility_id, 'FACILITY_ACCESS_GRANTED',
    'Access granted to this facility', p_user_id, target_role.id, '{}'::jsonb);
end;
$$;

grant execute on function add_facility_access(uuid, uuid, uuid, boolean) to authenticated;


create or replace function remove_facility_access(p_facility_id uuid, p_user_id uuid) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not has_permission(p_facility_id, 'USERS_MANAGE_FACILITY_ACCESS') then
    raise exception 'You don''t have permission to manage facility access.' using errcode = '42501';
  end if;
  if not exists (select 1 from facility_users where facility_id = p_facility_id and user_id = p_user_id) then
    raise exception 'That person does not have access to this facility.' using errcode = 'P0002';
  end if;
  if is_last_active_owner(p_facility_id, p_user_id) then
    raise exception 'You can''t remove the last active owner''s access.' using errcode = '23514';
  end if;

  delete from facility_users where facility_id = p_facility_id and user_id = p_user_id;

  perform log_security_event(p_facility_id, 'FACILITY_ACCESS_REMOVED', 'Access to this facility removed', p_user_id, null, '{}'::jsonb);
end;
$$;

grant execute on function remove_facility_access(uuid, uuid) to authenticated;
