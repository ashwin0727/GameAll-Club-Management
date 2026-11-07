-- ═══════════════════════════════════════════════════════════════════════════
-- Player Home: memberships and coaching show "Active" / "Enrolled" only once they are PAID; an unpaid one stays visible but is tagged
-- "Payment Incomplete", and everything still unpaid also comes back as a payment prompt.
--
--   get_player_dashboard()                 same function as 0169, with:
--       memberships / coaching   every active one, each with paymentIncomplete (true until it is paid in full, or the AutoPay mandate
--                                                        is approved, or nothing is owed)
--       pendingPayments                                  [{ kind, id, title, venueName, state, dueOn, overdue, startTime, mode, balance, balanceInr }]
--                                                        kind  membership | coaching | booking
--                                                        state PENDING (not paid yet) | FAILED (a payment failed, or AutoPay is
--                                                              halted / retrying, or the payment link ran out)
--   player_booking_payment_context(id)     signed-in player: what create-player-booking-payment-link needs for one of THEIR bookings
--
-- Nothing is stored: like Pending Payments (0052) the amount owed is the gap between what something costs and what was paid.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_player_dashboard()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (select auth.uid() as uid),
  pl as (select p.id, p.full_name, p.phone, p.email from players p, me where p.id = me.uid),
  my_members as (
    select m.id from members m, pl where normalize_phone(m.phone) = pl.phone
    union
    select m.id from members m, me where m.user_id = me.uid
  ),
  my_guests as (
    select g.id from guest_players g, pl where normalize_phone(g.phone) = pl.phone
  ),
  my_people as (
    select id from my_members
    union
    select uid from me where uid is not null
  ),
  -- bookings: made for me as a member, or as a guest (by guest record or by the phone typed on the booking)
  my_bookings as (
    select b.id, b.start_time, b.end_time, b.status::text as status, b.customer_type,
           b.amount_minor, b.payment_status::text as payment_status,
           f.name as venue_name, f.logo_url as venue_logo, c.name as court_name, s.name as sport_name
      from bookings b
      join facilities f on f.id = b.facility_id
      left join courts c on c.id = b.court_id
      left join sports s on s.id = c.sport_id
     where b.member_id in (select id from my_people)
        or b.guest_player_id in (select id from my_guests)
        or (b.customer_type = 'GUEST' and normalize_phone(b.guest_phone) = (select phone from pl))
  ),
  upcoming as (
    select * from my_bookings where status = 'confirmed' and end_time > now() order by start_time limit 5
  ),

  -- ── memberships and what has been paid towards each ──
  ms_calc as (
    select ms.id, ms.start_date, ms.end_date,
           coalesce(nullif(trim(ms.name), ''), mp.name, 'Membership') as plan_name, f.name as venue_name,
           -- what is owed: the stored total, or (a membership started in the Player app has only a plan price) the unpaid payment row
           greatest(coalesce(ms.total_amount_inr, 0) * 100,
                    coalesce((select max(p.amount_inr) * 100 from payments p where p.membership_id = ms.id and p.status in ('created', 'failed')), 0))::bigint as total_minor,
           coalesce((select sum(p.amount_inr) * 100 from payments p where p.membership_id = ms.id and p.status = 'paid'), 0)::bigint as paid_minor,
           (select s.status::text from membership_subscriptions s where s.membership_id = ms.id) as sub_status,
           exists (select 1 from payments p where p.membership_id = ms.id and p.status = 'failed') as has_failed
      from memberships ms
      left join membership_plans mp on mp.id = ms.plan_id
      join facilities f on f.id = ms.facility_id
     where ms.member_id in (select id from my_people)
       and ms.status::text = 'active' and ms.end_date >= current_date
  ),
  ms_state as (
    select c.*,
           case
             when c.sub_status in ('halted', 'pending') then 'FAILED'      -- AutoPay: a charge failed
             when c.total_minor <= 0 or c.paid_minor >= c.total_minor or c.sub_status in ('authenticated', 'active', 'completed') then 'PAID'
             when c.has_failed then 'FAILED'
             else 'PENDING'
           end as pay_state
      from ms_calc c
  ),
  -- Active = something has actually been paid, or nothing is owed.
  ms_settled as (select s.id from ms_state s where s.pay_state = 'PAID' or s.paid_minor > 0),
  ms_unsettled as (select s.id from ms_state s where not (s.pay_state = 'PAID' or s.paid_minor > 0)),

  -- ── coaching enrolments, the same way ──
  co_calc as (
    select e.id, e.start_date, e.fee_type, cp.name as program_name, f.name as venue_name,
           e.price_minor::bigint as total_minor,
           coalesce((select sum(p.amount_inr) * 100 from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid'), 0)::bigint as paid_minor,
           (select b.status from coaching_enrollment_billing b where b.enrollment_id = e.id) as bill_status,
           exists (select 1 from payments p where p.coaching_enrollment_id = e.id and p.status = 'failed') as has_failed
      from coaching_enrollments e
      join coaching_programs cp on cp.id = e.program_id
      join facilities f on f.id = e.facility_id
     where e.member_id in (select id from my_people)
       and e.status = 'ACTIVE' and (e.end_date is null or e.end_date >= current_date)
  ),
  co_state as (
    select c.*,
           case
             when c.bill_status in ('HALTED', 'PENDING', 'EXPIRED', 'CANCELLED') then 'FAILED'   -- charge failed / link ran out
             when c.total_minor <= 0 or c.paid_minor >= c.total_minor or c.bill_status in ('AUTHENTICATED', 'ACTIVE', 'PAID', 'COMPLETED') then 'PAID'
             when c.has_failed then 'FAILED'
             else 'PENDING'
           end as pay_state
      from co_calc c
  ),
  co_settled as (select s.id from co_state s where s.pay_state = 'PAID' or s.paid_minor > 0),

  -- ── bookings with money still owed ──
  bk_state as (
    select mb.id, mb.customer_type, mb.venue_name, mb.start_time, mb.status,
           coalesce(mb.amount_minor, 0)::bigint as total_minor,
           coalesce((select sum(p.amount_inr) * 100 from payments p where p.booking_id = mb.id and p.status = 'paid'), 0)::bigint as paid_minor,
           exists (select 1 from payments p where p.booking_id = mb.id and p.status = 'failed') as has_failed
      from my_bookings mb
     where mb.status in ('pending', 'confirmed') and mb.end_time > now()
       and coalesce(mb.payment_status, '') <> 'PAID'
  ),
  -- A confirmed booking whose online advance (50% of a booking over an hour) is paid is NOT "payment pending": its court is secured and
  -- the rest is paid at the venue. Only a booking that has not been paid at all, or is still a hold, asks for payment.
  bk_due as (select * from bk_state s where s.total_minor > 0 and s.paid_minor < s.total_minor and not (s.status = 'confirmed' and s.paid_minor > 0)),

  -- ── a booking whose advance is paid but whose balance is still owed, as its time runs out ──
  -- A guest booking over an hour is secured with a 50% advance and the rest is paid at the venue. From 5 minutes before the booking
  -- ends (and for a week after, until it is paid) Home asks for the balance, so it can be paid online instead.
  bk_balance_due as (
    select mb.id, mb.customer_type, mb.venue_name, mb.start_time, mb.end_time,
           coalesce(mb.amount_minor, 0)::bigint as total_minor,
           coalesce((select sum(p.amount_inr) * 100 from payments p where p.booking_id = mb.id and p.status = 'paid'), 0)::bigint as paid_minor
      from my_bookings mb
     where mb.status = 'confirmed'
       and coalesce(mb.payment_status, '') <> 'PAID'
       and now() >= mb.end_time - interval '5 minutes'
       and mb.end_time > now() - interval '7 days'
  ),

  active_memberships as (
    select ms.id, coalesce(nullif(trim(ms.name), ''), mp.name, 'Membership') as plan_name, f.name as venue_name, ms.start_date, ms.end_date,
           bt.batch_name, bt.days_of_week, bt.start_time, bt.end_time, bt.court_name,
           (ms.id in (select id from ms_state where pay_state <> 'PAID')) as payment_incomplete
      from memberships ms
      left join membership_plans mp on mp.id = ms.plan_id
      join facilities f on f.id = ms.facility_id
      left join lateral (
        select mb.name as batch_name, mb.days_of_week, mb.start_time, mb.end_time, c.name as court_name
          from membership_batch_members bm
          join membership_batches mb on mb.id = bm.batch_id and mb.is_active
          left join courts c on c.id = mb.court_id
         where bm.member_id = ms.member_id
           and (bm.membership_id = ms.id or bm.membership_id is null)
         order by (bm.membership_id = ms.id) desc, bm.created_at desc
         limit 1
      ) bt on true
     where ms.member_id in (select id from my_people)
       and ms.status::text = 'active' and ms.end_date >= current_date
  ),
  active_coaching as (
    select e.id, cp.name as program_name, f.name as venue_name, e.end_date,
           (e.id in (select id from co_state where pay_state <> 'PAID')) as payment_incomplete,
           (select pr.full_name from coaches co join profiles pr on pr.id = co.user_id where co.id = e.coach_id) as coach_name,
           (select min(cs.start_at)
              from coaching_session_students st
              join coaching_sessions cs on cs.id = st.session_id
             where st.enrollment_id = e.id and st.status = 'ENROLLED'
               and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS') and cs.end_at > now()) as next_session,
           (select cs.end_at
              from coaching_session_students st
              join coaching_sessions cs on cs.id = st.session_id
             where st.enrollment_id = e.id and st.status = 'ENROLLED'
               and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS') and cs.end_at > now()
             order by cs.start_at limit 1) as next_session_end
      from coaching_enrollments e
      join coaching_programs cp on cp.id = e.program_id
      join facilities f on f.id = e.facility_id
     where e.member_id in (select id from my_people)
       and e.status = 'ACTIVE' and (e.end_date is null or e.end_date >= current_date)
  ),
  items as (
    select 'guest' as kind, case when mb.customer_type = 'GUEST' then 'Guest Booking' else 'Court Booking' end as title,
           mb.venue_name, mb.court_name, mb.start_time as start_at, mb.end_time as end_at, 'confirmed' as status
      from my_bookings mb
     where mb.status = 'confirmed' and mb.end_time > now() and mb.start_time < now() + interval '8 days'
    union all
    select 'membership', coalesce(mb.name, 'Membership'), f.name, c.name,
           (s.session_date + s.start_time) at time zone coalesce(f.timezone, 'Asia/Kolkata'),
           (s.session_date + s.end_time) at time zone coalesce(f.timezone, 'Asia/Kolkata'), 'confirmed'
      from membership_sessions s
      join membership_batches mb on mb.id = s.batch_id
      join membership_batch_members bm on bm.batch_id = s.batch_id and bm.member_id in (select id from my_people)
      join facilities f on f.id = s.facility_id
      left join courts c on c.id = s.court_id
     where s.session_date >= current_date and s.session_date < current_date + 8
       and ((s.session_date + s.end_time) at time zone coalesce(f.timezone, 'Asia/Kolkata')) > now()
       -- a membership that has not been paid for is not on the schedule yet
       and (bm.membership_id is null or bm.membership_id not in (select id from ms_unsettled))
    union all
    select 'coaching', cp.name, f.name, c.name, cs.start_at, cs.end_at, lower(cs.status)
      from coaching_session_students st
      join coaching_enrollments e on e.id = st.enrollment_id and e.member_id in (select id from my_people)
      join coaching_sessions cs on cs.id = st.session_id
      join coaching_programs cp on cp.id = cs.program_id
      join facilities f on f.id = cs.facility_id
      left join courts c on c.id = cs.court_id
     where st.status = 'ENROLLED' and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS')
       and cs.end_at > now() and cs.start_at < now() + interval '8 days'
       and e.id in (select id from co_settled)
  ),
  schedule as (select * from items order by start_at limit 12),
  prompts as (
    select 'membership' as kind, s.id, s.plan_name as title, s.venue_name, s.pay_state as state, s.start_date as due_on,
           (s.start_date < current_date) as overdue, null::timestamptz as start_at, 'AUTOPAY' as mode, null::bigint as balance_minor
      from ms_state s where s.pay_state in ('PENDING', 'FAILED')
    union all
    select 'coaching', s.id, s.program_name, s.venue_name, s.pay_state, s.start_date,
           (s.start_date < current_date), null::timestamptz, case when s.fee_type = 'MONTHLY' then 'AUTOPAY' else 'LINK' end, null::bigint
      from co_state s where s.pay_state in ('PENDING', 'FAILED')
    union all
    select 'booking', d.id, case when d.customer_type = 'GUEST' then 'Guest Booking' else 'Court Booking' end, d.venue_name,
           case when d.has_failed then 'FAILED' else 'PENDING' end, (d.start_time at time zone 'Asia/Kolkata')::date,
           false, d.start_time, 'LINK', null::bigint
      from bk_due d
    union all
    select 'booking', d.id, case when d.customer_type = 'GUEST' then 'Guest Booking' else 'Court Booking' end, d.venue_name,
           'PENDING', (d.end_time at time zone 'Asia/Kolkata')::date, (d.end_time < now()), d.start_time, 'LINK', (d.total_minor - d.paid_minor)
      from bk_balance_due d where d.total_minor > 0 and d.paid_minor > 0 and d.paid_minor < d.total_minor
  )
  select jsonb_build_object(
    'fullName', (select full_name from pl),
    'phone', (select phone from pl),
    'email', (select email from pl),
    'unreadNotifications', (select count(*) from notifications n, me where n.user_id = me.uid and n.read_at is null),
    'hasActiveMembership', exists (select 1 from active_memberships),
    'hasActiveCoaching', exists (select 1 from active_coaching),
    'hasBookingHistory', exists (select 1 from my_bookings),
    'upcomingBookings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'startTime', u.start_time, 'endTime', u.end_time, 'status', u.status,
        'venueName', u.venue_name, 'venueLogo', u.venue_logo, 'courtName', u.court_name, 'sportName', u.sport_name
      ) order by u.start_time) from upcoming u), '[]'::jsonb),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'planName', a.plan_name, 'venueName', a.venue_name, 'endDate', a.end_date,
        'batchName', a.batch_name, 'daysOfWeek', to_jsonb(a.days_of_week),
        'startTime', to_char(a.start_time, 'HH24:MI'), 'endTime', to_char(a.end_time, 'HH24:MI'), 'courtName', a.court_name,
        'paymentIncomplete', a.payment_incomplete
      ) order by a.end_date) from active_memberships a), '[]'::jsonb),
    'coaching', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', k.id, 'programName', k.program_name, 'venueName', k.venue_name, 'coachName', k.coach_name,
        'endDate', k.end_date, 'nextSession', k.next_session, 'nextSessionEnd', k.next_session_end,
        'paymentIncomplete', k.payment_incomplete
      ) order by k.next_session nulls last) from active_coaching k), '[]'::jsonb),
    'guestBookings', jsonb_build_object(
      'count', (select count(*) from my_bookings g where g.customer_type = 'GUEST' and g.status = 'confirmed' and g.end_time > now()),
      'next', (select jsonb_build_object('startTime', g.start_time, 'endTime', g.end_time, 'venueName', g.venue_name, 'courtName', g.court_name)
                 from my_bookings g
                where g.customer_type = 'GUEST' and g.status = 'confirmed' and g.end_time > now()
                order by g.start_time limit 1)),
    'pendingPayments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', q.kind, 'id', q.id, 'title', q.title, 'venueName', q.venue_name, 'state', q.state,
        'dueOn', q.due_on, 'overdue', q.overdue, 'startTime', q.start_at, 'mode', q.mode,
        'balance', q.balance_minor is not null, 'balanceInr', (q.balance_minor / 100)
      ) order by (q.state = 'FAILED') desc, q.due_on)
        from prompts q), '[]'::jsonb),
    'schedule', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', i.kind, 'title', i.title, 'venueName', i.venue_name, 'courtName', i.court_name,
        'startTime', i.start_at, 'endTime', i.end_at, 'status', i.status
      ) order by i.start_at) from schedule i), '[]'::jsonb),
    'courtsToday', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', i.kind, 'title', i.title, 'venueName', i.venue_name, 'courtName', i.court_name,
        'startTime', i.start_at, 'endTime', i.end_at, 'status', i.status
      ) order by i.start_at)
        from schedule i
       where i.court_name is not null and (i.start_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date), '[]'::jsonb)
  );
