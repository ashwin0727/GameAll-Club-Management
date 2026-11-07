-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFY seed_qa_edge_cases.sql — what the Player app will actually receive. Run each block and compare with the "EXPECT" line.
-- (The public functions are the ones the apps call, so this is the truth the screens are built on.)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1 · The QA venues that exist, and which ones the Player app is allowed to see ------------------------------------------------------
select f.slug, f.name, f.city, f.status::text as status, f.onboarding_step::text as step,
       (select count(*) from courts c where c.facility_id = f.id and not c.archived and c.status = 'ACTIVE' and c.booking_enabled) as bookable_courts,
       (select count(*) from membership_plans p where p.facility_id = f.id and p.is_active) as active_plans,
       (select count(*) from coaching_programs cp where cp.facility_id = f.id and cp.status = 'ACTIVE') as active_programmes
  from facilities f
 where f.slug like 'qa-%' and f.slug not like 'qa-load-%'
 order by f.slug;
-- EXPECT: 25 hand-made rows. qa-inactive-venue is INACTIVE and qa-onboarding-incomplete has step PRICING (both hidden from players).
--         qa-no-bookable-court has 0 bookable courts but 1 active plan. qa-memberships-full / qa-single-court-studio have 1 active plan.

-- 2 · Venues list (what the Venues page gets) ---------------------------------------------------------------------------------------
select jsonb_array_length(list_public_venue_cards('Bangalore', 'Karnataka', 'venues')) as bangalore_venues,
       (select count(*) from jsonb_array_elements(list_public_venue_cards('Bangalore', 'Karnataka', 'venues')) e where e ->> 'name' like 'QA %') as qa_in_bangalore;
-- EXPECT: the 3 hidden/odd venues are absent: run the next query to see them missing.
select e ->> 'name' as name
  from jsonb_array_elements(list_public_venue_cards('Bangalore', 'Karnataka', 'venues')) e
 where e ->> 'name' ilike any (array['%Inactive%', '%Half Set Up%', '%No Bookable Court%']);
-- EXPECT: 0 rows (inactive, half set up and no-bookable-court venues are NOT in the Venues list).

-- 3 · Memberships list ---------------------------------------------------------------------------------------------------------------
select e ->> 'name' as name, e -> 'memberships' ->> 'count' as plans, e -> 'memberships' -> 'plans' as per_length, e -> 'memberships' -> 'bySport' as by_sport
  from jsonb_array_elements(list_public_venue_cards('Bangalore', 'Karnataka', 'memberships')) e
 where e ->> 'name' like 'QA %'
 order by 1;
-- EXPECT: "QA No Bookable Court" IS here (it sells plans). "QA Inactive Venue" and "QA Half Set Up" are NOT. QA Multi-Sport Arena has
--         bySport for Badminton / Padel / Football / Pickleball / Tennis. "QA Budget Courts" has plans of 10, 7, 45 and 30 days (and "Retired Plan" must be absent).

-- 4 · Coaching list: ONE programme per venue AND sport, the latest created ------------------------------------------------------------
select e -> 'venue' ->> 'name' as venue, e ->> 'sport' as sport, e ->> 'name' as programme, e ->> 'feeType' as fee, (e ->> 'priceMinor')::int / 100 as price_inr,
       e ->> 'programType' as type, e -> 'coach' ->> 'name' as coach
  from jsonb_array_elements(list_public_coaching_programs('Bangalore', 'Karnataka')) e
 where e -> 'venue' ->> 'name' like 'QA %' and e -> 'venue' ->> 'name' not like 'QA Load%'
 order by 1, 2;
-- EXPECT: QA Multi-Sport Arena → Badminton "Badminton Beginner Program" (NOT "Badminton Advanced Squad", which is older), Tennis "Tennis Starters",
--         Padel "Padel Pro Clinic" (₹25,000), Football "Football Juniors" (coach = null).
--         QA Coaching Showcase → Badminton "Early Bird Monthly" at ₹3,399 (₹3,999 − ₹500 discount), Tennis "Tennis Closed Enrolment" at ₹4,500 (discount expired),
--         Cricket "Free Cricket Trial" at ₹0 (TRIAL, no coach), Football "Football Coming Soon" (no batches). NO Pickleball row (ended / inactive).

