-- ═══════════════════════════════════════════════════════════════════════════
-- GameAll — TEST VENUES (fake data for trying the Player app end to end)
--
--   !!  FOR TESTING ONLY. Remove it afterwards with test_venues_cleanup.sql.  !!
--
-- Run this in the Supabase SQL editor (it runs as the service role, which is what lets it write verified photos and locations).
-- Needs migrations 0169 - 0174 applied first.
--
-- What it creates (every row is traceable: the owner is seed.owner@gameall.test, every facility's slug starts with "seed-", every
-- phone number is 9000000001 - 9000000003):
--
--   6 venues in 3 cities, each with sports, courts, rates, opening hours, an amenity mix, a description and a Google Maps link:
--     Champz Turf          Chennai    indoor   badminton x3 + football x1   photos approved, map verified, plans + coaching
--     Smash Arena          Chennai    indoor   badminton x4 + tennis x1     photos approved, map verified, plans + coaching
--     Kickoff Sports       Chennai    outdoor  football x2 + cricket x1     photos WAITING for review, map NOT verified (shows the drawn court)
--     Ace Pickle Club      Bengaluru  outdoor  pickleball x4 + padel x2     photos approved, map verified, plans
--     Hoops & Rackets      Bengaluru  indoor   basketball x1 + badminton x2 + tennis x2   approved, plans + coaching
--     Boundary Cricket Hub Hyderabad  outdoor  cricket x3 + football x1     photos approved, map verified, nothing else
--
--   Test players (log in on the Player app with just the number while codes are off):
--     9000000001  Arun Test    an active membership at Champz Turf, coaching at Smash Arena, 2 upcoming guest bookings
--     9000000002  Meena Test   an active membership at Ace Pickle Club
--     9000000003  Ravi Test    a guest booking only
--
-- Photos are public-domain / Creative Commons pictures from Wikimedia Commons (hot-linked), fine for testing, not for production.
-- ═══════════════════════════════════════════════════════════════════════════