$$;
revoke all on function get_player_dashboard() from public, anon;
grant execute on function get_player_dashboard() to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- What create-player-booking-payment-link needs, for one booking, and only when it is the signed-in player's own (made for them
-- as a member or a guest, matched by their phone number). Same ownership rule as the dashboard.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function player_booking_payment_context(p_booking_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me players;
  b bookings;
  v_paid bigint;
begin
  select * into me from players where id = auth.uid();
  if me.id is null then
    raise exception 'Sign in first.' using errcode = '42501';
  end if;

  select b2.* into b
    from bookings b2
   where b2.id = p_booking_id
     and (
       b2.member_id in (select m.id from members m where normalize_phone(m.phone) = me.phone or m.user_id = me.id)
       or b2.guest_player_id in (select g.id from guest_players g where normalize_phone(g.phone) = me.phone)
       or (b2.customer_type = 'GUEST' and normalize_phone(b2.guest_phone) = me.phone)
     );
  if b.id is null then
    raise exception 'Booking not found.' using errcode = 'P0002';
  end if;

  select coalesce(sum(p.amount_inr) * 100, 0)::bigint into v_paid
    from payments p where p.booking_id = b.id and p.status = 'paid';

  return jsonb_build_object(
    'bookingId', b.id,
    'facilityId', b.facility_id,
    'customerType', b.customer_type,
    'status', b.status::text,
    'paymentStatus', b.payment_status::text,
    'amountMinor', coalesce(b.amount_minor, 0),
    'paidMinor', v_paid,
    'courtId', b.court_id,
    'startTime', b.start_time,
    'endTime', b.end_time,
    'name', coalesce(b.guest_name, me.full_name),
    'phone', coalesce(b.guest_phone, me.phone)
  );
end;
$$;
revoke all on function player_booking_payment_context(uuid) from public, anon;
grant execute on function player_booking_payment_context(uuid) to authenticated;

notify pgrst, 'reload schema';
