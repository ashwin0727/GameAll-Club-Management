-- ═══════════════════════════════════════════════════════════════════════════
-- Membership "Active" rules: paid, with a 15-day grace after the due date.
--
-- A membership's end_date is its next payment (due) date: it moves forward each time a payment is recorded or collected, whatever
-- the plan length (monthly, 3-monthly, 6-monthly ...). From that, one rule counts a member as Active:
--
--   • cancelled                                     → not active
--   • free membership (nothing to pay)              → active while its end date has not passed
--   • never paid                                    → not active (the player has not completed payment)
--   • paid, and today <= due date                   → Active
--   • paid, due date passed, today <= due date + 15 → still counted Active, shown as "Payment Incomplete" (the grace period)
--   • paid, today > due date + 15                   → not active; the daily job below cancels it and tells the player
--
-- Expiring Soon (Home) = active memberships whose due date is TOMORROW.
--
-- Changes:
--   • membership_counts_as_active()    — the rule above, in one place
--   • membership_display_status()       — past the grace period reads "inactive" (it already reads "payment_incomplete" for the
--                                        grace period itself)
--   • dashboard_totals()                — Home: Active Members + Expiring Soon use the rule
--   • _get_membership_page_summary_impl — Membership Dashboard: Active Members includes the grace-period members
--   • lapse_overdue_memberships()       — cancels memberships past due date + 15 and notifies the player; scheduled hourly
-- Dates are India dates (Asia/Kolkata), not UTC, so "tomorrow" flips at local midnight.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function membership_grace_days() returns integer language sql immutable as $$ select 15; $$;

create or replace function ist_today() returns date language sql stable as $$
  select (now() at time zone 'Asia/Kolkata')::date;
$$;
grant execute on function membership_grace_days() to authenticated;
grant execute on function ist_today() to authenticated;

create or replace function membership_counts_as_active(p_id uuid, p_raw_status text, p_end date, p_fee integer)
returns boolean
language sql
stable
as $$
  select case
    when p_raw_status in ('cancelled', 'pending') then false
    when coalesce(p_fee, 0) <= 0 then p_end >= ist_today()
    when not exists (
      select 1 from payments where membership_id = p_id and status = 'paid' and paid_at is not null
    ) then false
    else ist_today() <= p_end + membership_grace_days()
  end;
$$;
grant execute on function membership_counts_as_active(uuid, text, date, integer) to authenticated;

-- Display status: same as before, plus "inactive" once the grace period has run out.
create or replace function membership_display_status(
  p_id uuid,
  p_raw_status text,
  p_start date,
  p_end date,
  p_duration integer,
  p_fee integer
) returns text
language sql
stable
as $$
  select case
    when p_raw_status = 'cancelled' then 'inactive'
    when coalesce(p_fee, 0) = 0 then 'active'
    when p_end + membership_grace_days() < ist_today() then 'inactive'
    when p_end < ist_today() then 'payment_incomplete'
    when not exists (
      select 1 from payments
      where membership_id = p_id and status = 'paid' and paid_at is not null
    ) then 'payment_incomplete'
    else 'active'
  end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Home totals: only the memberships block changes.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function dashboard_totals(
  p_facility_id uuid,
  p_cur_from timestamptz,
  p_cur_to timestamptz,
  p_prev_from timestamptz,
  p_prev_to timestamptz,
  p_court_ids uuid[],
  p_facility_sport_ids uuid[],
  p_soon timestamptz,               -- no longer used: Expiring Soon is "due tomorrow"; kept so existing callers still work
  p_month_start timestamptz
) returns jsonb
language sql
stable
set search_path = public
as $$
  with
  win as (select coalesce(p_prev_from, p_cur_from) as earliest),
  scope_bookings as (
    select b.id
      from bookings b, win
     where p_facility_sport_ids is not null
       and b.facility_id = p_facility_id
       and b.court_id = any (coalesce(p_court_ids, '{}'::uuid[]))
       and b.start_time >= win.earliest and b.start_time < p_cur_to
  ),
  scope_memberships as (
    select distinct bm.membership_id as id
      from membership_batch_members bm
      join membership_batches mb on mb.id = bm.batch_id
     where p_facility_sport_ids is not null
       and mb.facility_id = p_facility_id
       and mb.facility_sport_id = any (p_facility_sport_ids)
       and bm.membership_id is not null
  ),
  pay as (
    select p.status::text as status, p.amount_inr, p.created_at
      from payments p, win
     where p.facility_id = p_facility_id
       and p.created_at >= win.earliest and p.created_at < p_cur_to
       and (
         p_facility_sport_ids is null
         or p.booking_id in (select id from scope_bookings)
         or p.membership_id in (select id from scope_memberships)
       )
  ),
  pay_totals as (
    select
      coalesce(sum(amount_inr) filter (where status = 'paid'     and created_at >= p_cur_from and created_at < p_cur_to), 0) as collected,
      coalesce(sum(amount_inr) filter (where status = 'created'  and created_at >= p_cur_from and created_at < p_cur_to), 0) as pending,
      coalesce(sum(amount_inr) filter (where status = 'refunded' and created_at >= p_cur_from and created_at < p_cur_to), 0) as refunds,
      coalesce(sum(amount_inr) filter (where status = 'paid' and p_prev_from is not null and created_at >= p_prev_from and created_at < p_prev_to), 0) as prev_collected
    from pay
  ),
  guest as (
    select
      count(*) filter (where b.start_time >= p_cur_from and b.start_time < p_cur_to) as cur,
      count(*) filter (where p_prev_from is not null and b.start_time >= p_prev_from and b.start_time < p_prev_to) as prev
    from bookings b, win
    where b.facility_id = p_facility_id
      and b.court_id = any (coalesce(p_court_ids, '{}'::uuid[]))
      and b.customer_type = 'GUEST' and b.payment_status = 'PAID' and b.status <> 'cancelled'
      and b.start_time >= win.earliest and b.start_time < p_cur_to
  ),
  mem_rows as (
    select
      m.id, m.status::text as raw_status, m.end_date, m.created_at,
      membership_counts_as_active(
        m.id, m.status::text, m.end_date,
        coalesce(m.total_amount_inr, m.membership_fee_inr, mp.price_inr, 0)::integer
      ) as is_active
    from memberships m
    left join membership_plans mp on mp.id = m.plan_id
    where m.facility_id = p_facility_id
  ),
  mem as (
    select
      count(*) filter (where is_active) as active,
      count(*) filter (where is_active and end_date = ist_today() + 1) as expiring,
      count(*) filter (where raw_status = 'expired') as expired,
      count(*) filter (where created_at >= p_month_start) as new_this_month,
      count(*) filter (where is_active and (p_facility_sport_ids is null or id in (select id from scope_memberships))) as active_in_scope
    from mem_rows
  )
  select jsonb_build_object(
    'collectedInr', pt.collected,
    'pendingInr', pt.pending,
    'refundsInr', pt.refunds,
    'previousCollectedInr', pt.prev_collected,
    'guestBookings', g.cur,
    'previousGuestBookings', g.prev,
    'memberships', jsonb_build_object('active', mem.active, 'expiringSoon', mem.expiring, 'expired', mem.expired, 'newThisMonth', mem.new_this_month),
    'activeMembershipsInScope', mem.active_in_scope
  )
  from pay_totals pt, guest g, mem;