do $seed$
declare
  seed_owner uuid;
  v jsonb;
  sp jsonb;
  ct jsonb;
  pl jsonb;
  pr jsonb;
  ph jsonb;
  fid uuid;
  fsid uuid;
  cid uuid;
  sport_row_id uuid;
  plan_id uuid;
  sched_id uuid;
  day_id uuid;
  dow int;
  facilities_data jsonb := $json$[
    {
      "slug": "seed-champz-turf", "name": "Champz Turf", "type": "MULTI_SPORT", "venue": "INDOOR",
      "city": "Chennai", "state": "Tamil Nadu", "area": "Iyyapanthangal", "line1": "No. 45, Mount Poonamallee Road", "pin": "600056",
      "phone": "9840011001", "email": "champz@seed.gameall.test", "lat": 13.0295, "lng": 80.1374,
      "description": "Premium indoor facility with well-maintained wooden badminton courts, a small-sided football turf, coaching and flexible membership plans.",
      "amenities": {"parking": true, "changing": true, "toilets": true, "cafe": true, "rental": true},
      "opens": "06:00", "closes": "23:00", "location": "VERIFIED",
      "photos": [["https://upload.wikimedia.org/wikipedia/commons/thumb/2/25/Badminton_court_view.jpg/1280px-Badminton_court_view.jpg", "VERIFIED"], ["https://upload.wikimedia.org/wikipedia/commons/thumb/9/90/Interior_overview_of_the_indoor_sports_hall_at_OAU_Gymnasium.jpg/1280px-Interior_overview_of_the_indoor_sports_hall_at_OAU_Gymnasium.jpg", "VERIFIED"], ["https://upload.wikimedia.org/wikipedia/commons/thumb/1/1b/Badminton_Court_NISER.jpg/1280px-Badminton_Court_NISER.jpg", "VERIFIED"]],
      "sports": [
        {"key": "badminton", "rate": 400, "weekend": 500, "surface": "Wooden", "courts": ["Court 1", "Court 2", "Court 3"]},
        {"key": "football", "rate": 1200, "surface": "Artificial turf", "courts": ["Turf A"]}
      ],
      "plans": [["Monthly Unlimited", 2999, 30], ["Quarterly Saver", 7999, 90], ["Evening Play", 1999, 30]],
      "programs": [["Junior Badminton Academy", "Beginner", "Kids 8-14", 1500], ["Adult Performance Coaching", "Intermediate", "Adults", 2500]]
    },
    {
      "slug": "seed-smash-arena", "name": "Smash Arena", "type": "BADMINTON", "venue": "INDOOR",
      "city": "Chennai", "state": "Tamil Nadu", "area": "Adyar", "line1": "12, Lattice Bridge Road", "pin": "600020",
      "phone": "9840022002", "email": "smash@seed.gameall.test", "lat": 13.0063, "lng": 80.2574,
      "description": "Chennai's dedicated badminton centre: four BWF-grade courts, certified coaches and a relaxed cafeteria.",
      "amenities": {"parking": true, "changing": true, "toilets": true, "cafe": true, "rental": false},
      "opens": "05:30", "closes": "22:30", "location": "VERIFIED",
      "photos": [["https://upload.wikimedia.org/wikipedia/commons/thumb/d/de/Wo_Che_Estate_Badminton_Court.jpg/1280px-Wo_Che_Estate_Badminton_Court.jpg", "VERIFIED"], ["https://upload.wikimedia.org/wikipedia/commons/thumb/8/88/Multipurpose_Indoor_Sport_Hall.jpg/1280px-Multipurpose_Indoor_Sport_Hall.jpg", "VERIFIED"]],
      "sports": [
        {"key": "badminton", "rate": 450, "weekend": 550, "surface": "Wooden", "courts": ["Court 1", "Court 2", "Court 3", "Court 4"]},
        {"key": "tennis", "rate": 700, "surface": "Hard", "courts": ["Tennis Court"]}
      ],
      "plans": [["Gold Membership", 3499, 30], ["Silver Membership", 2499, 30]],
      "programs": [["Beginner Badminton", "Beginner", "All ages", 1200], ["Advanced Squad", "Advanced", "Teens & Adults", 3000]]
    },
    {
      "slug": "seed-kickoff-sports", "name": "Kickoff Sports", "type": "MULTI_SPORT", "venue": "OUTDOOR",
      "city": "Chennai", "state": "Tamil Nadu", "area": "Mangadu", "line1": "Plot 7, Kundrathur Main Road", "pin": "600122",
      "phone": "9840033003", "email": "kickoff@seed.gameall.test", "lat": 13.0305, "lng": 80.1109,
      "description": "Floodlit open-air turfs for football and box cricket. Newly registered: photos and location are still waiting for GameAll to verify.",
      "amenities": {"parking": true, "changing": false, "toilets": true, "cafe": false, "rental": false},
      "opens": "06:00", "closes": "23:00", "location": "PENDING",
      "photos": [["https://upload.wikimedia.org/wikipedia/commons/thumb/2/2d/Kaukaj%C3%A4rvi_artificial_turf_pitch.jpg/1280px-Kaukaj%C3%A4rvi_artificial_turf_pitch.jpg", "PENDING"]],
      "sports": [
        {"key": "football", "rate": 1000, "surface": "Artificial turf", "courts": ["Turf 1", "Turf 2"]},
        {"key": "cricket", "rate": 900, "surface": "Artificial turf", "courts": ["Box Cricket Net"]}
      ],
      "plans": [], "programs": []
    },
    {
      "slug": "seed-ace-pickle-club", "name": "Ace Pickle Club", "type": "MULTI_SPORT", "venue": "OUTDOOR",
      "city": "Bengaluru", "state": "Karnataka", "area": "Indiranagar", "line1": "100 Feet Road, 2nd Stage", "pin": "560038",
      "phone": "9880044004", "email": "acepickle@seed.gameall.test", "lat": 12.9784, "lng": 77.6408,
      "description": "Bengaluru's friendliest pickleball and padel club with glass-walled padel courts, rental paddles and weekend leagues.",
      "amenities": {"parking": true, "changing": true, "toilets": true, "cafe": true, "rental": true},
      "opens": "06:00", "closes": "22:00", "location": "VERIFIED",
      "photos": [["https://upload.wikimedia.org/wikipedia/commons/thumb/3/39/Outdoor_pickleball_courts.jpg/1280px-Outdoor_pickleball_courts.jpg", "VERIFIED"], ["https://upload.wikimedia.org/wikipedia/commons/thumb/7/72/Padel_court.jpg/1280px-Padel_court.jpg", "VERIFIED"]],
      "sports": [
        {"key": "pickleball", "rate": 500, "weekend": 650, "surface": "Acrylic", "courts": ["Court A", "Court B", "Court C", "Court D"]},
        {"key": "other", "custom": "Padel", "rate": 1400, "surface": "Artificial grass", "courts": ["Padel 1", "Padel 2"]}
      ],
      "plans": [["Club Member", 2499, 30], ["Pickle Pass (3 months)", 6499, 90]],
      "programs": []
    },
    {
      "slug": "seed-hoops-and-rackets", "name": "Hoops & Rackets", "type": "MULTI_SPORT", "venue": "INDOOR",
      "city": "Bengaluru", "state": "Karnataka", "area": "Koramangala", "line1": "80 Feet Road, 4th Block", "pin": "560034",
      "phone": "9880055005", "email": "hoops@seed.gameall.test", "lat": 12.9352, "lng": 77.6245,
      "description": "A multi-sport indoor complex: full-size basketball court, two badminton courts and two tennis courts with a pro shop.",
      "amenities": {"parking": false, "changing": true, "toilets": true, "cafe": true, "rental": true},
      "opens": "06:00", "closes": "22:00", "location": "VERIFIED",
      "photos": [["https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Indoor_Basketball_Court_in_Karlovasi%2C_Samos.jpg/1280px-Indoor_Basketball_Court_in_Karlovasi%2C_Samos.jpg", "VERIFIED"], ["https://upload.wikimedia.org/wikipedia/commons/thumb/c/cc/Hanes_Park_hard_surface_tennis_courts%2C_2026.jpg/1280px-Hanes_Park_hard_surface_tennis_courts%2C_2026.jpg", "VERIFIED"]],
      "sports": [
        {"key": "other", "custom": "Basketball", "rate": 1500, "surface": "Hardwood", "courts": ["Main Court"]},
        {"key": "badminton", "rate": 380, "surface": "Wooden", "courts": ["Badminton 1", "Badminton 2"]},
        {"key": "tennis", "rate": 650, "surface": "Hard", "courts": ["Tennis 1", "Tennis 2"]}
      ],
      "plans": [["All-Sport Pass", 3999, 30]],
      "programs": [["Youth Basketball Camp", "Beginner", "Kids 10-16", 2000]]
    },
    {
      "slug": "seed-boundary-cricket-hub", "name": "Boundary Cricket Hub", "type": "MULTI_SPORT", "venue": "OUTDOOR",
      "city": "Hyderabad", "state": "Telangana", "area": "Gachibowli", "line1": "Survey 12, Nanakramguda Road", "pin": "500032",
      "phone": "9990066006", "email": "boundary@seed.gameall.test", "lat": 17.4401, "lng": 78.3489,
      "description": "Three practice nets and a five-a-side football turf, open late. Walk-in friendly: no memberships or coaching yet.",
      "amenities": {"parking": true, "changing": false, "toilets": true, "cafe": false, "rental": true},
      "opens": "05:00", "closes": "23:00", "location": "VERIFIED",
      "photos": [["https://upload.wikimedia.org/wikipedia/commons/thumb/9/97/Cricket_nets%2C_Fred_Mayhead_Memorial_Ground%2C_Normandy_Cricket_Club%2C_Surrey_01.jpg/1280px-Cricket_nets%2C_Fred_Mayhead_Memorial_Ground%2C_Normandy_Cricket_Club%2C_Surrey_01.jpg", "VERIFIED"], ["https://upload.wikimedia.org/wikipedia/commons/thumb/5/59/Cricket_nets%2C_Fred_Mayhead_Memorial_Ground%2C_Normandy_Cricket_Club%2C_Surrey_02.jpg/1280px-Cricket_nets%2C_Fred_Mayhead_Memorial_Ground%2C_Normandy_Cricket_Club%2C_Surrey_02.jpg", "VERIFIED"], ["https://upload.wikimedia.org/wikipedia/commons/thumb/a/ac/Artificial_Turf_Football_Field_at_Regent%27s_International_School_Bangkok.jpg/1280px-Artificial_Turf_Football_Field_at_Regent%27s_International_School_Bangkok.jpg", "VERIFIED"]],
      "sports": [
        {"key": "cricket", "rate": 800, "surface": "Artificial turf", "courts": ["Net 1", "Net 2", "Net 3"]},
        {"key": "football", "rate": 1100, "surface": "Artificial turf", "courts": ["Five-a-side Turf"]}
      ],
      "plans": [], "programs": []
    }
  ]$json$::jsonb;
