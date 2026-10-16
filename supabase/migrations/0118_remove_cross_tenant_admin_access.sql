-- ═══════════════════════════════════════════════════════════════════════════
-- No account may see or change another business's information.
--
-- Every owner who signs up gets profiles.role = 'admin' (handle_new_user), and six places treated that
-- role as "can see / do anything anywhere":
--
--   1. facilities_select_members   — read every facility
--   2. profiles_select_own_or_staff — read every user's profile (any admin OR staff)
--   3. profiles_admin_all          — read, change and delete every profile
--   4. has_permission()            — hold every permission in every facility
--   5. caller_may_grant()          — grant any permission in any facility
--   6. membership_subscriptions_select_staff — read every facility's subscriptions
--
-- All six are replaced here. Access is now only through a facility you OWN or are an ACTIVE member of.
-- profiles.role keeps its meaning as the account type; it no longer widens access to other people's data.
-- Real platform administration can be designed separately later, as its own explicit rule.
--
-- Safe to run repeatedly.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 1. facilities — your own, or ones you're an active member of.
-- ─────────────────────────────────────────────────────────────────────────
drop policy if exists "facilities_select_members" on facilities;
create policy "facilities_select_members" on facilities for select
  using (is_facility_member(id) or owner_id = auth.uid());


-- ─────────────────────────────────────────────────────────────────────────
-- 2 + 3. profiles — your own, plus the people you share a facility with (the team list, coach names,
-- etc.) and the customers who booked at your facility. No more "every admin / staff account reads every profile", and no all-powerful admin policy.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function shares_a_facility_with(p_profile uuid) returns boolean
language sql security definer stable
set search_path = public
as $$
  select exists (
    select 1
    from facility_users me
    join facility_users other on other.facility_id = me.facility_id
    where me.user_id = auth.uid()
      and me.status = 'ACTIVE'
      and other.user_id = p_profile
  )
  -- ...and the customers who booked at a facility the caller belongs to (the schedule shows their names).
  or exists (
    select 1
    from bookings b
    join facility_users me on me.facility_id = b.facility_id
    where me.user_id = auth.uid()
      and me.status = 'ACTIVE'
      and b.member_id = p_profile
  );
$$;

grant execute on function shares_a_facility_with(uuid) to authenticated;

drop policy if exists "profiles_select_own_or_staff" on profiles;
drop policy if exists "profiles_admin_all" on profiles;
create policy "profiles_select_own_or_same_facility" on profiles for select
  using (id = auth.uid() or shares_a_facility_with(id));
-- profiles_update_own (id = auth.uid()) is unchanged.


-- ─────────────────────────────────────────────────────────────────────────
-- 4. has_permission — the facility owner, or an ACTIVE assignment whose role grants the key. Nothing else.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function has_permission(p_facility uuid, p_permission text) returns boolean
language sql security definer stable
set search_path = public
as $$
  select
    exists (
      select 1 from facilities f
      where f.id = p_facility and f.owner_id = auth.uid()
    )
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


-- ─────────────────────────────────────────────────────────────────────────
-- 5. caller_may_grant — an owner of that facility, or a caller granting only what they hold themselves.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function caller_may_grant(p_facility uuid, p_permission_keys text[]) returns boolean
language sql security definer stable
set search_path = public
as $$
  select
    exists (
      select 1 from facility_users
      where facility_id = p_facility and user_id = auth.uid() and status = 'ACTIVE' and role = 'owner'
    )
    or not exists (
      select 1 from unnest(coalesce(p_permission_keys, array[]::text[])) k
      where not has_permission(p_facility, k)
    );
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- 6. membership_subscriptions — the facility's owner or an active member of it.
-- ─────────────────────────────────────────────────────────────────────────
drop policy if exists "membership_subscriptions_select_staff" on membership_subscriptions;
create policy "membership_subscriptions_select_staff" on membership_subscriptions
  for select using (
    exists (
      select 1 from facilities f
      where f.id = membership_subscriptions.facility_id and f.owner_id = auth.uid()
    )
    or is_facility_member(membership_subscriptions.facility_id)
  );
