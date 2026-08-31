-- ═══════════════════════════════════════════════════════════════════════════
-- Memberships page rework — Phase 6.
--
--   • list_memberships    : status is now payment-driven, not date-window
--     driven — 'payment_not_initiated' | 'active' | 'inactive'. Sort loses
--     'newest' and defaults to 'oldest'; 'expiry_asc' is renamed
--     'next_payment'. The RETURNS shape is unchanged (created_by /
--     created_by_name / days_left stay but the UI stops reading them).
--   • get_membership_page_summary : four KPIs instead of five —
--     expiring_soon + expired_members collapse into a single
--     inactive_members. RETURNS shape changes, so drop+recreate.
--   • delete_member       : hard-delete a member that has NO booking or
--     settled-payment history (a mistaken / junk entry). Owner/manager only.
--
-- Status rules (shared by both reads):
--   inactive              = membership cancelled OR end_date < today
--   payment_not_initiated = still current, fee > 0, no 'paid' payment yet
--   active                = still current AND (a 'paid' payment exists OR fee is 0)
-- "Next payment date" shown in the UI is simply memberships.end_date — a
-- recurring subscription already rolls that forward on each charge
-- (0026), and a one-off membership's end_date is when renewal falls due.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- list_memberships — payment-driven status + new sort set. Body change on a
-- SQL function is a replace, but keep the drop explicit alongside 0027/0028.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists list_memberships(uuid, text, text, uuid, text, integer, integer);

create function list_memberships(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,
  p_plan_id uuid default null,
  p_sort text default 'oldest',
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
  batch_name text,
  batch_days integer[],
  batch_start time,
  batch_end time,
  batch_court text,
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
      coalesce(m.name, mp.name, 'Membership') as plan_name,
      coalesce(m.monthly_price_inr, m.membership_fee_inr, mp.price_inr, 0) as monthly_price_inr,
      case
        when m.status = 'cancelled' or m.end_date < current_date then 'inactive'
        when coalesce(m.total_amount_inr, m.membership_fee_inr, mp.price_inr, 0) > 0
          and not exists (
            select 1 from payments pp
            where pp.membership_id = m.id and pp.status = 'paid'
          )
          then 'payment_not_initiated'
        else 'active'
      end as display_status,
      m.start_date,
      m.end_date,
      (m.end_date - current_date) as days_left,
      m.created_by,
      p.full_name as created_by_name,
      coalesce(b.name, case when m.time_slot_start is not null then 'Time slot' end) as batch_name,
      b.days_of_week as batch_days,
      coalesce(b.start_time, m.time_slot_start) as batch_start,
      coalesce(b.end_time, m.time_slot_end) as batch_end,
      bc.name as batch_court,
      m.created_at
    from memberships m
    join members mem on mem.id = m.member_id
    left join membership_plans mp on mp.id = m.plan_id
    left join profiles p on p.id = m.created_by
    left join lateral (
      select bm.batch_id
      from membership_batch_members bm
      where bm.membership_id = m.id
      order by bm.created_at
      limit 1
    ) bml on true
    left join membership_batches b on b.id = bml.batch_id
    left join courts bc on bc.id = b.court_id
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
    batch_name, batch_days, batch_start, batch_end, batch_court,
    count(*) over () as total_count
  from filtered
  order by
    case when p_sort = 'next_payment' then end_date end asc nulls last,
    case when p_sort = 'name' then member_name end asc nulls last,
    created_at asc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0);
$$;

grant execute on function list_memberships(uuid, text, text, uuid, text, integer, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_membership_page_summary — four KPIs. RETURNS shape changes.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists get_membership_page_summary(uuid);

create function get_membership_page_summary(p_facility_id uuid)
returns table (
  total_members bigint,
  total_members_prev bigint,
  active_members bigint,
  inactive_members bigint,
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
      (mm.status = 'cancelled' or mm.end_date < current_date) as is_inactive,
      (
        coalesce(mm.total_amount_inr, mm.membership_fee_inr, mp.price_inr, 0) = 0
        or exists (select 1 from payments pp where pp.membership_id = mm.id and pp.status = 'paid')
      ) as is_paid
    from memberships mm
    left join membership_plans mp on mp.id = mm.plan_id
    where mm.facility_id = p_facility_id
  )
  select
    (select count(distinct member_id) from m),
    (select count(distinct member_id) from m, months where m.created_at < months.cur_start),
    (select count(*) from m where not is_inactive and is_paid),
    (select count(*) from m where is_inactive),
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

-- ─────────────────────────────────────────────────────────────────────────
-- delete_member — hard delete, guarded. Only a member with zero bookings
-- and no settled ('paid'/'refunded') payment can be removed; the cascade
-- then clears any empty memberships / 'created' payment stubs / batch
-- enrolments. Owner/manager only.
-- ─────────────────────────────────────────────────────────────────────────
create function delete_member(p_member_id uuid) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_facility uuid;
begin
  select facility_id into v_facility from members where id = p_member_id;
  if v_facility is null then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(v_facility, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized to delete members.' using errcode = '42501';
  end if;
  if exists (select 1 from bookings where member_id = p_member_id)
     or exists (select 1 from payments where member_id = p_member_id and status in ('paid', 'refunded')) then
    raise exception 'This member has booking or payment history and cannot be deleted.' using errcode = '23514';
  end if;

  delete from members where id = p_member_id;
end;
$$;

grant execute on function delete_member(uuid) to authenticated;