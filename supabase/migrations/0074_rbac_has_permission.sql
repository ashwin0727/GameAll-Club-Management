-- ═══════════════════════════════════════════════════════════════════════════
-- has_permission — the one authorization check every sensitive operation
-- routes through — and a status check folded into the existing membership
-- helpers so a deactivated staff member fails every facility policy at once.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- is_facility_member / has_facility_role — unchanged signatures, now also
-- require the assignment to be ACTIVE. Every existing row was backfilled to
-- ACTIVE in 0073, so no current access changes; a future INACTIVE row loses
-- access to ~40 policies in one place.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function is_facility_member(target_facility uuid) returns boolean
language sql security definer stable
set search_path = public
as $$
  select exists (
    select 1 from facility_users
    where facility_id = target_facility
      and user_id = auth.uid()
      and status = 'ACTIVE'
  );
$$;

create or replace function has_facility_role(target_facility uuid, allowed facility_role[])
returns boolean
language sql security definer stable
set search_path = public
as $$
  select exists (
    select 1 from facility_users
    where facility_id = target_facility
      and user_id = auth.uid()
      and status = 'ACTIVE'
      and role = any (allowed)
  );
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- effective_role_id — the role row a user's permissions resolve against for
-- a facility:
--   1. an explicit custom role on the assignment (facility_users.role_id), or
--   2. the facility's own override of the base-tier template, or
--   3. the shared system template for that tier.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function effective_role_id(p_facility uuid, p_user uuid) returns uuid
language sql security definer stable
set search_path = public
as $$
  select coalesce(
    fu.role_id,
    (select r.id from roles r
       where r.facility_id = p_facility and r.base_role = fu.role and r.is_active
       order by r.created_at limit 1),
    (select r.id from roles r
       where r.facility_id is null and r.key = fu.role::text and not r.is_template
       limit 1)
  )
  from facility_users fu
  where fu.facility_id = p_facility and fu.user_id = p_user and fu.status = 'ACTIVE';
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- has_permission(facility, permission_key) — true when the signed-in user
-- may perform that action in that facility.
--
--   * platform admin (profiles.role = 'admin') — bypass, matching role()
--     usage elsewhere.
--   * facility owner — always full access (anchors last-owner protection).
--   * everyone else — ACTIVE assignment whose resolved role grants the key.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function has_permission(p_facility uuid, p_permission text) returns boolean
language sql security definer stable
set search_path = public
as $$
  select
    coalesce(role() = 'admin', false)
    or exists (
      select 1 from facility_users fu
      where fu.facility_id = p_facility
        and fu.user_id = auth.uid()
        and fu.status = 'ACTIVE'
        and (
          fu.role = 'owner'
          or exists (
            select 1 from role_permissions rp
            where rp.role_id = effective_role_id(p_facility, auth.uid())
              and rp.permission_key = p_permission
          )
        )
    );
$$;

grant execute on function has_permission(uuid, text) to authenticated;
grant execute on function effective_role_id(uuid, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- my_facility_permissions — the flat list of permission keys the signed-in
-- user holds for a facility. The web / Flutter session loads this once and
-- gates UI with it (the database stays authoritative regardless).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function my_facility_permissions(p_facility uuid) returns setof text
language sql security definer stable
set search_path = public
as $$
  select p.key
  from permissions p
  where has_permission(p_facility, p.key);
$$;

grant execute on function my_facility_permissions(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- mark_password_reset_complete — called by the client immediately after a
-- staff member sets their own password on first sign-in. Clears the forced
-- flag and activates any assignments that were waiting on it.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function mark_password_reset_complete() returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update profiles set must_reset_password = false where id = auth.uid();
  update facility_users
    set status = 'ACTIVE', activated_at = coalesce(activated_at, now())
    where user_id = auth.uid() and status = 'INVITED';
end;
$$;

grant execute on function mark_password_reset_complete() to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- record_my_login — bumps last_login_at on the signed-in user's assignments.
-- Called by the session bootstrap on both clients.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function record_my_login() returns void
language sql
security definer
set search_path = public
as $$
  update facility_users set last_login_at = now() where user_id = auth.uid() and status = 'ACTIVE';
$$;

grant execute on function record_my_login() to authenticated;
