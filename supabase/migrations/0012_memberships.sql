-- ═══════════════════════════════════════════════════════════════════════════
-- Members & Memberships — closes the gap between the 0001 schema
-- (membership_plans/memberships/payments already existed, fully correct,
-- but had zero service/RPC layer beyond one read-only dashboard aggregate)
-- and an actual assignable/renewable membership flow.
--
-- Reused as-is, unmodified: membership_plans, memberships, payments, their
-- RLS policies, and the existing profiles-based Member account model
-- (a "member" is a full Supabase Auth user with profiles.role = 'member',
-- created via the existing /api/members route — not a new lightweight
-- entity like guest_players).
--
--   facilities → memberships ← profiles (member)
--                    │  └── membership_plans (facility-scoped)
--                    └── payments (facility-scoped)
--
-- Membership history is preserved by design: renewing never overwrites a
-- row, it inserts a new one (see create_membership below) — the same
-- get-or-create-never-mutate-history convention used for bookings.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- create_membership: the single write path for both "assign a plan" and
-- "renew" (renewal is just calling this again with a new start date — it
-- never updates a prior membership row, so history is never lost).
-- Computes end_date from the plan's duration_days (never trust a
-- client-typed expiry date), and records a payment row when the plan has a
-- price, exactly like create_booking captures amount_minor server-side.
-- ─────────────────────────────────────────────────────────────────────────
create function create_membership(
  p_member_id uuid,
  p_facility_id uuid,
  p_plan_id uuid,
  p_start_date date,
  p_payment_status payment_status default 'created'
) returns memberships
language plpgsql
as $$
declare
  plan membership_plans;
  result memberships;
  computed_end date;
  computed_status membership_status;
begin
  select * into plan from membership_plans
    where id = p_plan_id and facility_id = p_facility_id and is_active;
  if plan.id is null then
    raise exception 'Membership plan not found for this facility.' using errcode = '23503';
  end if;

  computed_end := p_start_date + plan.duration_days;
  computed_status := case when computed_end >= current_date then 'active' else 'expired' end;

  insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date)
  values (p_facility_id, p_member_id, p_plan_id, computed_status, p_start_date, computed_end)
  returning * into result;

  if plan.price_inr > 0 then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status)
    values (p_facility_id, p_member_id, result.id, plan.price_inr, p_payment_status);
  end if;

  return result;
end;
$$;

grant execute on function create_membership(uuid, uuid, uuid, date, payment_status) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- cancel_membership: explicit terminal state, distinct from "expired"
-- (which just means time ran out) — matches membership_status already
-- having both 'expired' and 'cancelled' values.
-- ─────────────────────────────────────────────────────────────────────────
create function cancel_membership(p_membership_id uuid) returns memberships
language plpgsql
as $$
declare
  result memberships;
begin
  update memberships set status = 'cancelled' where id = p_membership_id
  returning * into result;
  if result.id is null then
    raise exception 'Membership not found' using errcode = 'P0002';
  end if;
  return result;
end;
$$;

grant execute on function cancel_membership(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- search_facility_members: one row per member, their most recent
-- membership at this facility — the source of truth for "who is a member
-- of this facility" (facility scoping comes from the memberships
-- relationship, not from a global profiles.role check, so this stays
-- correctly tenant-isolated even though profiles itself is not
-- facility-scoped). Runs as the caller (not security definer), so the
-- existing memberships/profiles RLS still governs access — this can never
-- return another facility's members.
-- ─────────────────────────────────────────────────────────────────────────
create function search_facility_members(
  p_facility_id uuid,
  p_query text default null,
  p_limit integer default 50,
  p_offset integer default 0
) returns table (
  member_id uuid,
  full_name text,
  phone text,
  email text,
  membership_id uuid,
  plan_id uuid,
  plan_name text,
  start_date date,
  end_date date,
  status membership_status
)
language sql
stable
as $$
  with latest as (
    select distinct on (member_id) *
    from memberships
    where facility_id = p_facility_id
    order by member_id, end_date desc
  )
  select p.id, p.full_name, p.phone, p.email,
         l.id, l.plan_id, mp.name, l.start_date, l.end_date, l.status
  from latest l
  join profiles p on p.id = l.member_id
  join membership_plans mp on mp.id = l.plan_id
  where p_query is null or trim(p_query) = ''
     or p.full_name ilike '%' || p_query || '%'
     or p.phone ilike '%' || p_query || '%'
     or p.email ilike '%' || p_query || '%'
  order by l.end_date desc
  limit p_limit offset p_offset;
$$;

grant execute on function search_facility_members(uuid, text, integer, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_member_stats: every number the Member Profile screen shows, derived
-- live from real bookings scoped to this facility — mirrors
-- get_guest_stats exactly, no duplicated logic.
-- ─────────────────────────────────────────────────────────────────────────
create function get_member_stats(p_member_id uuid, p_facility_id uuid) returns table (
  total_visits bigint,
  total_bookings bigint,
  last_visit timestamptz,
  total_amount_minor bigint,
  pending_amount_minor bigint,
  sports jsonb
)
language sql
stable
as $$
  select
    count(*) filter (where b.status in ('confirmed', 'completed')) as total_visits,
    count(*) as total_bookings,
    max(b.start_time) filter (where b.status in ('confirmed', 'completed')) as last_visit,
    coalesce(sum(b.amount_minor) filter (where b.status in ('confirmed', 'completed')), 0) as total_amount_minor,
    coalesce(
      sum(b.amount_minor) filter (
        where b.status in ('confirmed', 'completed') and b.payment_status = 'PENDING'
      ), 0
    ) as pending_amount_minor,
    coalesce(
      jsonb_agg(distinct jsonb_build_object('sportId', s.id, 'sportName', s.name))
        filter (where s.id is not null),
      '[]'::jsonb
    ) as sports
  from bookings b
  left join facility_sports fs on fs.id = b.facility_sport_id
  left join sports s on s.id = fs.sport_id
  where b.member_id = p_member_id and b.facility_id = p_facility_id;
$$;

grant execute on function get_member_stats(uuid, uuid) to authenticated;