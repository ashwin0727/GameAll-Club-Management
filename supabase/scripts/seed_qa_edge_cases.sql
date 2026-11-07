-- ═══════════════════════════════════════════════════════════════════════════
-- QA EDGE-CASE DATASET — venues, memberships, coaching and player payment states built to BREAK the Player app and the Club app.
--
-- NOT a migration. Run by hand in the Supabase SQL editor (ideally in a TEST project / Razorpay test mode).
-- Companion files in this folder:   verify_qa_edge_cases.sql  (check the numbers)   cleanup_qa_edge_cases.sql  (remove everything)
-- The test plan that says WHAT to look at for each venue is docs/qa/PLAYER_APP_QA_TEST_PLAN.md.
--
-- HOW TO RUN
--   1. Edit the three settings just below (owner e-mail, your test player's phone, load venues on/off).
--   2. Run the WHOLE file once. A second run adds no venues again (it stops when qa-… venues exist; to rebuild, run the cleanup first), but it
--      CAN add the test player's payment states if you set v_player_phone after the first run.
--   3. Run verify_qa_edge_cases.sql.
--
-- SAFETY
--   • Everything it adds is named "QA …" (slugs "qa-…") and every id is written to qa_seed_log, so cleanup removes exactly that.
--   • Each venue is built in its own sub-block: if one fails you get a NOTICE and the rest still go in.
--   • It never touches a venue or member that is not QA-marked.
--   • Needs migrations through 0179 for the Player pages to show everything (0178 / 0179 are optional fallbacks, see the plan).
--
-- WHAT YOU GET (see the test plan for the full matrix)
--   25 hand-built venues:  multi-sport, single court, very long names, unicode / emoji, 24-hour, after-midnight hours, closed Sundays,
--                          premium and budget prices, no photos, no amenities, inactive, half-onboarded, no bookable court,
--                          court under maintenance, fully booked tomorrow, plans that are full, plans of odd lengths, free plans,
--                          every coaching shape (monthly / one-time / trial / one-to-one, no coach, no batches, expired, discounted …)
--   2 venues in Chennai (city switching)   +   60 "QA Load" venues in Bangalore (list performance; switch off with v_load below)
--   If you give your test player's phone: that player gets paid / unpaid / failed / part-paid / AutoPay-halted memberships and guest
--   bookings, so the Home payment prompts and "Payment Incomplete" tags can be checked with real states.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists qa_seed_log (tbl text not null, id uuid not null, created_at timestamptz not null default now());

-- ───────────────────────── helper functions (live only for this session) ─────────────────────────

-- A venue with its hours. Returns the facility id (an existing QA venue with the same slug is returned unchanged).
create or replace function pg_temp.qa_venue(
  p_owner uuid, p_slug text, p_name text, p_city text, p_state text, p_area text,
  p_vtype text,          -- INDOOR | OUTDOOR | null (owner never said)
  p_amen text,           -- letters: P parking, C changing rooms, T toilets, F cafeteria, E equipment rental ('' = none)
  p_status text,         -- ACTIVE | INACTIVE
  p_step text,           -- onboarding step; COMPLETED = open for players
  p_desc text, p_hero text, p_photos text[],
  p_hours text           -- STD (6-22 daily) | 24H | LATE (18:00-02:00, closed Sunday) | SPLIT (6-10 and 16-22) | NONE (no hours set)
) returns uuid language plpgsql as $f$
declare v uuid; s uuid; d uuid; dd int; ph text; n int := 0;
begin
  select id into v from facilities where slug = p_slug;
  if v is not null then return v; end if;

  insert into facilities (name, slug, owner_id, facility_type, business_email, business_phone, address_line_1, area, city, state, country,
                          postal_code, timezone, description, onboarding_step, onboarding_completed_at, status, hero_image_url, venue_type,
                          has_parking, has_changing_rooms, has_toilets, has_cafeteria, has_equipment_rental)
  values (p_name, p_slug, p_owner, 'MULTI_SPORT', 'qa@example.invalid', '9000000000', '1 QA Street', coalesce(p_area, ''), p_city, coalesce(p_state, ''), 'India',
          '560001', 'Asia/Kolkata', p_desc, p_step::onboarding_step, case when p_step = 'COMPLETED' then now() end, p_status::entity_status,
          p_hero, p_vtype, position('P' in p_amen) > 0, position('C' in p_amen) > 0, position('T' in p_amen) > 0,
          position('F' in p_amen) > 0, position('E' in p_amen) > 0)
  returning id into v;
  insert into qa_seed_log values ('facilities', v);
  insert into facility_users (facility_id, user_id, role) values (v, p_owner, 'owner') on conflict do nothing;

  if p_photos is not null then
    foreach ph in array p_photos loop
      insert into facility_images (facility_id, url, sort_order, verification_status, verified_at) values (v, ph, n, 'VERIFIED', now());
      n := n + 1;
    end loop;
  end if;

  if p_hours <> 'NONE' then
    begin
      insert into operating_schedules (facility_id, scope_type, timezone) values (v, 'FACILITY', 'Asia/Kolkata') returning id into s;
      for dd in 0..6 loop
        if p_hours = 'LATE' and dd = 0 then
          insert into operating_days (schedule_id, facility_id, day_of_week, is_closed, is_24_hours) values (s, v, dd, true, false);
        elsif p_hours = '24H' then
          insert into operating_days (schedule_id, facility_id, day_of_week, is_closed, is_24_hours) values (s, v, dd, false, true);
        else
          insert into operating_days (schedule_id, facility_id, day_of_week, is_closed, is_24_hours) values (s, v, dd, false, false) returning id into d;
          if p_hours = 'LATE' then
            insert into operating_time_slots (operating_day_id, facility_id, start_time, end_time, crosses_midnight, display_order) values (d, v, '18:00', '02:00', true, 0);
          elsif p_hours = 'SPLIT' then
            insert into operating_time_slots (operating_day_id, facility_id, start_time, end_time, crosses_midnight, display_order) values (d, v, '06:00', '10:00', false, 0), (d, v, '16:00', '22:00', false, 1);
          else
            insert into operating_time_slots (operating_day_id, facility_id, start_time, end_time, crosses_midnight, display_order) values (d, v, '06:00', '22:00', false, 0);
          end if;
        end if;
      end loop;
    exception when others then raise notice 'hours for % skipped: %', p_slug, sqlerrm; end;
  end if;
  return v;
end $f$;

-- A court (creates the venue's sport when needed; sport_key 'other' + p_custom gives Padel, Basketball, Squash …).
create or replace function pg_temp.qa_court(
  p_fac uuid, p_sport_key text, p_custom text, p_name text, p_rate int, p_area text, p_surface text,
  p_status text default 'ACTIVE', p_enabled boolean default true, p_archived boolean default false
) returns uuid language plpgsql as $f$
declare sp uuid; fs uuid; c uuid;
begin
  select id into sp from sports where key = p_sport_key;
  if sp is null then raise exception 'sport % missing', p_sport_key; end if;
  insert into facility_sports (facility_id, sport_id, custom_sport_name) values (p_fac, sp, p_custom)
  on conflict (facility_id, sport_id) do update set is_active = true, custom_sport_name = coalesce(excluded.custom_sport_name, facility_sports.custom_sport_name);
  select id into fs from facility_sports where facility_id = p_fac and sport_id = sp;
  insert into courts (facility_id, facility_sport_id, sport_id, name, surface, hourly_rate_inr, area_type, display_order, status, booking_enabled, archived)
  values (p_fac, fs, sp, p_name, p_surface, p_rate, p_area::area_type, 1 + (select count(*) from courts where facility_id = p_fac), p_status::entity_status, p_enabled, p_archived)
  returning id into c;
  insert into qa_seed_log values ('courts', c);
  return c;
end $f$;

-- facility_sports.id of a venue's sport
create or replace function pg_temp.qa_fs(p_fac uuid, p_sport_key text) returns uuid language sql as
$f$ select fs.id from facility_sports fs join sports s on s.id = fs.sport_id where fs.facility_id = p_fac and s.key = p_sport_key $f$;

-- A membership plan
create or replace function pg_temp.qa_plan(p_fac uuid, p_name text, p_price int, p_days int, p_type text default 'TIME_BASED',
                                           p_active boolean default true, p_features text[] default array['Court access'])
returns uuid language plpgsql as $f$
declare pid uuid;
begin
  insert into membership_plans (facility_id, name, price_inr, duration_days, features, is_active, plan_type)
  values (p_fac, p_name, p_price, p_days, p_features, p_active, p_type::membership_plan_type)
  on conflict (facility_id, name) do update set price_inr = excluded.price_inr, duration_days = excluded.duration_days, is_active = excluded.is_active
  returning id into pid;
  insert into qa_seed_log values ('membership_plans', pid);
  return pid;
end $f$;

-- A membership batch (time slot) of a plan on a court
create or replace function pg_temp.qa_batch(p_fac uuid, p_plan uuid, p_fs uuid, p_court uuid, p_name text, p_dow smallint[], p_st time, p_et time,
                                            p_cap int, p_status text default 'ACTIVE')
returns uuid language plpgsql as $f$
declare bid uuid;
begin
  insert into membership_batches (facility_id, plan_id, facility_sport_id, court_id, name, days_of_week, start_time, end_time, capacity, status, start_date)
  values (p_fac, p_plan, p_fs, p_court, p_name, p_dow, p_st, p_et, p_cap, p_status, current_date - 30)
  returning id into bid;
  insert into qa_seed_log values ('membership_batches', bid);
  return bid;
end $f$;

-- A coach (a login-less staff user, with the owner as fallback when the project forbids adding auth users)
create or replace function pg_temp.qa_coach(p_fac uuid, p_owner uuid, p_slug text, p_name text, p_cert text, p_spec text, p_years numeric,
                                            p_rating numeric, p_avatar text, p_fs uuid)
returns uuid language plpgsql as $f$
declare u uuid; c uuid; v_email text := 'coach.qa.' || p_slug || '@example.invalid';
begin
  select id into u from auth.users where auth.users.email = v_email;
  if u is null then
    begin
      u := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                              created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
      values ('00000000-0000-0000-0000-000000000000', u, 'authenticated', 'authenticated', v_email, '', now(),
              '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', p_name), now(), now(), '', '', '', '');
      insert into profiles (id, full_name, email, role, avatar_url) values (u, p_name, v_email, 'member', p_avatar)
      on conflict (id) do update set full_name = excluded.full_name, avatar_url = excluded.avatar_url;
      insert into qa_seed_log values ('auth_users', u);
    exception when others then
      raise notice 'could not add auth user for %, the owner coaches instead: %', p_name, sqlerrm;
      u := p_owner;
    end;
  end if;
  insert into coaches (facility_id, user_id, specialization, certifications, experience_years, hourly_rate_minor, status, joined_on, rating, created_by)
  values (p_fac, u, p_spec, p_cert, p_years, 80000, 'ACTIVE', current_date - 365, p_rating, p_owner)
  on conflict (facility_id, user_id) do update set specialization = excluded.specialization, certifications = excluded.certifications,
        experience_years = excluded.experience_years, rating = excluded.rating, status = 'ACTIVE'
  returning id into c;
  insert into qa_seed_log values ('coaches', c);
  insert into coach_sports (coach_id, facility_id, facility_sport_id) values (c, p_fac, p_fs) on conflict do nothing;
  return c;
end $f$;

-- A coaching programme. p_created_ago lets "the latest programme per sport" be tested (older ones must lose).
create or replace function pg_temp.qa_program(
  p_fac uuid, p_owner uuid, p_fs uuid, p_name text, p_level text, p_descr text, p_price_minor int, p_fee text, p_type text,
  p_start_off int, p_end_off int, p_cap int, p_disc_minor int default 0, p_disc_till_off int default null,
  p_status text default 'ACTIVE', p_deadline_off int default null, p_created_ago interval default interval '0',
  p_payment_mode text default 'BOTH', p_age text default 'All Ages'
) returns uuid language plpgsql as $f$
declare pid uuid; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  insert into coaching_programs (facility_id, name, level, age_group, category, description, facility_sport_id, default_duration_minutes, default_capacity,
                                 default_price_minor, status, created_by, program_type, start_date, end_date, payment_mode, fee_type, sessions_per_week,
                                 program_structure, early_bird_discount_minor, discount_valid_till, is_membership_included, enrollment_deadline, created_at)
  values (p_fac, p_name, p_level, p_age, 'Coaching', p_descr, p_fs, 60, p_cap, p_price_minor, p_status, p_owner, p_type,
          today + p_start_off, case when p_end_off is null then null else today + p_end_off end, p_payment_mode, p_fee, 3,
          array['Basic Techniques','Fitness'], p_disc_minor, case when p_disc_till_off is null then null else today + p_disc_till_off end, false,
          case when p_deadline_off is null then null else today + p_deadline_off end, now() - p_created_ago)
  on conflict (facility_id, lower(name)) do update set level = excluded.level, default_price_minor = excluded.default_price_minor,
        status = excluded.status, created_at = excluded.created_at
  returning id into pid;
  insert into qa_seed_log values ('coaching_programs', pid);
  return pid;
end $f$;

create or replace function pg_temp.qa_cbatch(p_fac uuid, p_owner uuid, p_prog uuid, p_court uuid, p_coach uuid, p_name text, p_dow smallint[],
                                             p_st time, p_et time, p_cap int, p_status text default 'ACTIVE')
returns uuid language plpgsql as $f$
declare bid uuid;
begin
  insert into coaching_program_batches (facility_id, program_id, court_id, coach_id, name, days_of_week, start_time, end_time, capacity, status, created_by)
  values (p_fac, p_prog, p_court, p_coach, p_name, p_dow, p_st, p_et, p_cap, p_status, p_owner)
  returning id into bid;
  insert into qa_seed_log values ('coaching_program_batches', bid);
  return bid;
end $f$;

-- ═══════════════════════════════════════════════════════════════════════════
-- THE DATA
-- ═══════════════════════════════════════════════════════════════════════════
do $seed$
declare
  -- ── SETTINGS ───────────────────────────────────────────────────────────
  v_owner_email  text    := 'umashankarjul26@gmail.com';  -- ← the club account that will own the QA venues (must already exist)
  v_player_phone text    := '';                      -- ← your TEST PLAYER's phone, 10 digits (e.g. '9876543210'). '' = skip the player's payment states
  v_load         boolean := true;                    -- ← 60 extra venues for list performance. false = skip

  v_owner uuid;
  v_exists boolean;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  img_wood  constant text := 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/39/Outdoor_pickleball_courts.jpg/1280px-Outdoor_pickleball_courts.jpg';
  img_a     constant text := 'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=1200';
  img_b     constant text := 'https://images.unsplash.com/photo-1554068865-24cecd4e34b8?w=1200';
  img_c     constant text := 'https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=1200';
  img_broken constant text := 'https://example.invalid/this-image-does-not-exist.jpg';   -- a hero that fails to load → the placeholder scene must show
  -- venue / court / plan / program ids
  v1 uuid; v2 uuid; v3 uuid; v4 uuid; v5 uuid; v6 uuid; v7 uuid; v8 uuid; v9 uuid; v10 uuid; v11 uuid; v12 uuid; v13 uuid; v14 uuid; v15 uuid;
  v16 uuid; v17 uuid; v18 uuid; v19 uuid; v20 uuid; v21 uuid; v22 uuid; v23 uuid; v24 uuid; v25 uuid; vq uuid;
  c1 uuid; c2 uuid; c3 uuid; c4 uuid; c5 uuid; c6 uuid; c7 uuid; c8 uuid;
  fs_bad uuid; fs_pkl uuid; fs_crk uuid; fs_ftb uuid; fs_ten uuid; fs_oth uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid; p6 uuid; p7 uuid; p8 uuid; p9 uuid;
  k1 uuid; k2 uuid; k3 uuid; k4 uuid; k5 uuid; k6 uuid;
  pr1 uuid; pr2 uuid; pr3 uuid;
  i int; n int;
begin
  select id into v_owner from profiles where lower(email) = lower(v_owner_email);
  if v_owner is null then raise exception 'No profile with e-mail %. Sign up that account first (or change v_owner_email).', v_owner_email; end if;

  -- A second run must not add the venues again (courts, plans and bookings are not de-duplicated): it stops here and only the test
  -- player's payment states below can still be added. To rebuild everything, run cleanup_qa_edge_cases.sql first.
  v_exists := exists (select 1 from facilities where slug like 'qa-%');

  <<venues>>
  begin
  if v_exists then
    raise notice 'QA venues already exist: not adding them again (run cleanup_qa_edge_cases.sql first for a fresh set).';
    exit venues;
  end if;

  -- ══ V01 · QA Multi-Sport Arena ════════════════════════════════════════
  -- Six sports, many courts, three verified photos, every amenity, memberships AND coaching in several sports.
  -- Tests: sport chips (6), sport picker on the Memberships / Coaching cards, "latest programme per sport", Venues + Memberships + Coaching lists.
  begin
    v1 := pg_temp.qa_venue(v_owner, 'qa-multi-sport-arena', 'QA Multi-Sport Arena', 'Bangalore', 'Karnataka', 'Indiranagar', 'INDOOR', 'PCTFE', 'ACTIVE', 'COMPLETED',
          'Six sports under one roof: badminton, pickleball, cricket nets, five-a-side football, tennis and padel. Glass-walled padel courts, rental kits and weekend leagues.',
          img_a, array[img_a, img_b, img_c], 'STD');
    c1 := pg_temp.qa_court(v1, 'badminton', null, 'Badminton Court 1', 400, 'INDOOR', 'Wooden');
    c2 := pg_temp.qa_court(v1, 'badminton', null, 'Badminton Court 2', 450, 'INDOOR', 'Synthetic');
    c3 := pg_temp.qa_court(v1, 'pickleball', null, 'Pickleball Court 1', 600, 'INDOOR', 'Acrylic');
    c4 := pg_temp.qa_court(v1, 'cricket', null, 'Cricket Nets', 900, 'OUTDOOR', 'Turf');
    c5 := pg_temp.qa_court(v1, 'football', null, 'Five-a-side Pitch', 1400, 'OUTDOOR', 'Artificial turf');
    c6 := pg_temp.qa_court(v1, 'tennis', null, 'Tennis Court 1', 700, 'OUTDOOR', 'Clay');
    c7 := pg_temp.qa_court(v1, 'other', 'Padel', 'Padel Court 1', 1200, 'INDOOR', 'Glass-walled');
    fs_bad := pg_temp.qa_fs(v1, 'badminton'); fs_pkl := pg_temp.qa_fs(v1, 'pickleball'); fs_crk := pg_temp.qa_fs(v1, 'cricket');
    fs_ftb := pg_temp.qa_fs(v1, 'football');  fs_ten := pg_temp.qa_fs(v1, 'tennis');     fs_oth := pg_temp.qa_fs(v1, 'other');
    -- plans differ by sport (a plan belongs to a sport through its batches)
    p1 := pg_temp.qa_plan(v1, 'Badminton Monthly', 1500, 30, 'RECURRING');
    p2 := pg_temp.qa_plan(v1, 'Badminton Quarterly', 4000, 90);
    p3 := pg_temp.qa_plan(v1, 'Badminton Yearly', 12000, 365);
    p4 := pg_temp.qa_plan(v1, 'Padel Monthly', 3200, 30, 'RECURRING');
    p5 := pg_temp.qa_plan(v1, 'Padel Half-Year', 17000, 180);
    p6 := pg_temp.qa_plan(v1, 'Football Monthly', 2800, 30, 'RECURRING');
    p7 := pg_temp.qa_plan(v1, 'Football Quarterly', 7500, 90);
    p8 := pg_temp.qa_plan(v1, 'Pickleball Monthly', 1800, 30, 'RECURRING');
    p9 := pg_temp.qa_plan(v1, 'Tennis Monthly', 2000, 30, 'RECURRING');
    perform pg_temp.qa_batch(v1, p1, fs_bad, c1, 'Badminton Morning', array[1,2,3,4,5,6]::smallint[], '06:00', '07:00', 20);
    perform pg_temp.qa_batch(v1, p2, fs_bad, c1, 'Badminton Morning', array[1,2,3,4,5,6]::smallint[], '06:00', '07:00', 20);
    perform pg_temp.qa_batch(v1, p3, fs_bad, c2, 'Badminton Evening', array[1,2,3,4,5,6]::smallint[], '18:00', '19:00', 20);
    perform pg_temp.qa_batch(v1, p1, fs_bad, c2, 'Badminton Evening', array[1,2,3,4,5,6]::smallint[], '18:00', '19:00', 20);
    perform pg_temp.qa_batch(v1, p4, fs_oth, c7, 'Padel Evening', array[1,3,5]::smallint[], '19:00', '20:00', 8);
    perform pg_temp.qa_batch(v1, p5, fs_oth, c7, 'Padel Evening', array[1,3,5]::smallint[], '19:00', '20:00', 8);
    perform pg_temp.qa_batch(v1, p6, fs_ftb, c5, 'Football Weekend', array[0,6]::smallint[], '07:00', '09:00', 14);
    perform pg_temp.qa_batch(v1, p7, fs_ftb, c5, 'Football Weekend', array[0,6]::smallint[], '07:00', '09:00', 14);
    perform pg_temp.qa_batch(v1, p8, fs_pkl, c3, 'Pickleball Evening', array[1,2,3,4,5]::smallint[], '19:00', '20:00', 12);
    perform pg_temp.qa_batch(v1, p9, fs_ten, c6, 'Tennis Morning', array[2,4,6]::smallint[], '06:30', '07:30', 6);
    -- coaches: full detail / no photo and no rating / very long certification text
    k1 := pg_temp.qa_coach(v1, v_owner, 'arjun', 'Arjun', 'BWF Level 1 Certified', 'Badminton — beginners', 8, 4.9, 'https://i.pravatar.cc/200?img=12', fs_bad);
    k2 := pg_temp.qa_coach(v1, v_owner, 'meera', 'Meera', 'ITF Level 2 Certified Tennis Coach', 'Tennis — all levels', 6.5, 4.8, null, fs_ten);
    k3 := pg_temp.qa_coach(v1, v_owner, 'diego', 'Diego Hernández-Villalobos', 'International Padel Federation Level 3 Coach · Former World Tour Player (Spain) · Certified Sports Nutritionist · First-Aid and CPR Instructor', 'Padel — advanced', 12, null, null, fs_oth);
    -- programmes: an OLD Badminton Advanced and a NEWER Beginner (the card must show the newer one), plus Tennis, Padel, Football
    pr1 := pg_temp.qa_program(v1, v_owner, fs_bad, 'Badminton Advanced Squad', 'Advanced', 'Older programme: must LOSE to the newer Beginner one on the Coaching list.', 499900, 'ONE_TIME', 'GROUP', 0, 60, 4, 0, null, 'ACTIVE', null, interval '90 days');
    pr2 := pg_temp.qa_program(v1, v_owner, fs_bad, 'Badminton Beginner Program', 'Beginner', 'Build a strong foundation with proper technique, footwork and game basics.', 299900, 'MONTHLY', 'GROUP', 0, 89, 8, 0, null, 'ACTIVE', null, interval '10 days');
    pr3 := pg_temp.qa_program(v1, v_owner, fs_ten, 'Tennis Starters', 'Intermediate', 'Weekend tennis for improving players.', 350000, 'MONTHLY', 'GROUP', 0, 89, 6, 0, null, 'ACTIVE', null, interval '5 days');
    perform pg_temp.qa_cbatch(v1, v_owner, pr1, c1, k1, 'Advanced Evening', array[2,4,6]::smallint[], '20:00', '21:00', 4);
    perform pg_temp.qa_cbatch(v1, v_owner, pr2, c1, k1, 'Beginner Evening', array[1,3,5]::smallint[], '18:00', '19:00', 8);
    perform pg_temp.qa_cbatch(v1, v_owner, pr2, c1, k1, 'Beginner Early Morning', array[2,4,6]::smallint[], '06:00', '07:00', 8);
    perform pg_temp.qa_cbatch(v1, v_owner, pr3, c6, k2, 'Tennis Weekend', array[6,0]::smallint[], '08:00', '09:00', 6);
    pr1 := pg_temp.qa_program(v1, v_owner, fs_oth, 'Padel Pro Clinic', 'Advanced', 'One-to-one padel with a former tour player.', 2500000, 'ONE_TIME', 'ONE_ON_ONE', 0, 30, 1, 0, null, 'ACTIVE', null, interval '2 days');
    perform pg_temp.qa_cbatch(v1, v_owner, pr1, c7, k3, 'Padel One-to-one', array[1,3]::smallint[], '17:00', '18:00', 1);
    pr1 := pg_temp.qa_program(v1, v_owner, fs_ftb, 'Football Juniors', 'Beginner', null, 120000, 'MONTHLY', 'GROUP', 0, 89, 16, 0, null, 'ACTIVE', null, interval '1 day');   -- no description
    perform pg_temp.qa_cbatch(v1, v_owner, pr1, c5, null, 'Juniors Saturday', array[6]::smallint[], '16:00', '17:00', 16);   -- a batch with NO coach
  exception when others then raise notice 'V01 failed: %', sqlerrm; end;

  -- ══ V02 · QA Single Court Studio ═══════════════════════════════════════
  -- One sport, one court, one plan, no photos, owner never said indoor/outdoor, no amenities.
  -- Tests: no sport chips, one price tile, placeholder scene, no type badge, "no amenities" blocks.
  begin
    v2 := pg_temp.qa_venue(v_owner, 'qa-single-court-studio', 'QA Single Court Studio', 'Bangalore', 'Karnataka', 'HSR Layout', null, '', 'ACTIVE', 'COMPLETED',
          null, null, null, 'STD');
    c1 := pg_temp.qa_court(v2, 'badminton', null, 'The Only Court', 350, 'INDOOR', null);
    fs_bad := pg_temp.qa_fs(v2, 'badminton');
    p1 := pg_temp.qa_plan(v2, 'Monthly Pass', 1200, 30);
    perform pg_temp.qa_batch(v2, p1, fs_bad, c1, 'Evening', array[1,2,3,4,5]::smallint[], '18:00', '19:00', 6);
  exception when others then raise notice 'V02 failed: %', sqlerrm; end;

  -- ══ V03 · very long names (truncation everywhere) ═══════════════════════
  begin
    v3 := pg_temp.qa_venue(v_owner, 'qa-long-name', 'QA Extraordinarily Long Venue Name Sports Complex And Recreation Centre Of Greater Whitefield Main Road Opposite The Big Mall',
          'Bangalore', 'Karnataka', 'Whitefield Extension Phase Three Beyond The Flyover', 'INDOOR', 'PCTFE', 'ACTIVE', 'COMPLETED',
          'A description that goes on and on to check wrapping on the venue page and the Guest Booking page: ' || repeat('this venue has everything a player could want. ', 12),
          img_b, array[img_b], 'STD');
    c1 := pg_temp.qa_court(v3, 'badminton', null, 'Championship Court With An Unreasonably Long Name Number One', 500, 'INDOOR', 'Wooden');
    fs_bad := pg_temp.qa_fs(v3, 'badminton');
    p1 := pg_temp.qa_plan(v3, 'The Ultimate All-Access Annual Premium Platinum Membership For Serious Players', 18000, 365);
    perform pg_temp.qa_batch(v3, p1, fs_bad, c1, 'Early Bird Batch For The Very Dedicated', array[1,2,3,4,5]::smallint[], '06:00', '07:00', 10);
    k1 := pg_temp.qa_coach(v3, v_owner, 'longname', 'Subramaniam Venkataraghavan Ramanathan Iyer', 'Level 2', 'Everything', 15, 4.5, null, fs_bad);
    pr1 := pg_temp.qa_program(v3, v_owner, fs_bad, 'Advanced Competitive Tournament Preparation And Performance Optimisation Programme', 'Advanced',
          'An unreasonably long description. ' || repeat('Footwork, smashes, drops, clears, net play, match strategy, fitness, recovery. ', 8), 899900, 'MONTHLY', 'GROUP', 0, 120, 10, 0, null);
    perform pg_temp.qa_cbatch(v3, v_owner, pr1, c1, k1, 'Evening', array[1,3,5]::smallint[], '19:00', '20:00', 10);
  exception when others then raise notice 'V03 failed: %', sqlerrm; end;

  -- ══ V04 · unicode, emoji, quotes, HTML-looking text ════════════════════
  begin
    v4 := pg_temp.qa_venue(v_owner, 'qa-unicode', 'QA Café & Co. — “Ñandú” Courts 🏸', 'Bangalore', 'Karnataka', 'Koramangala 5th Block', 'OUTDOOR', 'PT', 'ACTIVE', 'COMPLETED',
          'Quotes "double" and ''single'', <b>not bold</b>, <script>alert(1)</script>, 100% & more, ₹ symbols, தமிழ், हिन्दी, ಕನ್ನಡ, 日本語, العربية 🏸⚽🏏',
          img_c, array[img_c], 'STD');
    c1 := pg_temp.qa_court(v4, 'badminton', null, 'Court “A” — Ñ', 400, 'OUTDOOR', 'Wooden');
    c2 := pg_temp.qa_court(v4, 'tennis', null, 'Court <B> & C', 650, 'OUTDOOR', 'Hard');
    fs_bad := pg_temp.qa_fs(v4, 'badminton');
    p1 := pg_temp.qa_plan(v4, 'Monthly — ₹ “Special” & 50% off 🎉', 1000, 30);
    perform pg_temp.qa_batch(v4, p1, fs_bad, c1, 'Batch <1>', array[1,2,3,4,5]::smallint[], '17:00', '18:00', 8);
  exception when others then raise notice 'V04 failed: %', sqlerrm; end;

  -- ══ V05 · 24-hour outdoor turf, no memberships, no coaching ════════════
  begin
    v5 := pg_temp.qa_venue(v_owner, 'qa-24x7-turf', 'QA 24x7 Turf', 'Bangalore', 'Karnataka', 'Electronic City', 'OUTDOOR', 'PT', 'ACTIVE', 'COMPLETED',
          'Open round the clock under floodlights.', img_a, array[img_a, img_c], '24H');
    c1 := pg_temp.qa_court(v5, 'football', null, 'Turf 1', 1500, 'OUTDOOR', 'Artificial turf');
    c2 := pg_temp.qa_court(v5, 'football', null, 'Turf 2', 1500, 'OUTDOOR', 'Artificial turf');
  exception when others then raise notice 'V05 failed: %', sqlerrm; end;

  -- ══ V06 · premium prices (Indian digit grouping) ═══════════════════════
  begin
    v6 := pg_temp.qa_venue(v_owner, 'qa-premium-club', 'QA Premium Padel Club', 'Bangalore', 'Karnataka', 'Sadashivanagar', 'INDOOR', 'PCTFE', 'ACTIVE', 'COMPLETED',
          'Members-first padel club.', img_b, array[img_b, img_a, img_c], 'STD');
    c1 := pg_temp.qa_court(v6, 'other', 'Padel', 'Centre Court', 12500, 'INDOOR', 'Glass-walled');
    fs_oth := pg_temp.qa_fs(v6, 'other');
    p1 := pg_temp.qa_plan(v6, 'Founding Member (Yearly)', 150000, 365);
    p2 := pg_temp.qa_plan(v6, 'Monthly', 24999, 30, 'RECURRING');
    perform pg_temp.qa_batch(v6, p1, fs_oth, c1, 'Prime Time', array[1,2,3,4,5]::smallint[], '19:00', '21:00', 4);
    perform pg_temp.qa_batch(v6, p2, fs_oth, c1, 'Prime Time', array[1,2,3,4,5]::smallint[], '19:00', '21:00', 4);
    k1 := pg_temp.qa_coach(v6, v_owner, 'luca', 'Luca', 'FIP Platinum Coach', 'Padel', 14, 5.0, 'https://i.pravatar.cc/200?img=33', fs_oth);
    pr1 := pg_temp.qa_program(v6, v_owner, fs_oth, 'Private Padel Masterclass', 'Advanced', 'One-to-one coaching on the centre court.', 15000000, 'ONE_TIME', 'ONE_ON_ONE', 0, 30, 1);
    perform pg_temp.qa_cbatch(v6, v_owner, pr1, c1, k1, 'By appointment', array[6]::smallint[], '10:00', '11:00', 1);
  exception when others then raise notice 'V06 failed: %', sqlerrm; end;

  -- ══ V07 · budget prices and odd plan lengths ═══════════════════════════
  -- Tests: ₹50/hr; a 10-day pass and a 45-day plan (no tile: not Monthly / 3 / 6 / Yearly); a FREE plan; an inactive plan (must not show).
  begin
    v7 := pg_temp.qa_venue(v_owner, 'qa-budget-courts', 'QA Budget Courts', 'Bangalore', 'Karnataka', 'Yelahanka', 'OUTDOOR', '', 'ACTIVE', 'COMPLETED',
          'Low-cost courts.', null, null, 'STD');
    c1 := pg_temp.qa_court(v7, 'badminton', null, 'Court 1', 50, 'OUTDOOR', 'Cement');
    fs_bad := pg_temp.qa_fs(v7, 'badminton');
    p1 := pg_temp.qa_plan(v7, '10-Day Pass', 300, 10);
    p2 := pg_temp.qa_plan(v7, 'Free Trial Week', 0, 7);
    p3 := pg_temp.qa_plan(v7, '45-Day Special', 1500, 45);
    p4 := pg_temp.qa_plan(v7, 'Retired Plan', 999, 30, 'TIME_BASED', false);
    p5 := pg_temp.qa_plan(v7, 'Monthly Basic', 99, 30);
    for i in 1..5 loop
      perform pg_temp.qa_batch(v7, (array[p1,p2,p3,p4,p5])[i], fs_bad, c1, 'Batch ' || i, array[1,2,3,4,5]::smallint[], make_time(5 + i, 0, 0), make_time(6 + i, 0, 0), 10);
    end loop;
  exception when others then raise notice 'V07 failed: %', sqlerrm; end;

  -- ══ V08 · plans whose seats are FULL ═══════════════════════════════════
  -- One batch with capacity 1 and one member already in it: the Enroll Membership page must say the slot is full, not offer it.
  begin
    v8 := pg_temp.qa_venue(v_owner, 'qa-memberships-full', 'QA Memberships Full House', 'Bangalore', 'Karnataka', 'Jayanagar', 'INDOOR', 'PC', 'ACTIVE', 'COMPLETED',
          'Every membership slot here is taken.', img_a, array[img_a], 'STD');
    c1 := pg_temp.qa_court(v8, 'badminton', null, 'Court 1', 400, 'INDOOR', 'Wooden');
    fs_bad := pg_temp.qa_fs(v8, 'badminton');
    p1 := pg_temp.qa_plan(v8, 'Monthly', 1500, 30);
    declare b_full uuid; m_id uuid; ms_id uuid;
    begin
      b_full := pg_temp.qa_batch(v8, p1, fs_bad, c1, 'Evening (full)', array[1,2,3,4,5]::smallint[], '18:00', '19:00', 1);
      perform pg_temp.qa_batch(v8, p1, fs_bad, c1, 'Morning (3 seats free)', array[1,2,3,4,5]::smallint[], '06:00', '07:00', 3);
      insert into members (facility_id, full_name, phone, status) values (v8, 'QA Seat Holder', '7900000001', 'ACTIVE') returning id into m_id;
      insert into qa_seed_log values ('members', m_id);
      insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date, auto_renew, created_by, monthly_price_inr, name, membership_type,
                               duration_days, membership_fee_inr, registration_fee_inr, gst_percent, total_amount_inr)
      values (v8, m_id, p1, 'active', v_today - 5, v_today + 25, false, v_owner, 1500, 'Monthly', 'INDIVIDUAL', 30, 1500, 0, 0, 1500) returning id into ms_id;
      insert into qa_seed_log values ('memberships', ms_id);
      insert into payments (facility_id, member_id, membership_id, amount_inr, status, payment_method, paid_at)
      values (v8, m_id, ms_id, 1500, 'paid', 'UPI', now() - interval '5 days');
      alter table membership_batch_members disable trigger membership_batch_members_eligible;
      insert into membership_batch_members (batch_id, member_id, membership_id) values (b_full, m_id, ms_id);
      alter table membership_batch_members enable trigger membership_batch_members_eligible;
    end;
  exception when others then raise notice 'V08 failed: %', sqlerrm; end;

  -- ══ V09 · coaching showcase: every programme shape ═════════════════════
  -- The Coaching list shows only the LATEST active programme per sport, so each shape sits at its own venue-sport pair in V09–V12 and V01.
  -- V09 (Badminton): the latest programme is MONTHLY with an active early-bird discount and a coach with no photo / rating / years.
  begin
    v9 := pg_temp.qa_venue(v_owner, 'qa-coaching-showcase', 'QA Coaching Showcase', 'Bangalore', 'Karnataka', 'Marathahalli', 'INDOOR', 'PCT', 'ACTIVE', 'COMPLETED',
          'Coaching in every shape.', img_c, array[img_c, img_a], 'STD');
    c1 := pg_temp.qa_court(v9, 'badminton', null, 'Court 1', 400, 'INDOOR', 'Wooden');
    c2 := pg_temp.qa_court(v9, 'tennis', null, 'Tennis Court', 600, 'OUTDOOR', 'Hard');
    c3 := pg_temp.qa_court(v9, 'cricket', null, 'Nets', 800, 'OUTDOOR', 'Turf');
    c4 := pg_temp.qa_court(v9, 'football', null, 'Pitch', 1200, 'OUTDOOR', 'Turf');
    c5 := pg_temp.qa_court(v9, 'pickleball', null, 'Pickle 1', 500, 'INDOOR', 'Acrylic');
    fs_bad := pg_temp.qa_fs(v9, 'badminton'); fs_ten := pg_temp.qa_fs(v9, 'tennis'); fs_crk := pg_temp.qa_fs(v9, 'cricket');
    fs_ftb := pg_temp.qa_fs(v9, 'football');  fs_pkl := pg_temp.qa_fs(v9, 'pickleball');
    k1 := pg_temp.qa_coach(v9, v_owner, 'bare', 'Bare Bones', null, null, null, null, null, fs_bad);          -- nothing but a name
    k2 := pg_temp.qa_coach(v9, v_owner, 'newbie', 'Newbie', 'Foundation Course', null, 0.4, 3.0, null, fs_ten); -- under a year, low rating
    -- Badminton: monthly + early-bird still running (₹3,999 − ₹500)
    pr1 := pg_temp.qa_program(v9, v_owner, fs_bad, 'Early Bird Monthly', 'Beginner', 'A discount is running: the card must show the DISCOUNTED price.', 399900, 'MONTHLY', 'GROUP', 0, 89, 10, 50000, 14);
    perform pg_temp.qa_cbatch(v9, v_owner, pr1, c1, k1, 'Evening', array[1,3,5]::smallint[], '18:00', '19:00', 10);
    -- Tennis: early-bird EXPIRED (full price), enrolment deadline in the past (cannot enrol), coach <1 year
    pr2 := pg_temp.qa_program(v9, v_owner, fs_ten, 'Tennis Closed Enrolment', 'Intermediate', 'Early bird ended and the enrolment deadline has passed.', 450000, 'ONE_TIME', 'GROUP', -20, 40, 8, 50000, -5, 'ACTIVE', -2);
    perform pg_temp.qa_cbatch(v9, v_owner, pr2, c2, k2, 'Weekend', array[6,0]::smallint[], '09:00', '10:00', 8);
    -- Cricket: TRIAL class, free (price 0), no coach, no description
    pr3 := pg_temp.qa_program(v9, v_owner, fs_crk, 'Free Cricket Trial', 'All Levels', null, 0, 'ONE_TIME', 'TRIAL', 0, 14, 20);
    perform pg_temp.qa_cbatch(v9, v_owner, pr3, c3, null, 'Trial Sunday', array[0]::smallint[], '08:00', '09:00', 20);
    -- Football: programme with NO batches at all (no days, times or coach)
    perform pg_temp.qa_program(v9, v_owner, fs_ftb, 'Football Coming Soon', 'Beginner', 'Created but no batch yet.', 200000, 'MONTHLY', 'GROUP', 7, 97, 12);
    -- Pickleball: programme that has ENDED (must be hidden) — and a newer INACTIVE one (also hidden)
    perform pg_temp.qa_program(v9, v_owner, fs_pkl, 'Pickleball Ended Course', 'Beginner', 'Ended yesterday: must not show.', 100000, 'ONE_TIME', 'GROUP', -60, -1, 8);
    perform pg_temp.qa_program(v9, v_owner, fs_pkl, 'Pickleball Paused', 'Beginner', 'Inactive: must not show.', 100000, 'ONE_TIME', 'GROUP', 0, 30, 8, 0, null, 'INACTIVE');
  exception when others then raise notice 'V09 failed: %', sqlerrm; end;

  -- ══ V10 · INACTIVE venue (must appear NOWHERE) ═════════════════════════
  begin
    v10 := pg_temp.qa_venue(v_owner, 'qa-inactive-venue', 'QA Inactive Venue (must not show)', 'Bangalore', 'Karnataka', 'BTM', 'INDOOR', 'PC', 'INACTIVE', 'COMPLETED', null, img_a, array[img_a], 'STD');
    c1 := pg_temp.qa_court(v10, 'badminton', null, 'Court 1', 400, 'INDOOR', 'Wooden');
    fs_bad := pg_temp.qa_fs(v10, 'badminton');
    p1 := pg_temp.qa_plan(v10, 'Monthly', 1500, 30);
    perform pg_temp.qa_batch(v10, p1, fs_bad, c1, 'Evening', array[1,2,3]::smallint[], '18:00', '19:00', 8);
    pr1 := pg_temp.qa_program(v10, v_owner, fs_bad, 'Inactive Venue Coaching', 'Beginner', null, 100000, 'ONE_TIME', 'GROUP', 0, 30, 8);
    perform pg_temp.qa_cbatch(v10, v_owner, pr1, c1, null, 'Evening', array[1]::smallint[], '18:00', '19:00', 8);
  exception when others then raise notice 'V10 failed: %', sqlerrm; end;

  -- ══ V11 · onboarding NOT finished (must appear nowhere) ═════════════════
  begin
    v11 := pg_temp.qa_venue(v_owner, 'qa-onboarding-incomplete', 'QA Half Set Up (must not show)', 'Bangalore', 'Karnataka', 'Hebbal', 'INDOOR', '', 'ACTIVE', 'PRICING', null, null, null, 'STD');
    c1 := pg_temp.qa_court(v11, 'badminton', null, 'Court 1', 400, 'INDOOR', 'Wooden');
    p1 := pg_temp.qa_plan(v11, 'Monthly', 1500, 30);
  exception when others then raise notice 'V11 failed: %', sqlerrm; end;

  -- ══ V12 · no bookable court, but it HAS memberships ════════════════════
  -- Courts are archived / inactive / booking-disabled, so the venue is NOT in the Venues list, yet it IS in the Memberships list.
  begin
    v12 := pg_temp.qa_venue(v_owner, 'qa-no-bookable-court', 'QA No Bookable Court', 'Bangalore', 'Karnataka', 'Malleshwaram', 'INDOOR', 'P', 'ACTIVE', 'COMPLETED',
          'Courts closed for booking, memberships still sold.', img_b, array[img_b], 'STD');
    c1 := pg_temp.qa_court(v12, 'badminton', null, 'Archived Court', 400, 'INDOOR', 'Wooden', 'ACTIVE', true, true);
    c2 := pg_temp.qa_court(v12, 'badminton', null, 'Inactive Court', 400, 'INDOOR', 'Wooden', 'INACTIVE', true, false);
    c3 := pg_temp.qa_court(v12, 'badminton', null, 'Booking Disabled Court', 400, 'INDOOR', 'Wooden', 'ACTIVE', false, false);
    fs_bad := pg_temp.qa_fs(v12, 'badminton');
    p1 := pg_temp.qa_plan(v12, 'Monthly', 1400, 30);
    perform pg_temp.qa_batch(v12, p1, fs_bad, c3, 'Evening', array[1,2,3,4,5]::smallint[], '18:00', '19:00', 8);
  exception when others then raise notice 'V12 failed: %', sqlerrm; end;

  -- ══ V13 · court under maintenance ═══════════════════════════════════════
  -- Court 1 has an ACTIVE maintenance block for the next three days: Guest Booking must show NO slots for it; Court 2 is normal.
  begin
    v13 := pg_temp.qa_venue(v_owner, 'qa-maintenance', 'QA Maintenance Court', 'Bangalore', 'Karnataka', 'JP Nagar', 'INDOOR', 'PC', 'ACTIVE', 'COMPLETED', null, img_c, array[img_c], 'STD');
    c1 := pg_temp.qa_court(v13, 'badminton', null, 'Court 1 (under maintenance)', 400, 'INDOOR', 'Wooden');
    c2 := pg_temp.qa_court(v13, 'badminton', null, 'Court 2 (fine)', 400, 'INDOOR', 'Wooden');
    declare t uuid; cat uuid;
    begin
      select id into cat from maintenance_issue_categories where facility_id is null order by sort_order limit 1;
      insert into maintenance_tickets (facility_id, court_id, issue_category_id, title, description, priority, status, reported_by, scheduled_start, scheduled_end)
      values (v13, c1, cat, 'QA floor repair', 'Seeded by the QA dataset', 'HIGH', 'IN_PROGRESS', v_owner, now() - interval '1 hour', now() + interval '3 days') returning id into t;
      insert into qa_seed_log values ('maintenance_tickets', t);
      insert into maintenance_blocks (facility_id, court_id, ticket_id, start_time, end_time, status, created_by)
      values (v13, c1, t, now() - interval '1 hour', now() + interval '3 days', 'ACTIVE', v_owner);
    exception when others then raise notice 'V13 maintenance block skipped: %', sqlerrm; end;
  exception when others then raise notice 'V13 failed: %', sqlerrm; end;

  -- ══ V14 · fully booked TOMORROW ═════════════════════════════════════════
  -- A single court with a confirmed booking for every hour 06:00–22:00 tomorrow, and a few hours booked today and the day after.
  begin
    v14 := pg_temp.qa_venue(v_owner, 'qa-fully-booked', 'QA Fully Booked Tomorrow', 'Bangalore', 'Karnataka', 'Banashankari', 'INDOOR', 'P', 'ACTIVE', 'COMPLETED', null, img_a, array[img_a], 'STD');
    c1 := pg_temp.qa_court(v14, 'badminton', null, 'Only Court', 400, 'INDOOR', 'Wooden');
    insert into bookings (facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status, amount_minor, currency, payment_status, notes, party_size, created_by)
    select v14, c1, 'GUEST', 'QA Walk-in ' || h, '7900000' || lpad(h::text, 3, '0'),
           ((v_today + 1) + make_time(h, 0, 0)) at time zone 'Asia/Kolkata', ((v_today + 1) + make_time(h + 1, 0, 0)) at time zone 'Asia/Kolkata',
           'confirmed', 40000, 'INR', 'PAID', 'QA', 2, v_owner
    from generate_series(6, 21) h;
    insert into bookings (facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status, amount_minor, currency, payment_status, notes, party_size, created_by)
    select v14, c1, 'GUEST', 'QA Partial ' || h, '7900100' || lpad(h::text, 3, '0'),
           ((v_today + 2) + make_time(h, 0, 0)) at time zone 'Asia/Kolkata', ((v_today + 2) + make_time(h + 1, 0, 0)) at time zone 'Asia/Kolkata',
           'confirmed', 40000, 'INR', 'PAID', 'QA', 2, v_owner
    from unnest(array[7, 8, 18, 19, 20]) h;
    insert into qa_seed_log select 'bookings', id from bookings where facility_id = v14 and notes = 'QA';
  exception when others then raise notice 'V14 failed: %', sqlerrm; end;

  -- ══ V15 · after-midnight hours, closed Sundays ══════════════════════════
  begin
    v15 := pg_temp.qa_venue(v_owner, 'qa-late-night', 'QA Late Night Courts', 'Bangalore', 'Karnataka', 'Indiranagar', 'INDOOR', 'PT', 'ACTIVE', 'COMPLETED',
          'Open 6 PM to 2 AM, closed on Sundays.', img_b, array[img_b], 'LATE');
    c1 := pg_temp.qa_court(v15, 'badminton', null, 'Night Court', 450, 'INDOOR', 'Wooden');
  exception when others then raise notice 'V15 failed: %', sqlerrm; end;

  -- ══ V16 · split hours; V17 · no hours set at all ════════════════════════
  begin
    v16 := pg_temp.qa_venue(v_owner, 'qa-split-hours', 'QA Split Shift Courts', 'Bangalore', 'Karnataka', 'RT Nagar', 'INDOOR', 'P', 'ACTIVE', 'COMPLETED', null, img_c, array[img_c], 'SPLIT');
    c1 := pg_temp.qa_court(v16, 'badminton', null, 'Court 1', 400, 'INDOOR', 'Wooden');
    v17 := pg_temp.qa_venue(v_owner, 'qa-no-hours', 'QA No Hours Set', 'Bangalore', 'Karnataka', 'Basavanagudi', 'INDOOR', '', 'ACTIVE', 'COMPLETED', null, null, null, 'NONE');
    c2 := pg_temp.qa_court(v17, 'badminton', null, 'Court 1', 400, 'INDOOR', 'Wooden');
    p1 := pg_temp.qa_plan(v17, 'Monthly', 1300, 30);
    perform pg_temp.qa_batch(v17, p1, pg_temp.qa_fs(v17, 'badminton'), c2, 'Evening', array[1,2,3,4,5]::smallint[], '18:00', '19:00', 8);
  exception when others then raise notice 'V16/V17 failed: %', sqlerrm; end;

  -- ══ V18 · no amenities, owner left indoor/outdoor blank, broken hero image ═
  begin
    v18 := pg_temp.qa_venue(v_owner, 'qa-broken-image', 'QA Broken Hero Image', 'Bangalore', 'Karnataka', 'Rajajinagar', null, '', 'ACTIVE', 'COMPLETED', null, img_broken, array[img_broken], 'STD');
    c1 := pg_temp.qa_court(v18, 'cricket', null, 'Nets', 700, 'OUTDOOR', 'Turf');
  exception when others then raise notice 'V18 failed: %', sqlerrm; end;

  -- ══ V19 · court with NO price (rate 0) ═══════════════════════════════════
  begin
    v19 := pg_temp.qa_venue(v_owner, 'qa-no-price', 'QA Price Not Set', 'Bangalore', 'Karnataka', 'Ulsoor', 'INDOOR', '', 'ACTIVE', 'COMPLETED', null, img_a, array[img_a], 'STD');
    c1 := pg_temp.qa_court(v19, 'badminton', null, 'Court 1', 0, 'INDOOR', 'Wooden');
  exception when others then raise notice 'V19 failed: %', sqlerrm; end;

  -- ══ V20 · city spelling and state variants ═══════════════════════════════
  -- "Bengaluru" and "Bangalore" are the same city; state in other case; state missing.
  begin
    v20 := pg_temp.qa_venue(v_owner, 'qa-bengaluru-spelling', 'QA Bengaluru Spelling', 'Bengaluru', 'KARNATAKA', 'Yeshwanthpur', 'INDOOR', 'P', 'ACTIVE', 'COMPLETED', null, img_b, array[img_b], 'STD');
    c1 := pg_temp.qa_court(v20, 'badminton', null, 'Court 1', 400, 'INDOOR', 'Wooden');
    v21 := pg_temp.qa_venue(v_owner, 'qa-no-state', 'QA Missing State', 'Bangalore', '', 'Sarjapur', 'INDOOR', '', 'ACTIVE', 'COMPLETED', null, img_c, array[img_c], 'STD');
    c2 := pg_temp.qa_court(v21, 'badminton', null, 'Court 1', 400, 'INDOOR', 'Wooden');
  exception when others then raise notice 'V20/V21 failed: %', sqlerrm; end;

  -- ══ V22/V23 · another city (Chennai): city switching ═════════════════════
  begin
    v22 := pg_temp.qa_venue(v_owner, 'qa-chennai-1', 'QA Chennai Courts', 'Chennai', 'Tamil Nadu', 'Adyar', 'INDOOR', 'PCTFE', 'ACTIVE', 'COMPLETED', 'A venue in a different city.', img_a, array[img_a, img_b], 'STD');
    c1 := pg_temp.qa_court(v22, 'badminton', null, 'Court 1', 380, 'INDOOR', 'Wooden');
    c2 := pg_temp.qa_court(v22, 'other', 'Padel', 'Padel 1', 1000, 'INDOOR', 'Glass-walled');
    p1 := pg_temp.qa_plan(v22, 'Monthly', 1400, 30);
    perform pg_temp.qa_batch(v22, p1, pg_temp.qa_fs(v22, 'badminton'), c1, 'Evening', array[1,2,3,4,5]::smallint[], '18:00', '19:00', 8);
    k1 := pg_temp.qa_coach(v22, v_owner, 'chennai', 'Karthik', 'State Level Coach', 'Badminton', 7, 4.7, null, pg_temp.qa_fs(v22, 'badminton'));
    pr1 := pg_temp.qa_program(v22, v_owner, pg_temp.qa_fs(v22, 'badminton'), 'Chennai Badminton Basics', 'Beginner', 'Weekday evenings.', 200000, 'MONTHLY', 'GROUP', 0, 89, 8);
    perform pg_temp.qa_cbatch(v22, v_owner, pr1, c1, k1, 'Evening', array[2,4]::smallint[], '18:00', '19:00', 8);
    v23 := pg_temp.qa_venue(v_owner, 'qa-chennai-2', 'QA Chennai Turf', 'Chennai', 'Tamil Nadu', 'Velachery', 'OUTDOOR', 'PT', 'ACTIVE', 'COMPLETED', null, img_c, array[img_c], '24H');
    c3 := pg_temp.qa_court(v23, 'football', null, 'Turf', 1300, 'OUTDOOR', 'Artificial turf');
  exception when others then raise notice 'V22/V23 failed: %', sqlerrm; end;

  -- ══ V24 · a city with no QA coaching / memberships but venues ═════════════
  -- (Hyderabad has one plain venue: the Memberships and Coaching pages must show their "nothing here yet" message for it.)
  begin
    v24 := pg_temp.qa_venue(v_owner, 'qa-hyderabad', 'QA Hyderabad Court', 'Hyderabad', 'Telangana', 'Gachibowli', 'INDOOR', 'P', 'ACTIVE', 'COMPLETED', null, img_a, array[img_a], 'STD');
    c1 := pg_temp.qa_court(v24, 'badminton', null, 'Court 1', 420, 'INDOOR', 'Wooden');
  exception when others then raise notice 'V24 failed: %', sqlerrm; end;

  -- ══ V25 · a venue with MANY plans (12) in one sport ═══════════════════════
  -- Tests the price tiles: only the lowest per length shows, odd duplicates collapse, order stays Monthly → Yearly.
  begin
    v25 := pg_temp.qa_venue(v_owner, 'qa-many-plans', 'QA Many Plans', 'Bangalore', 'Karnataka', 'Kalyan Nagar', 'INDOOR', 'PC', 'ACTIVE', 'COMPLETED', null, img_b, array[img_b], 'STD');
    c1 := pg_temp.qa_court(v25, 'badminton', null, 'Court 1', 400, 'INDOOR', 'Wooden');
    fs_bad := pg_temp.qa_fs(v25, 'badminton');
    for i in 1..12 loop
      p1 := pg_temp.qa_plan(v25, 'Plan ' || lpad(i::text, 2, '0'),
                            (array[2200, 1500, 1800, 4200, 3900, 4500, 8500, 8000, 9000, 15000, 12000, 13500])[i],
                            (array[30, 30, 30, 90, 90, 90, 180, 180, 180, 365, 365, 365])[i]);
      perform pg_temp.qa_batch(v25, p1, fs_bad, c1, 'Batch ' || i, array[1,2,3,4,5]::smallint[], make_time(5 + (i % 12), 0, 0), make_time(6 + (i % 12), 0, 0), 10);
    end loop;
  exception when others then raise notice 'V25 failed: %', sqlerrm; end;

  -- ══ LOAD: 60 venues (list performance, scrolling, filters on a big list) ═══
  if v_load then
    for i in 1..60 loop
      begin
        vq := pg_temp.qa_venue(v_owner, 'qa-load-' || lpad(i::text, 3, '0'), 'QA Load Venue ' || lpad(i::text, 3, '0'), 'Bangalore', 'Karnataka',
              (array['Indiranagar','Koramangala','HSR Layout','Whitefield','Jayanagar','Hebbal','Marathahalli','BTM','JP Nagar','Yelahanka'])[1 + (i % 10)],
              (array['INDOOR','OUTDOOR'])[1 + (i % 2)],
              (array['','P','PC','PCT','PCTF','PCTFE'])[1 + (i % 6)], 'ACTIVE', 'COMPLETED', null,
              case when i % 5 = 0 then null else img_a end, case when i % 5 = 0 then null else array[img_a] end, 'STD');
        c1 := pg_temp.qa_court(vq, (array['badminton','pickleball','cricket','football','tennis'])[1 + (i % 5)], null, 'Court 1', 200 + (i * 37) % 1800, 'INDOOR', 'Wooden');
        if i % 3 = 0 then
          p1 := pg_temp.qa_plan(vq, 'Monthly', 800 + (i * 53) % 3000, 30);
          perform pg_temp.qa_batch(vq, p1, (select facility_sport_id from courts where id = c1), c1, 'Evening', array[1,2,3,4,5]::smallint[], '18:00', '19:00', 10);
        end if;
        if i % 4 = 0 then
          pr1 := pg_temp.qa_program(vq, v_owner, (select facility_sport_id from courts where id = c1), 'Load Coaching ' || i, (array['Beginner','Intermediate','Advanced'])[1 + (i % 3)],
                 'Load-test programme.', 100000 + (i * 1100), (array['MONTHLY','ONE_TIME'])[1 + (i % 2)], 'GROUP', 0, 60, 10);
          perform pg_temp.qa_cbatch(vq, v_owner, pr1, c1, null, 'Evening', array[2,4]::smallint[], '18:00', '19:00', 10);
        end if;
      exception when others then raise notice 'load venue % failed: %', i, sqlerrm; end;
    end loop;
  end if;
  end; -- venues

  -- ══ THE TEST PLAYER'S OWN PAYMENT STATES ═══════════════════════════════════
  -- Needs v_player_phone. Creates a member record with that phone at QA Multi-Sport Arena and gives it memberships / bookings in every
  -- payment state, so Home's prompts, "Payment Incomplete" tags and the Pay buttons can be checked.
  if v1 is null then select id into v1 from facilities where slug = 'qa-multi-sport-arena'; end if;
  if length(v_player_phone) >= 10 and v1 is not null
     and not exists (select 1 from members where facility_id = v1 and full_name = 'QA Test Player') then
    begin
      declare m uuid; ms uuid; pl uuid; plan_ids uuid[]; r record; court uuid;
      begin
        select id into court from courts where facility_id = v1 and name = 'Badminton Court 1';
        insert into members (facility_id, full_name, phone, status) values (v1, 'QA Test Player', v_player_phone, 'ACTIVE')
        on conflict do nothing;
        select id into m from members where facility_id = v1 and phone = v_player_phone limit 1;
        insert into qa_seed_log values ('members', m);

        -- (plan name, total ₹, status, start offset, end offset, payment rows ['paid:N' | 'failed:N' | 'created:N'], subscription status or '')
        for r in
          select * from (values
            ('Badminton Monthly',    1500, 'active',    -3, 27, array['paid:1500'],                '',              '1. PAID in full → "Active", no prompt'),
            ('Padel Monthly',        3200, 'active',    -2, 28, array[]::text[],                   '',              '2. UNPAID → "Payment Incomplete" + prompt (PENDING)'),
            ('Football Monthly',     2800, 'active',    -4, 26, array['failed:2800'],              '',              '3. Payment FAILED → red prompt (FAILED)'),
            ('Tennis Monthly',       2000, 'active',    -1, 29, array['paid:1000'],                '',              '4. PART-PAID (₹1,000 of ₹2,000) → prompt for the balance'),
            ('Pickleball Monthly',   1800, 'active',    -5, 25, array[]::text[],                   'halted',        '5. AutoPay HALTED → FAILED prompt'),
            ('Badminton Quarterly',  4000, 'active',    -6, 84, array[]::text[],                   'active',        '6. AutoPay ACTIVE (mandate approved) → paid, no prompt'),
            ('Badminton Yearly',    12000, 'expired',  -400, -35, array['paid:12000'],             '',              '7. EXPIRED → not listed on Home'),
            ('Padel Half-Year',     17000, 'pending',    0, 180, array[]::text[],                  '',              '8. status PENDING → not listed on Home')
          ) t(plan, total, status, s_off, e_off, pays, sub, note)
        loop
          select id into pl from membership_plans where facility_id = v1 and name = r.plan;
          insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date, auto_renew, created_by, monthly_price_inr, name, membership_type,
                                   duration_days, membership_fee_inr, registration_fee_inr, gst_percent, total_amount_inr)
          values (v1, m, pl, r.status::membership_status, v_today + r.s_off, v_today + r.e_off, r.sub <> '', v_owner, r.total, r.plan, 'INDIVIDUAL',
                  (r.e_off - r.s_off), r.total, 0, 0, r.total)
          returning id into ms;
          insert into qa_seed_log values ('memberships', ms);
          if array_length(r.pays, 1) is not null then
            insert into payments (facility_id, member_id, membership_id, amount_inr, status, payment_method, paid_at)
            select v1, m, ms, split_part(x, ':', 2)::int, split_part(x, ':', 1)::payment_status, 'Online',
                   case when split_part(x, ':', 1) = 'paid' then now() - interval '2 days' end
            from unnest(r.pays) x;
          end if;
          if r.sub <> '' then
            insert into membership_subscriptions (membership_id, facility_id, member_id, razorpay_plan_id, razorpay_subscription_id, status, amount_inr,
                                                  charge_count, current_start, current_end, interval_months, one_time_inr)
            values (ms, v1, m, 'plan_qa_' || substr(ms::text, 1, 8), 'sub_qa_' || substr(ms::text, 1, 8), r.sub::membership_subscription_status,
                    r.total, 1, v_today + r.s_off, v_today + r.e_off, 1, 0);
          end if;
          raise notice 'player state: %  —  %', r.plan, r.note;
        end loop;

        -- guest bookings for the same phone: paid / unpaid (prompt) / part-paid / cancelled / past / far future
        insert into bookings (facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status, amount_minor, currency, payment_status, notes, party_size, created_by)
        select v1, court, 'GUEST', 'QA Test Player', v_player_phone,
               ((v_today + d) + make_time(h, 0, 0)) at time zone 'Asia/Kolkata', ((v_today + d) + make_time(h + 1, 0, 0)) at time zone 'Asia/Kolkata',
               st::booking_status, amt, 'INR', ps, 'QA', 2, v_owner
        from (values
          (2, 18, 'confirmed', 40000, 'PAID'),        -- upcoming, paid → listed, no prompt
          (3, 19, 'confirmed', 40000, 'PENDING'),     -- upcoming, UNPAID → "Payment pending for Guest Booking" prompt
          (4, 20, 'confirmed', 120000, 'PENDING'),    -- upcoming, 3 hours' worth unpaid → bigger prompt amount
          (5, 17, 'cancelled', 40000, 'PENDING'),     -- cancelled → no prompt
          (-3, 18, 'completed', 40000, 'PAID'),       -- past
          (-1, 19, 'completed', 40000, 'PENDING'),    -- past and unpaid → no prompt (it is over)
          (45, 18, 'confirmed', 40000, 'PENDING')     -- far future, unpaid
        ) b(d, h, st, amt, ps);
        insert into qa_seed_log select 'bookings', id from bookings where facility_id = v1 and notes = 'QA' and guest_phone = v_player_phone;
      end;
    exception when others then raise notice 'player payment states failed: %', sqlerrm; end;
  elsif length(v_player_phone) < 10 then
    raise notice 'No v_player_phone set, so the test players payment states were not added (set it and run again to add them).';
  end if;

  raise notice 'QA dataset ready: % QA venues.', (select count(*) from facilities where slug like 'qa-%');
end
$seed$;
