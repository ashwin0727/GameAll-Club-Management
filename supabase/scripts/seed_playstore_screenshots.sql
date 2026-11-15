-- ═════════════════════════════════════════════════════════════════════
-- PLAY STORE SCREENSHOT DATA — makes the demo venue look like a real, busy, approved venue, and gives the test PLAYER real-looking
-- bookings and a membership. Run it AFTER seed_2y_facility_dataset.sql.
--
-- NOT a migration. Run by hand in the Supabase SQL editor (use a TEST project / Razorpay test mode, never your live data).
--
-- WHAT IT DOES
--   1. Venue "Smash Arena Sports Hub" (Adyar, Chennai): a proper description, phone, indoor venue, all five amenities, the map link and the
--      photos marked VERIFIED, and the setup marked APPROVED, so GameAll Play lists it with photos and amenities.
--   2. The test player (v_player_phone) gets, at that venue: two upcoming PAID bookings, three past completed bookings, and one
--      active, fully paid membership. Nothing is unpaid, so Home shows no "payment pending" prompts in the screenshots.
--   3. Everything it inserts is written to seed2y_log, so cleanup_2y_facility_dataset.sql removes it with the rest.
--
-- BEFORE YOU RUN IT
--   a. Run seed_2y_facility_dataset.sql first (the Venue app screenshots: bookings, members, coaching, finance, reports come from it).
--   b. In GameAll Venue, open Profile > Facility > Photos and upload 3 to 4 REAL photos of a court (you may use free-licence or
--      your own photos). This script cannot create photos. It only marks the ones you uploaded as verified.
--   c. Sign in once to GameAll Play with the test number (v_player_phone) so that player exists, and give it a name.
--   d. Set the three values just below.
--
-- NOTES ON PRIVACY
--   Every name below is made up, and the phone numbers are placeholders. Do not put a real customer's name or number in a screenshot.
-- ═════════════════════════════════════════════════════════════════════

do $shots$
declare
  v_owner_email  text := 'ashwinv277@gmail.com';   -- ← the account that owns the demo venue
  v_player_phone text := '';                       -- ← the test player's 10-digit phone (e.g. '9000000099'). '' = skip the player part
  v_player_name  text := 'Karthik Subramanian';      -- ← the name that appears on the player's bookings

  v_tz        constant text := 'Asia/Kolkata';
  v_today     date := (now() at time zone 'Asia/Kolkata')::date;
  v_owner     uuid;
  v_facility  uuid;
  v_member    uuid;
  v_plan      uuid;
  v_ms        uuid;
  v_court     uuid;
  v_court2    uuid;
  v_n         integer;
