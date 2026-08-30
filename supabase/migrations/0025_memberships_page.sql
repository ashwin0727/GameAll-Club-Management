-- ═══════════════════════════════════════════════════════════════════════════
-- Memberships page — a dedicated hub for viewing/creating memberships.
--
-- Adds two per-membership columns:
--   • created_by       — the manager/owner who created it; NULL = the player
--                        self-registered via a shared link.
--   • monthly_price_inr — owner-set recurring price snapshot at creation;
--                        NULL falls back to the plan's price_inr.
--
-- Plus the read RPCs the page needs: list_memberships (paginated, filtered,
-- sorted, with total_count) and get_membership_page_summary (the KPI tiles
-- with month-over-month deltas).
--
-- The recurring-payment engine (UPI AutoPay mandates, self-registration
-- public flow, owner payouts) is deliberately out of scope here.
-- ═══════════════════════════════════════════════════════════════════════════

alter table memberships
  add column created_by uuid references profiles (id) on delete set null,
  add column monthly_price_inr integer;

comment on column memberships.created_by is
  'The manager/owner who created this membership; NULL means the player self-registered.';
comment on column memberships.monthly_price_inr is
  'Owner-set recurring price snapshot at creation; NULL falls back to the plan price.';

-- ─────────────────────────────────────────────────────────────────────────
-- create_membership — replace to also record created_by (auth.uid()) and an
-- optional owner-set monthly price. Same single write path for assign/renew;
-- history is still never overwritten. Drop+recreate because the argument
-- list changes.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists create_membership(uuid, uuid, uuid, date, payment_status);

create function create_membership(
  p_member_id uuid,
  p_facility_id uuid,
  p_plan_id uuid,
  p_start_date date,
  p_payment_status payment_status default 'created',
  p_monthly_price_inr integer default null
) returns memberships
language plpgsql
as $$
declare
  plan membership_plans;
  result memberships;
  computed_end date;
  computed_status membership_status;
  price integer;
begin
  select * into plan from membership_plans
    where id = p_plan_id and facility_id = p_facility_id and is_active;
  if plan.id is null then
    raise exception 'Membership plan not found for this facility.' using errcode = '23503';
  end if;

  computed_end := p_start_date + plan.duration_days;
  computed_status := case when computed_end >= current_date then 'active' else 'expired' end;
  price := coalesce(nullif(p_monthly_price_inr, 0), plan.price_inr);

  insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date, created_by, monthly_price_inr)
  values (p_facility_id, p_member_id, p_plan_id, computed_status, p_start_date, computed_end, auth.uid(), price)
  returning * into result;

  if price > 0 then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status)
    values (p_facility_id, p_member_id, result.id, price, p_payment_status);
  end if;

  return result;
end;
$$;

grant execute on function create_membership(uuid, uuid, uuid, date, payment_status, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_memberships — one row per membership for the facility. display_status
-- (active / expiring_soon within 30d / expired / cancelled) and days_left are
-- computed here so the UI never re-derives them.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_memberships(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,
  p_plan_id uuid default null,
  p_sort text default 'newest',
  p_limit integer default 10,
  p_offset integer default 0
) returns table (
  membership_id uuid,
  member_id uuid,
  member_name text,
  member_phone text,
  member_email text,
  plan_id uuid,
  plan_name text,
  monthly_price_inr integer,
  display_status text,
  start_date date,
  end_date date,
  days_left integer,
  created_by uuid,
  created_by_name text,
  total_count bigint
)
language sql
stable
as $$
  with base as (
    select
      m.id as membership_id,
      m.member_id,
      mem.full_name as member_name,
      mem.phone as member_phone,
      mem.email as member_email,
      m.plan_id,
      mp.name as plan_name,
      coalesce(m.monthly_price_inr, mp.price_inr) as monthly_price_inr,
      case
        when m.status = 'cancelled' then 'cancelled'
        when m.end_date < current_date then 'expired'
        when m.end_date <= current_date + 30 then 'expiring_soon'
        else 'active'
      end as display_status,
      m.start_date,
      m.end_date,
      (m.end_date - current_date) as days_left,
      m.created_by,
      p.full_name as created_by_name,
      m.created_at
    from memberships m
    join members mem on mem.id = m.member_id
    join membership_plans mp on mp.id = m.plan_id
    left join profiles p on p.id = m.created_by
    where m.facility_id = p_facility_id
      and (
        p_search is null
        or mem.full_name ilike '%' || p_search || '%'
        or mem.phone ilike '%' || p_search || '%'
        or coalesce(mem.email, '') ilike '%' || p_search || '%'
      )
      and (p_plan_id is null or m.plan_id = p_plan_id)
  ),
  filtered as (
    select * from base where p_status is null or display_status = p_status
  )
  select
    membership_id, member_id, member_name, member_phone, member_email,
    plan_id, plan_name, monthly_price_inr, display_status,
    start_date, end_date, days_left, created_by, created_by_name,
    count(*) over () as total_count
  from filtered
  order by
    case when p_sort = 'oldest' then created_at end asc nulls last,
    case when p_sort = 'expiry_asc' then end_date end asc nulls last,
    case when p_sort = 'expiry_desc' then end_date end desc nulls last,
    case when p_sort = 'name' then member_name end asc nulls last,
    created_at desc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0);
$$;

grant execute on function list_memberships(uuid, text, text, uuid, text, integer, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_membership_page_summary — the five KPI tiles + month-over-month deltas.
-- "Total members" = distinct members holding any membership at the facility.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_membership_page_summary(p_facility_id uuid)
returns table (
  total_members bigint,
  total_members_prev bigint,
  active_members bigint,
  expiring_soon bigint,
  expired_members bigint,
  revenue_inr bigint,
  revenue_prev_inr bigint
)
language sql
stable
as $$
  with months as (
    select
      date_trunc('month', current_date)::date as cur_start,
      (date_trunc('month', current_date) - interval '1 month')::date as prev_start
  ),
  m as (
    select
      mm.*,
      (mm.end_date < current_date) as is_expired,
      (mm.status <> 'cancelled' and mm.end_date >= current_date and mm.end_date <= current_date + 30) as is_expiring
    from memberships mm
    where mm.facility_id = p_facility_id
  )
  select
    (select count(distinct member_id) from m),
    (select count(distinct member_id) from m, months where m.created_at < months.cur_start),
    (select count(*) from m where status = 'active' and not is_expired),
    (select count(*) from m where is_expiring),
    (select count(*) from m where status = 'expired' or is_expired),
    coalesce((
      select sum(amount_inr) from payments, months
      where facility_id = p_facility_id and membership_id is not null and status = 'paid'
        and created_at >= months.cur_start
    ), 0),
    coalesce((
      select sum(amount_inr) from payments, months
      where facility_id = p_facility_id and membership_id is not null and status = 'paid'
        and created_at >= months.prev_start and created_at < months.cur_start
    ), 0);
$$;

grant execute on function get_membership_page_summary(uuid) to authenticated;