begin
  if exists (select 1 from auth.users where lower(email) = 'seed.owner@gameall.test') then
    raise exception 'The test venues are already loaded. Run test_venues_cleanup.sql first if you want to reload them.';
  end if;

  -- the owner of every test venue
  seed_owner := gen_random_uuid();
  -- (no password: nobody can sign in as this account, it only owns the venues)
  insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
  values (seed_owner, 'seed.owner@gameall.test', now(),
          '{"full_name": "Test Venue Owner"}'::jsonb, '{"provider": "email", "providers": ["email"]}'::jsonb, now(), now());
  insert into profiles (id, full_name, email, role, onboarding_completed)
  values (seed_owner, 'Test Venue Owner', 'seed.owner@gameall.test', 'admin', true)
  on conflict (id) do update set onboarding_completed = true;

  for v in select * from jsonb_array_elements(facilities_data) loop
    fid := gen_random_uuid();
    insert into facilities (
      id, name, slug, owner_id, facility_type, business_email, business_phone, address_line_1, area, city, state, country, postal_code,
      latitude, longitude, timezone, currency, description, status, onboarding_step, onboarding_completed_at,
      location_url, venue_type, has_parking, has_changing_rooms, has_toilets, has_cafeteria, has_equipment_rental)
    values (
      fid, v->>'name', v->>'slug', seed_owner, (v->>'type')::facility_type, v->>'email', v->>'phone', v->>'line1', v->>'area', v->>'city', v->>'state', 'India', v->>'pin',
      (v->>'lat')::numeric, (v->>'lng')::numeric, 'Asia/Kolkata', 'INR', v->>'description', 'ACTIVE', 'COMPLETED', now(),
      'https://www.google.com/maps/search/?api=1&query=' || (v->>'lat') || ',' || (v->>'lng'),
      v->>'venue',
      (v#>>'{amenities,parking}')::boolean, (v#>>'{amenities,changing}')::boolean, (v#>>'{amenities,toilets}')::boolean,
      (v#>>'{amenities,cafe}')::boolean, (v#>>'{amenities,rental}')::boolean);
    -- the admin's verdict on the map link (this script runs as the service role, so it may set it)
    update facilities set location_verification_status = v->>'location',
                          location_verification_note = case when v->>'location' = 'PENDING' then null else 'Test data: location confirmed.' end
     where id = fid;
    insert into facility_users (facility_id, user_id, role) values (fid, seed_owner, 'owner');

    -- photos, cover first
    for ph in select * from jsonb_array_elements(v->'photos') loop
      insert into facility_images (facility_id, url, sort_order, verification_status)
      values (fid, ph->>0, (select count(*) from facility_images where facility_id = fid), ph->>1);
    end loop;

    -- sports, courts and rates
    insert into pricing_plans (facility_id, name) values (fid, 'Standard Pricing') returning id into plan_id;
    for sp in select * from jsonb_array_elements(v->'sports') loop
      select id into sport_row_id from sports where key = sp->>'key';
      fsid := gen_random_uuid();
      insert into facility_sports (id, facility_id, sport_id, is_active, custom_sport_name)
      values (fsid, fid, sport_row_id, true, sp->>'custom');
      for ct in select * from jsonb_array_elements(sp->'courts') loop
        insert into courts (facility_id, sport_id, facility_sport_id, name, hourly_rate_inr, surface, area_type, display_order, status, booking_enabled)
        values (fid, sport_row_id, fsid, ct #>> '{}', (sp->>'rate')::int, sp->>'surface', (v->>'venue')::area_type,
                (select count(*) from courts where facility_id = fid), 'ACTIVE', true);
      end loop;
      insert into pricing_rules (pricing_plan_id, facility_id, facility_sport_id, day_type, covers_full_day, amount_minor, pricing_unit, priority)
      values (plan_id, fid, fsid, 'ALL_DAYS', true, (sp->>'rate')::int * 100, 'PER_HOUR', 0);
      if sp ? 'weekend' then
        insert into pricing_rules (pricing_plan_id, facility_id, facility_sport_id, day_type, covers_full_day, amount_minor, pricing_unit, priority)
        values (plan_id, fid, fsid, 'WEEKENDS', true, (sp->>'weekend')::int * 100, 'PER_HOUR', 10);
      end if;
    end loop;

    -- opening hours: every day, one block
    insert into operating_schedules (facility_id, scope_type, timezone) values (fid, 'FACILITY', 'Asia/Kolkata') returning id into sched_id;
    for dow in 0..6 loop
      insert into operating_days (schedule_id, facility_id, day_of_week) values (sched_id, fid, dow) returning id into day_id;
      insert into operating_time_slots (operating_day_id, facility_id, start_time, end_time)
      values (day_id, fid, (v->>'opens')::time, (v->>'closes')::time);
    end loop;

    -- membership plans and coaching programmes
    for pl in select * from jsonb_array_elements(v->'plans') loop
      insert into membership_plans (facility_id, name, price_inr, duration_days, features)
      values (fid, pl->>0, (pl->>1)::int, (pl->>2)::int, array['Priority booking', 'Free guest pass']);
    end loop;
    -- membership time slots (every plan is offered in two early-morning slots, so the Enroll page has something to pick; kept clear of the
    -- evening so guest booking still has hours to show)
    insert into membership_batches (facility_id, plan_id, facility_sport_id, court_id, name, days_of_week, start_time, end_time, capacity)
    select fid, mp.id, c.facility_sport_id, c.id, mp.name || ' - ' || t.label, '{0,1,2,3,4,5,6}'::smallint[], t.s, t.e, t.cap
      from membership_plans mp
      join lateral (select id, facility_sport_id from courts where facility_id = fid order by display_order limit 1) c on true
      cross join (values ('Early morning', time '06:00', time '07:00', 6), ('Morning', time '07:00', time '08:00', 10)) as t(label, s, e, cap)
     where mp.facility_id = fid;
    for pr in select * from jsonb_array_elements(v->'programs') loop
      insert into coaching_programs (facility_id, name, level, age_group, category, description, default_duration_minutes, default_capacity, default_price_minor, status)
      values (fid, pr->>0, pr->>1, pr->>2, 'Training', 'Test programme: ' || (pr->>0), 60, 12, (pr->>3)::int * 100, 'ACTIVE');
    end loop;
  end loop;
end
$seed$;


-- ── test players: records the clubs would have taken when these people joined ─────────────────────────────
do $players$
declare
  champz uuid := (select id from facilities where slug = 'seed-champz-turf');
  smash uuid := (select id from facilities where slug = 'seed-smash-arena');
  ace uuid := (select id from facilities where slug = 'seed-ace-pickle-club');
  arun_champz uuid := gen_random_uuid();
  arun_smash uuid := gen_random_uuid();
  meena_ace uuid := gen_random_uuid();
  prog uuid;
  court uuid;
  start_a timestamptz := (((now() at time zone 'Asia/Kolkata')::date + 1) + time '18:00') at time zone 'Asia/Kolkata';
  start_b timestamptz := (((now() at time zone 'Asia/Kolkata')::date + 2) + time '07:00') at time zone 'Asia/Kolkata';
  start_c timestamptz := (((now() at time zone 'Asia/Kolkata')::date + 3) + time '20:00') at time zone 'Asia/Kolkata';
begin
  -- Arun: a membership at Champz, coaching at Smash
  insert into members (id, facility_id, full_name, phone, email) values (arun_champz, champz, 'Arun Test', '9000000001', 'arun.test@seed.gameall.test');
  insert into members (id, facility_id, full_name, phone, email) values (arun_smash, smash, 'Arun Test', '+91 90000 00001', 'arun.test@seed.gameall.test');
  insert into memberships (facility_id, member_id, status, start_date, end_date, name, membership_type, duration_days, membership_fee_inr, registration_fee_inr, total_amount_inr, monthly_price_inr)
  values (champz, arun_champz, 'active', current_date - 10, current_date + 20, 'Monthly Unlimited', 'INDIVIDUAL', 30, 2999, 0, 2999, 2999);
  -- Arun plays in Champz's first early-morning slot, so that slot shows "1 member plays here"
  insert into membership_batch_members (batch_id, member_id, membership_id)
  select b.id, arun_champz, m.id from membership_batches b, memberships m
   where b.facility_id = champz and m.member_id = arun_champz order by b.start_time, b.name limit 1;
  select id into prog from coaching_programs where facility_id = smash and name = 'Beginner Badminton';
  insert into coaching_enrollments (facility_id, member_id, program_id, start_date, end_date, price_minor)
  values (smash, arun_smash, prog, current_date - 5, current_date + 55, 120000);

  -- Meena: a membership at Ace Pickle Club
  insert into members (id, facility_id, full_name, phone, email) values (meena_ace, ace, 'Meena Test', '9000000002', 'meena.test@seed.gameall.test');
  insert into memberships (facility_id, member_id, status, start_date, end_date, name, membership_type, duration_days, membership_fee_inr, registration_fee_inr, total_amount_inr, monthly_price_inr)
  values (ace, meena_ace, 'active', current_date - 3, current_date + 27, 'Club Member', 'INDIVIDUAL', 30, 2499, 0, 2499, 2499);

  -- guest bookings (the phone typed on the booking is what links them to the player)
  select id into court from courts where facility_id = champz and name = 'Court 1';
  insert into bookings (facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status, amount_minor)
  values (champz, court, 'GUEST', 'Arun Test', '9000000001', start_a, start_a + interval '1 hour', 'confirmed', 40000);
  select id into court from courts where facility_id = smash and name = 'Court 2';
  insert into bookings (facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status, amount_minor)
  values (smash, court, 'GUEST', 'Arun Test', '+91 9000000001', start_b, start_b + interval '1 hour', 'confirmed', 45000);
  -- Ravi: a guest booking and nothing else
  select id into court from courts where facility_id = champz and name = 'Court 3';
  insert into bookings (facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status, amount_minor)
  values (champz, court, 'GUEST', 'Ravi Test', '9000000003', start_c, start_c + interval '1 hour', 'confirmed', 40000);
end
$players$;

-- A quick look at what was loaded:
select f.name, f.city, f.venue_type, f.location_verification_status as map_status,
       (select count(*) from courts c where c.facility_id = f.id) as courts,
       (select count(*) from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED') as approved_photos,
       (select count(*) from membership_plans p where p.facility_id = f.id) as plans,
       (select count(*) from coaching_programs p where p.facility_id = f.id) as programs
  from facilities f where f.slug like 'seed-%' order by f.city, f.name;