begin
  select id into v_owner from profiles where lower(email) = lower(v_owner_email);
  if v_owner is null then raise exception 'No profile with e-mail %.', v_owner_email; end if;

  select id into v_facility from seed2y_log where tbl = 'facility' limit 1;
  if v_facility is null then select id into v_facility from facilities where owner_id = v_owner order by created_at limit 1; end if;
  if v_facility is null then raise exception 'No venue found. Run seed_2y_facility_dataset.sql first.'; end if;

  -- ── 1. the venue's profile ───────────────────────────────────────────────
  update facilities set
    name = 'Smash Arena Sports Hub',
    description = 'A friendly indoor sports hub in Adyar, Chennai. Three wooden-floor badminton courts, an outdoor pickleball court '
                  || 'and a floodlit cricket turf, with coaching for juniors and adults, flexible monthly memberships and easy online booking. '
                  || 'Open every day, 6 AM to 10 PM.',
    address_line_1 = '42 Lake View Road', area = 'Adyar', city = 'Chennai', state = 'Tamil Nadu', postal_code = '600020',
    business_phone = '9840012345',
    venue_type = 'INDOOR',
    has_parking = true, has_changing_rooms = true, has_toilets = true, has_cafeteria = true, has_equipment_rental = true,
    location_url = coalesce(nullif(location_url, ''), 'https://www.google.com/maps/search/?api=1&query=Adyar+Chennai'),
    location_verification_status = 'VERIFIED',
    setup_review_status = 'APPROVED',
    setup_reviewed_at = coalesce(setup_reviewed_at, now()),
    status = 'ACTIVE',
    onboarding_step = 'COMPLETED'
  where id = v_facility;

  select count(*) into v_n from facility_images where facility_id = v_facility;
  if v_n = 0 then
    raise notice 'This venue has NO photos yet. Upload 3 to 4 real court photos in GameAll Venue (Profile > Facility > Photos), then run this script again.';
  else
    update facility_images set verification_status = 'VERIFIED', verified_at = coalesce(verified_at, now()) where facility_id = v_facility;
    raise notice '% photo(s) marked verified.', v_n;
  end if;

  -- ── 2. the test player ───────────────────────────────────────────────────
  if length(v_player_phone) < 10 then
    raise notice 'v_player_phone is empty, so the player part was skipped. Set it and run again.';
    return;
  end if;
  if exists (select 1 from members where facility_id = v_facility and phone = v_player_phone) then
    raise notice 'The player already has a record at this venue, so no player data was added again.';
    return;
  end if;

  select id into v_court  from courts where facility_id = v_facility and name = 'Badminton Court 1' and not archived limit 1;
  select id into v_court2 from courts where facility_id = v_facility and name = 'Badminton Court 2' and not archived limit 1;
  if v_court is null then raise exception 'Badminton Court 1 not found. Run seed_2y_facility_dataset.sql first.'; end if;

  insert into members (facility_id, full_name, phone, status) values (v_facility, v_player_name, v_player_phone, 'ACTIVE')
  returning id into v_member;
  insert into seed2y_log values ('members', v_member);

  -- upcoming (paid) and past (completed) bookings, all in the evening so they look like a regular player's week
  insert into bookings (facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status,
                        amount_minor, currency, payment_status, notes, party_size, payment_method, created_by)
  select v_facility, case when i % 2 = 0 then v_court else coalesce(v_court2, v_court) end, 'GUEST', v_player_name, v_player_phone,
         ((v_today + d) + make_time(h, 0, 0)) at time zone v_tz, ((v_today + d) + make_time(h + 1, 0, 0)) at time zone v_tz,
         st::booking_status, 40000, 'INR', 'PAID', 'SEED2Y', 2, 'UPI', v_owner
  from (values (1, 2, 18, 'confirmed'), (2, 5, 19, 'confirmed'),
               (3, -2, 18, 'completed'), (4, -6, 19, 'completed'), (5, -9, 18, 'completed')) b(i, d, h, st);
  insert into seed2y_log select 'bookings', id from bookings where facility_id = v_facility and notes = 'SEED2Y' and guest_phone = v_player_phone;

  -- one active, fully paid membership (uses the venue's first active plan)
  select id into v_plan from membership_plans where facility_id = v_facility and is_active order by price_inr limit 1;
  if v_plan is not null then
    insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date, auto_renew, created_by, monthly_price_inr, name,
                             membership_type, duration_days, membership_fee_inr, registration_fee_inr, gst_percent, total_amount_inr)
    select v_facility, v_member, p.id, 'active'::membership_status, v_today - 10, v_today + 20, false, v_owner, p.price_inr, p.name,
           'INDIVIDUAL', 30, p.price_inr, 0, 0, p.price_inr
    from membership_plans p where p.id = v_plan
    returning id into v_ms;
    insert into seed2y_log values ('memberships', v_ms);
    insert into payments (facility_id, member_id, membership_id, amount_inr, status, payment_method, paid_at)
    select v_facility, v_member, v_ms, price_inr, 'paid'::payment_status, 'UPI', now() - interval '10 days' from membership_plans where id = v_plan;
    insert into seed2y_log select 'payments', id from payments where membership_id = v_ms;
  else
    raise notice 'The venue has no active membership plan, so the player got bookings only.';
  end if;

  raise notice 'Done. Sign in to GameAll Play as % and check Home, My Bookings and Memberships.', v_player_phone;
end
$shots$;
