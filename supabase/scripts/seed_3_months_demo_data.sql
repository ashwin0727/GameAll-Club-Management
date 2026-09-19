-- ═══════════════════════════════════════════════════════════════════════════
-- 3-month MOCKUP data — every row below is hand-authored (no random()
-- anywhere): specific guests, specific members, specific dates, specific
-- amounts, specific paid/pending/cancelled outcomes, chosen by hand to
-- spread realistically across the last 90 days.
--
-- The only things resolved automatically (because they're your real ids,
-- not something to invent) are: your facility, your existing courts, and
-- your existing membership plans. Everything else is a literal value you
-- can read straight off this file.
--
-- NOT a migration — run once, by hand, in the Supabase SQL editor. Do not
-- run it twice without reverting first (see the REVERT block at the
-- bottom) or every row doubles.
--
-- Identifiable / reversible by:
--   - guest_players.phone      = '9000000001'..'9000000010'
--   - members.phone            = '8000000001'..'8000000010'
--   - membership_plans.name    = 'Demo Plan Monthly'
--     (only created if you have no active plans of your own)
--
-- NOT included: Coaching (needs a real staff profile as the coach — tell me
-- who and I'll add it), Tournaments (no backend table exists for it in this
-- project yet), and Membership Sessions usage (left out of this pass —
-- say the word and it'll be added the same explicit, hand-authored way).
--
-- HOW TO RUN: change the email below if this isn't the right account, then
-- run the whole file as one block.
-- ═══════════════════════════════════════════════════════════════════════════

do $$
declare
  v_owner_email text := 'ashwinv277@gmail.com';
  v_facility uuid;
  v_owner_id uuid;
  v_court1 uuid;   -- your first bookable court
  v_court2 uuid;   -- your second, if you have one (else same as v_court1)
  v_plan_id uuid;  -- one of your existing active plans, or a demo one
begin
  select f.id, f.owner_id into v_facility, v_owner_id
  from facilities f join profiles p on p.id = f.owner_id
  where p.email = v_owner_email;

  if v_facility is null then
    raise exception 'No facility found for owner email %', v_owner_email;
  end if;

  select id into v_court1 from courts
    where facility_id = v_facility and archived = false and status = 'ACTIVE' and booking_enabled = true
    order by created_at limit 1;
  select id into v_court2 from courts
    where facility_id = v_facility and archived = false and status = 'ACTIVE' and booking_enabled = true and id <> v_court1
    order by created_at limit 1;
  if v_court1 is null then
    raise exception 'Facility % has no bookable courts — set up courts before seeding.', v_facility;
  end if;
  if v_court2 is null then
    v_court2 := v_court1;
  end if;

  select id into v_plan_id from membership_plans
    where facility_id = v_facility and is_active = true
    order by created_at limit 1;
  if v_plan_id is null then
    insert into membership_plans (facility_id, name, price_inr, duration_days, features)
    values (v_facility, 'Demo Plan Monthly', 1500, 30, array['Unlimited off-peak court time'])
    returning id into v_plan_id;
    raise notice 'No existing active membership plan — created "Demo Plan Monthly".';
  end if;

  raise notice 'Seeding facility % — court1=%, court2=%, plan=%', v_facility, v_court1, v_court2, v_plan_id;

  -----------------------------------------------------------------------
  -- A. GUEST PLAYERS — 10 named guests, phones 9000000001..9000000010.
  -----------------------------------------------------------------------
  insert into guest_players (facility_id, name, phone) values
    (v_facility, 'Rahul Sharma',   '9000000001'),
    (v_facility, 'Priya Menon',    '9000000002'),
    (v_facility, 'Arjun Iyer',     '9000000003'),
    (v_facility, 'Ananya Reddy',   '9000000004'),
    (v_facility, 'Vikram Nair',    '9000000005'),
    (v_facility, 'Sneha Rao',      '9000000006'),
    (v_facility, 'Karthik Kumar',  '9000000007'),
    (v_facility, 'Divya Pillai',   '9000000008'),
    (v_facility, 'Rohan Verma',    '9000000009'),
    (v_facility, 'Meera Krishnan', '9000000010')
  on conflict do nothing;

  raise notice '10 guest players seeded.';

  -----------------------------------------------------------------------
  -- B. GUEST BOOKINGS — one hand-picked row roughly per week for ~12
  -- weeks (oldest first), alternating courts, mixing paid / pending /
  -- cancelled. day_offset = how many days before today it happened.
  -----------------------------------------------------------------------
  with rows(day_offset, hour, guest_phone, court, amount_rupees, outcome) as (
    values
      (88, 7,  '9000000001', 1, 300, 'paid'),
      (81, 18, '9000000002', 2, 350, 'paid'),
      (74, 9,  '9000000003', 1, 250, 'pending'),
      (67, 19, '9000000004', 2, 400, 'paid'),
      (60, 7,  '9000000005', 1, 300, 'cancelled'),
      (53, 20, '9000000006', 2, 450, 'paid'),
      (46, 8,  '9000000007', 1, 300, 'paid'),
      (39, 17, '9000000008', 2, 350, 'pending'),
      (32, 7,  '9000000009', 1, 250, 'paid'),
      (25, 19, '9000000010', 2, 400, 'paid'),
      (18, 9,  '9000000001', 1, 300, 'paid'),
      (11, 18, '9000000003', 2, 350, 'pending'),
      (7,  7,  '9000000005', 1, 300, 'paid'),
      (4,  19, '9000000007', 2, 400, 'paid'),
      (1,  8,  '9000000009', 1, 250, 'paid')
  ),
  resolved as (
    select
      r.*,
      (current_date - r.day_offset)::timestamp + make_interval(hours => r.hour) as start_at,
      (select id from guest_players where facility_id = v_facility and phone = r.guest_phone) as guest_id,
      case when r.court = 1 then v_court1 else v_court2 end as court_id
    from rows r
  ),
  inserted as (
    insert into bookings (
      facility_id, court_id, member_id, start_time, end_time, status,
      customer_type, guest_name, guest_phone, guest_player_id,
      amount_minor, currency, notes, created_by, payment_status,
      party_size, payment_method, created_at
    )
    select
      v_facility, res.court_id, null, res.start_at, res.start_at + interval '1 hour',
      (case when res.outcome = 'cancelled' then 'cancelled' else 'completed' end)::booking_status,
      'GUEST', gp.name, gp.phone, res.guest_id,
      res.amount_rupees * 100, 'INR', null, v_owner_id,
      (case when res.outcome = 'paid' then 'PAID' else 'PENDING' end),
      2, (case when res.outcome = 'paid' then 'UPI' else null end), res.start_at
    from resolved res
    join guest_players gp on gp.id = res.guest_id
    returning id, amount_minor, created_at, guest_player_id, (payment_status = 'PAID') as is_paid
  )
  insert into payments (facility_id, member_id, membership_id, booking_id, guest_player_id, amount_inr, status, payment_method, paid_at, created_at)
  select v_facility, null, null, i.id, i.guest_player_id, i.amount_minor / 100, 'paid'::payment_status, 'UPI', i.created_at, i.created_at
  from inserted i
  where i.is_paid;

  raise notice '15 guest bookings seeded across 12 weeks.';

  -----------------------------------------------------------------------
  -- C. MEMBERS + MEMBERSHIPS — 10 named members, phones 8000000001..10,
  -- joined on hand-picked dates spread across the 3 months.
  -----------------------------------------------------------------------
  with rows(name, phone, join_offset) as (
    values
      ('Suresh Bhat',   '8000000001', 89),
      ('Pooja Das',     '8000000002', 80),
      ('Manoj Shetty',  '8000000003', 71),
      ('Neha Joshi',    '8000000004', 62),
      ('Ravi Krishnan', '8000000005', 53),
      ('Deepa Nair',    '8000000006', 44),
      ('Sanjay Gupta',  '8000000007', 35),
      ('Anjali Iyer',   '8000000008', 26),
      ('Kiran Reddy',   '8000000009', 12),
      ('Swathi Menon',  '8000000010', 3)
  )
  insert into members (facility_id, full_name, phone, status, created_at, updated_at)
  select v_facility, r.name, r.phone, 'ACTIVE', current_date - r.join_offset, current_date - r.join_offset
  from rows r
  on conflict (facility_id, phone) do nothing;

  raise notice '10 members seeded.';

  -- One membership per member, on your plan, dated from their join day.
  -- Expired members get an end_date already in the past; pending members
  -- get no payment row (signed up, never paid — same shape as the real
  -- "Madhan" bug this session fixed earlier).
  with rows(phone, join_offset, status, duration_days) as (
    values
      ('8000000001', 89, 'active',  30),
      ('8000000002', 80, 'active',  30),
      ('8000000003', 71, 'expired', 30),
      ('8000000004', 62, 'active',  30),
      ('8000000005', 53, 'active',  30),
      ('8000000006', 44, 'pending', 30),
      ('8000000007', 35, 'active',  30),
      ('8000000008', 26, 'active',  30),
      ('8000000009', 12, 'active',  30),
      ('8000000010', 3,  'pending', 30)
  ),
  resolved as (
    select
      m.id as member_id,
      (current_date - r.join_offset) as start_date,
      (current_date - r.join_offset) + r.duration_days as natural_end,
      r.status
    from rows r
    join members m on m.facility_id = v_facility and m.phone = r.phone
  ),
  inserted as (
    insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date, created_at)
    select
      v_facility, res.member_id, v_plan_id, res.status::membership_status,
      res.start_date,
      case when res.status = 'expired' then least(res.natural_end, current_date - 1) else res.natural_end end,
      res.start_date
    from resolved res
    returning id, member_id, status, start_date, (
      select price_inr from membership_plans where id = v_plan_id
    ) as price_inr
  )
  insert into payments (facility_id, member_id, membership_id, amount_inr, status, payment_method, paid_at, created_at)
  select v_facility, i.member_id, i.id, i.price_inr, 'paid'::payment_status, 'UPI', i.start_date::timestamp, i.start_date::timestamp
  from inserted i
  where i.status <> 'pending';

  raise notice '10 memberships seeded (2 pending / unpaid, 1 expired, 7 active).';

  raise notice 'Done.';
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- REVERT — removes exactly what this file added, nothing else. Uncomment
-- and run the whole block to undo.
-- ═══════════════════════════════════════════════════════════════════════════
-- begin;
--
-- delete from payments
--   where booking_id in (select id from bookings where guest_player_id in (select id from guest_players where phone like '9000000%'))
--      or guest_player_id in (select id from guest_players where phone like '9000000%')
--      or membership_id in (select id from memberships where member_id in (select id from members where phone like '8000000%'));
--
-- delete from bookings where guest_player_id in (select id from guest_players where phone like '9000000%');
-- delete from guest_players where phone like '9000000%';
-- delete from memberships where member_id in (select id from members where phone like '8000000%');
-- delete from members where phone like '8000000%';
--
-- -- Only if you also want the demo plan gone (skip if you're keeping it):
-- -- delete from membership_plans where name = 'Demo Plan Monthly';
--
-- commit;