$$;
grant execute on function dashboard_totals(uuid, timestamptz, timestamptz, timestamptz, timestamptz, uuid[], uuid[], timestamptz, timestamptz) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- Membership Dashboard summary: Active Members now includes the grace-period members (they show as "Payment Incomplete" in the
-- list but still count). payment_incomplete_members stays "status = payment_incomplete", as before.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function _get_membership_page_summary_impl(p_facility_id uuid)
returns table (
  total_members bigint,
  total_members_prev bigint,
  active_members bigint,
  payment_incomplete_members bigint,
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
      mm.member_id,
      mm.created_at,
      membership_display_status(
        mm.id, mm.status::text, mm.start_date, mm.end_date, mm.duration_days,
        coalesce(mm.total_amount_inr, mm.membership_fee_inr, mp.price_inr, 0)::integer
      ) as ds,
      membership_counts_as_active(
        mm.id, mm.status::text, mm.end_date,
        coalesce(mm.total_amount_inr, mm.membership_fee_inr, mp.price_inr, 0)::integer
      ) as is_active
    from memberships mm
    left join membership_plans mp on mp.id = mm.plan_id
    where mm.facility_id = p_facility_id
  )
  select
    (select count(distinct member_id) from m),
    (select count(distinct member_id) from m, months where m.created_at < months.cur_start),
    (select count(*) from m where is_active),
    (select count(*) from m where ds = 'payment_incomplete'),
    coalesce((
      select sum(amount_inr) from payments, months
      where facility_id = p_facility_id and membership_id is not null
        and status = 'paid' and paid_at is not null
        and paid_at >= months.cur_start
    ), 0),
    coalesce((
      select sum(amount_inr) from payments, months
      where facility_id = p_facility_id and membership_id is not null
        and status = 'paid' and paid_at is not null
        and paid_at >= months.prev_start and paid_at < months.cur_start
    ), 0);
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Cancel the memberships that ran out of grace, and tell the player. Safe to run any number of times: a cancelled membership is
-- not picked again, and the message carries a dedupe key.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function lapse_overdue_memberships()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select m.id, m.facility_id, m.end_date, mb.phone, f.name as venue
      from memberships m
      join members mb on mb.id = m.member_id
      join facilities f on f.id = m.facility_id
      left join membership_plans mp on mp.id = m.plan_id
     where m.status::text in ('active', 'pending')
       and coalesce(m.total_amount_inr, m.membership_fee_inr, mp.price_inr, 0) > 0
       and m.end_date + membership_grace_days() < ist_today()
  loop
    update memberships set status = 'cancelled' where id = r.id;
    perform _notify_players(
      r.phone, r.facility_id, 'player_membership_cancelled', 'Membership cancelled',
      'Your Membership has been cancelled at ' || coalesce(r.venue, 'your venue') || '. If any queries, please reach out to Venue',
      jsonb_build_object('route', '/my-membership', 'membershipId', r.id),
      'player_membership_cancelled:' || r.id || ':' || r.end_date::text);
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke all on function lapse_overdue_memberships() from public, anon, authenticated;
grant execute on function lapse_overdue_memberships() to service_role;

do $cron$
begin
  create extension if not exists pg_cron;
  if exists (select 1 from cron.job where jobname = 'lapse-overdue-memberships') then
    perform cron.unschedule('lapse-overdue-memberships');
  end if;
  -- every hour, at 5 past: a membership is cancelled within the hour after its grace period ends
  perform cron.schedule('lapse-overdue-memberships', '5 * * * *', 'select public.lapse_overdue_memberships()');
exception when others then
  raise notice 'Could not schedule the hourly job (%). Turn on pg_cron under Database > Extensions and run this block again, or call select public.lapse_overdue_memberships() once a day.', sqlerrm;
end
$cron$;
