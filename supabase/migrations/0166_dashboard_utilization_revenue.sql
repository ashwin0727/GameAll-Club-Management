-- Dashboard: court utilization and the revenue chart computed in the database.
--
-- Until now the dashboard downloaded every booking of the period (and two months of payments) and added them up on the phone or
-- in the browser; a busy club passes the API's 1000-row page limit and silently under-counts. These two functions return only the
-- numbers the screens draw. Both run as the caller (SECURITY INVOKER), so row-level security still limits them to the caller's club.

-- ── Booked minutes per court (utilization) ───────────────────────────────────────────────────────────────────
-- Booked time = every non-cancelled booking starting inside the window, plus every membership session that has at least one
-- confirmed slot booking (get_membership_utilization_sessions), counted once for its full length. The app divides by the
-- club's opening hours.
create or replace function dashboard_booked_minutes(
  p_facility_id uuid,
  p_cur_from timestamptz,
  p_cur_to timestamptz,
  p_prev_from timestamptz,        -- null when there is no comparison period
  p_prev_to timestamptz,
  p_cur_from_date date,           -- the same windows as local calendar dates, for membership sessions
  p_cur_to_date date,
  p_prev_from_date date,
  p_prev_to_date date,
  p_court_ids uuid[]
) returns table (court_id uuid, cur_minutes double precision, prev_minutes double precision)
language sql
stable
set search_path = public
as $$
  with b as (
    select bk.court_id,
           case when bk.start_time >= p_cur_from and bk.start_time < p_cur_to then 'c'
                when p_prev_from is not null and bk.start_time >= p_prev_from and bk.start_time < p_prev_to then 'p'
           end as w,
           greatest(0, extract(epoch from (bk.end_time - bk.start_time)) / 60.0) as m
      from bookings bk
     where bk.facility_id = p_facility_id
       and bk.status <> 'cancelled'
       and bk.court_id = any (coalesce(p_court_ids, '{}'::uuid[]))
       and bk.start_time >= coalesce(p_prev_from, p_cur_from)
       and bk.start_time < p_cur_to
  ),
  s as (
    select x.court_id, 'c' as w, greatest(0, extract(epoch from (x.end_time - x.start_time)) / 60.0) as m
      from get_membership_utilization_sessions(p_facility_id, p_cur_from_date, p_cur_to_date) x
     where x.court_id = any (coalesce(p_court_ids, '{}'::uuid[]))
    union all
    select x.court_id, 'p', greatest(0, extract(epoch from (x.end_time - x.start_time)) / 60.0)
      from get_membership_utilization_sessions(p_facility_id, p_prev_from_date, p_prev_to_date) x
     where p_prev_from_date is not null
       and x.court_id = any (coalesce(p_court_ids, '{}'::uuid[]))
  ),
  u as (
    select court_id, w, m from b where w is not null
    union all
    select court_id, w, m from s
  )
  select u.court_id,
         coalesce(sum(u.m) filter (where u.w = 'c'), 0)::double precision,
         coalesce(sum(u.m) filter (where u.w = 'p'), 0)::double precision
    from u
   group by u.court_id;
$$;
grant execute on function dashboard_booked_minutes(uuid, timestamptz, timestamptz, timestamptz, timestamptz, date, date, date, date, uuid[]) to authenticated;

