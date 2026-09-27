-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: list_roles (0075, syntax-fixed in 0097) shows a custom role twice and
-- swallows the Staff tier's own row whenever a facility has a custom role
-- built on the 'staff' base tier — which is every custom role, since 0072's
-- own schema comment says custom rows always get base_role='staff' (only a
-- genuine system role / facility override of a tier has `key` set to that
-- tier's name).
--
-- The `resolved` CTE's join only checked `r.base_role = t.tier`, so it
-- matched ANY custom role with base_role='staff' as if it were the facility's
-- override of the Staff tier itself — the same role then also matched
-- `customs`' plain "facility-scoped, not system, not template" filter,
-- appearing in the UNION ALL twice (once mislabeled as Staff, once correctly
-- as itself) while the real Staff tier row never showed up at all.
--
-- Fix: require `r.key = t.tier::text` on that branch too, exactly like the
-- global-template branch already does — only a role explicitly keyed to a
-- tier can stand in for that tier.
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

grant execute on function list_roles(uuid) to authenticated;
