-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: list_roles (0075) raises "column reference \"id\" is ambiguous".
--
-- `returns table (id uuid, key text, name text, ...)` makes every one of those
-- names a plpgsql-scoped variable for the whole function body. The `all_roles`
-- CTE selected `id, key, name, ...` unqualified from `resolved`/`customs` —
-- with a same-named table column AND a same-named plpgsql variable both in
-- scope, Postgres's default `#variable_conflict error` behavior raises the
-- ambiguity error the first time this exact query plan is built, rather than
-- silently picking one. Every reference needs an explicit table qualifier.
-- ═══════════════════════════════════════════════════════════════════════════

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

grant execute on function list_roles(uuid) to authenticated;
