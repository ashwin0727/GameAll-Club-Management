-- Dashboard totals computed in the database.
--
-- The web dashboard used to download every payment of the period, every membership the club has ever sold and (when a sport was
-- ticked) every membership-batch row of every club, then add them up in the browser. A busy club passes the API's 1000-row page
-- limit, which would silently under-count. This function returns just the totals, with the exact rules the browser used
-- (src/features/dashboard/summary.ts):
--   * payments are dated by created_at; collected = 'paid', pending = 'created', refunds = 'refunded'
--   * with sports ticked, a payment counts only if it is for a booking (in the period, on those sports' courts) or for a membership
--     enrolled in a batch of those sports
--   * guest bookings = GUEST + PAID + not cancelled, on the given courts, starting inside the window
--   * memberships: active / expiring (end date within p_soon) / expired / created since p_month_start
-- Runs as the caller (SECURITY INVOKER), so row-level security still limits it to the caller's own club.
create or replace function dashboard_totals(
  p_facility_id uuid,
  p_cur_from timestamptz,
  p_cur_to timestamptz,
  p_prev_from timestamptz,          -- null when there is no comparison period
  p_prev_to timestamptz,
  p_court_ids uuid[],               -- the courts in view
  p_facility_sport_ids uuid[],      -- null = all sports
  p_soon timestamptz,               -- an active membership ending on/before this is "expiring soon"
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
  mem as (
    select
      count(*) filter (where m.status::text = 'active') as active,
      count(*) filter (where m.status::text = 'active' and (m.end_date::timestamp at time zone 'UTC') <= p_soon) as expiring,
      count(*) filter (where m.status::text = 'expired') as expired,
      count(*) filter (where m.created_at >= p_month_start) as new_this_month,
      count(*) filter (where m.status::text = 'active' and (p_facility_sport_ids is null or m.id in (select id from scope_memberships))) as active_in_scope
    from memberships m
    where m.facility_id = p_facility_id
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