-- 5 · One venue's enrolment answers --------------------------------------------------------------------------------------------------
select jsonb_pretty(get_public_coaching_enroll((select id from facilities where slug = 'qa-coaching-showcase')));
select jsonb_pretty(get_public_membership_enroll((select id from facilities where slug = 'qa-memberships-full')));
-- EXPECT: coaching "Tennis Closed Enrolment" → enrollmentOpen false. membership: the 18:00 slot has spare 0, the 06:00 slot has spare 3.

-- 6 · Venue page data ----------------------------------------------------------------------------------------------------------------
select jsonb_pretty(get_public_venue((select id from facilities where slug = 'qa-multi-sport-arena')));
-- EXPECT: 6 sports (Badminton, Pickleball, Cricket, Football, Tennis, Padel), 7 courts, 3 photos, hours 06:00–22:00, all five amenities.

-- 7 · City handling -------------------------------------------------------------------------------------------------------------------
select 'Bangalore' as asked, jsonb_array_length(list_public_venue_cards('Bangalore', 'Karnataka', 'venues')) as venues
union all select 'Bengaluru', jsonb_array_length(list_public_venue_cards('Bengaluru', 'Karnataka', 'venues'))
union all select 'Chennai',   jsonb_array_length(list_public_venue_cards('Chennai', 'Tamil Nadu', 'venues'))
union all select 'Hyderabad (memberships)', jsonb_array_length(list_public_venue_cards('Hyderabad', 'Telangana', 'memberships'))
union all select 'Hyderabad (coaching)',    jsonb_array_length(list_public_coaching_programs('Hyderabad', 'Telangana'))
union all select 'Atlantis (nothing)',      jsonb_array_length(list_public_venue_cards('Atlantis', null, 'venues'));
-- EXPECT: Bangalore = Bengaluru (same city); Chennai 2; Hyderabad memberships 0 and coaching 0; Atlantis 0.

-- 8 · Fully booked tomorrow / maintenance ---------------------------------------------------------------------------------------------
select count(*) as bookings_tomorrow
  from bookings b join facilities f on f.id = b.facility_id
 where f.slug = 'qa-fully-booked' and (b.start_time at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date + 1;
-- EXPECT: 16 (06:00–22:00). The Guest Booking page for that venue must show NO free hour tomorrow, and 5 booked hours the day after.

select c.name, mb.status, mb.start_time, mb.end_time
  from maintenance_blocks mb join courts c on c.id = mb.court_id join facilities f on f.id = mb.facility_id
 where f.slug = 'qa-maintenance';
-- EXPECT: one ACTIVE block on "Court 1 (under maintenance)" for the next 3 days; Court 2 has none.

-- 9 · The test player's payment states (only if v_player_phone was set) ---------------------------------------------------------------
select ms.name as membership, ms.status::text as status, ms.total_amount_inr as total,
       coalesce((select sum(p.amount_inr) from payments p where p.membership_id = ms.id and p.status = 'paid'), 0) as paid,
       (select string_agg(distinct p.status::text, ',') from payments p where p.membership_id = ms.id) as payment_rows,
       (select s.status::text from membership_subscriptions s where s.membership_id = ms.id) as autopay
  from memberships ms join members m on m.id = ms.member_id join facilities f on f.id = ms.facility_id
 where f.slug = 'qa-multi-sport-arena' and m.full_name = 'QA Test Player'
 order by ms.created_at;
-- EXPECT 8 rows. On the Player Home: #1 and #6 are fine, #2 #4 are "Payment Incomplete" (PENDING prompts), #3 and #5 are FAILED prompts, #7 and #8 are not shown.

-- 10 · Load venues ------------------------------------------------------------------------------------------------------------------
select count(*) as load_venues from facilities where slug like 'qa-load-%';
-- EXPECT: 60 (0 if you switched the load off).