-- ── Revenue chart ───────────────────────────────────────────────────────────────────────────────────────────
-- Money actually received, dated the way Finance dates it (paid_at, else created_at). Returns the month's total, the previous
-- month's total, the total per local calendar day, and the split into bookings / memberships / coaching / other (a payment is a
-- membership payment if it has a membership, else a booking payment, else a coaching one).
-- With sports ticked, a payment counts when what it paid for belongs to one of them: a membership in one of their batches, a
-- booking on one of their courts, or a coaching enrollment in one of their programs.
create or replace function dashboard_revenue_overview(
  p_facility_id uuid,
  p_month_start timestamptz,
  p_month_end timestamptz,
  p_prev_start timestamptz,
  p_tz text,                      -- the viewer's time zone, to bucket by their calendar day
  p_facility_sport_ids uuid[],    -- null = all sports
  p_utc_offset_minutes integer default null   -- alternative to p_tz for callers that only know their UTC offset (the phone app)
) returns jsonb
language sql
stable
set search_path = public
as $$
  with
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
    select p.amount_inr, p.membership_id, p.booking_id, p.coaching_enrollment_id,
           coalesce(p.paid_at, p.created_at) as at
      from payments p
     where p.facility_id = p_facility_id
       and p.status::text = 'paid'
       and coalesce(p.paid_at, p.created_at) >= p_prev_start
       and coalesce(p.paid_at, p.created_at) < p_month_end
       and (
         p_facility_sport_ids is null
         or case
              when p.membership_id is not null then p.membership_id in (select id from scope_memberships)
              when p.booking_id is not null then exists (
                select 1 from bookings b join courts c on c.id = b.court_id
                 where b.id = p.booking_id and c.facility_sport_id = any (p_facility_sport_ids))
              when p.coaching_enrollment_id is not null then exists (
                select 1 from coaching_enrollments e join coaching_programs pr on pr.id = e.program_id
                 where e.id = p.coaching_enrollment_id and pr.facility_sport_id = any (p_facility_sport_ids))
              else false
            end
       )
  ),
  cur as (select * from pay where at >= p_month_start),
  by_day as (
    select to_char(
             (case when p_utc_offset_minutes is not null
                   then (at at time zone 'UTC') + make_interval(mins => p_utc_offset_minutes)
                   else at at time zone coalesce(nullif(p_tz, ''), 'UTC') end)::date,
             'YYYY-MM-DD') as d,
           sum(amount_inr) as amt
      from cur group by 1
  )
  select jsonb_build_object(
    'totalInr',         coalesce((select sum(amount_inr) from cur), 0),
    'previousTotalInr', coalesce((select sum(amount_inr) from pay where at < p_month_start), 0),
    'byDay',            coalesce((select jsonb_object_agg(d, amt) from by_day), '{}'::jsonb),
    'breakdown', jsonb_build_object(
      'memberships', jsonb_build_object(
        'count', (select count(*) from cur where membership_id is not null),
        'inr',   coalesce((select sum(amount_inr) from cur where membership_id is not null), 0)),
      'bookings', jsonb_build_object(
        'count', (select count(*) from cur where membership_id is null and booking_id is not null),
        'inr',   coalesce((select sum(amount_inr) from cur where membership_id is null and booking_id is not null), 0)),
      'coaching', jsonb_build_object(
        'count', (select count(*) from cur where membership_id is null and booking_id is null and coaching_enrollment_id is not null),
        'inr',   coalesce((select sum(amount_inr) from cur where membership_id is null and booking_id is null and coaching_enrollment_id is not null), 0)),
      'other', jsonb_build_object(
        'count', (select count(*) from cur where membership_id is null and booking_id is null and coaching_enrollment_id is null),
        'inr',   coalesce((select sum(amount_inr) from cur where membership_id is null and booking_id is null and coaching_enrollment_id is null), 0))
    )
  );
$$;
grant execute on function dashboard_revenue_overview(uuid, timestamptz, timestamptz, timestamptz, text, uuid[], integer) to authenticated;

-- ── Bookings made (the phone app's Bookings figure) ──
-- Every non-cancelled booking, member or guest, starting inside each window, on the given courts.
create or replace function dashboard_booking_counts(
  p_facility_id uuid,
  p_cur_from timestamptz,
  p_cur_to timestamptz,
  p_prev_from timestamptz,
  p_prev_to timestamptz,
  p_court_ids uuid[]
) returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'current',  count(*) filter (where b.start_time >= p_cur_from and b.start_time < p_cur_to),
    'previous', count(*) filter (where p_prev_from is not null and b.start_time >= p_prev_from and b.start_time < p_prev_to)
  )
  from bookings b
  where b.facility_id = p_facility_id
    and b.status <> 'cancelled'
    and b.court_id = any (coalesce(p_court_ids, '{}'::uuid[]))
    and b.start_time >= coalesce(p_prev_from, p_cur_from)
    and b.start_time < p_cur_to;
$$;
grant execute on function dashboard_booking_counts(uuid, timestamptz, timestamptz, timestamptz, timestamptz, uuid[]) to authenticated;

-- The dashboard's two-month payments read, dated the way the chart dates them.
create index if not exists payments_facility_paid_at_idx on payments (facility_id, paid_at) where paid_at is not null;
