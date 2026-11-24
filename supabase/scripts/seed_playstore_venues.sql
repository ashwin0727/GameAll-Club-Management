-- ═════════════════════════════════════════════════════════════════════
-- PLAY STORE SCREENSHOT VENUES — eight more believable Chennai venues so the GameAll venue list, search and venue pages look full.
--
-- NOT a migration. Run by hand in the Supabase SQL editor (a TEST project, never your live data).
--
-- WHAT IT CREATES
--   One hidden "demo owner" account (so your own login, and the Club app, are not affected) that owns eight venues across Chennai:
--   badminton, pickleball, cricket, football and tennis courts, with courts, prices, opening hours, amenities, an address, a verified
--   map link and a few membership plans each. Every venue is ACTIVE, approved and verified, so GameAll lists it.
--   The venue PHOTOS are copied from the photos you uploaded to your Smash Arena venue (this script cannot create photos itself).
--
-- BEFORE YOU RUN IT
--   1. Upload 3 to 4 court photos to the Smash Arena venue in GameAll Venue (Profile > Facility > Photos).
--   2. Run seed_playstore_screenshots.sql once, so those photos are marked verified.
--
-- HOW TO RUN: run the WHOLE file once. Running it twice does nothing (it stops if the venues exist).
-- TO REMOVE: run the CLEANUP block at the bottom (select it and run it).
--
-- Names, addresses and numbers are made up. Check each screenshot so it shows nothing you do not want shown.
-- ═════════════════════════════════════════════════════════════════════

create table if not exists seedvenues_log (tbl text not null, id uuid not null);

do $venues$
declare
  v_tz        constant text := 'Asia/Kolkata';
  v_src_email text := 'ashwinv277@gmail.com';        -- ← the account that owns Smash Arena (its photos are reused)
  v_owner     uuid := gen_random_uuid();
  v_src_fac   uuid;
  v_fid       uuid;
  v_sp        uuid;
  v_fs        uuid;
  v_sched     uuid;
  v_day       uuid;
  v_pp        uuid;
  v_n         integer;
  dd          integer;
  r           record;
  c           record;
  plan_rec    record;
begin
  if exists (select 1 from seedvenues_log limit 1) then
    raise exception 'These venues already exist. Run the CLEANUP block at the bottom of this file first.';
  end if;

  select f.id into v_src_fac from facilities f join profiles p on p.id = f.owner_id
   where lower(p.email) = lower(v_src_email) order by f.created_at limit 1;

  -- the hidden demo owner (a sign-in that nobody can use: no password)
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                          created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated', 'chennai.venues.seedvenues@example.invalid', '', now(),
          '{"provider":"email","providers":["email"]}', '{"full_name":"Chennai Venues"}', now(), now(), '', '', '', '');
  insert into seedvenues_log values ('auth_users', v_owner);
  update profiles set onboarding_completed = true where id = v_owner;

  -- name, slug, area, postcode, venue type, amenities (parking, changing, toilets, cafeteria, rental), phone, description,
  -- and the courts: sport key, how many, name stem, surface, indoor/outdoor, hourly rate in rupees
  for r in
    select * from (values
      ('Ace Badminton Arena',        'ace-badminton-arena',        'Anna Nagar',    '600040', 'INDOOR',  array[true,  true,  true,  true,  true ], '9841011101',
       'Six air-conditioned wooden courts with professional lighting, a pro shop and a cafe. Popular with leagues and corporate groups.',
       '[["badminton",6,"Court","Wooden","INDOOR",350]]'::jsonb),
      ('Shuttle Hub',                'shuttle-hub',                'T. Nagar',      '600017', 'INDOOR',  array[true,  true,  true,  false, true ], '9841011102',
       'A compact four-court badminton centre in the middle of T. Nagar, open early for morning players. Coaching batches run every evening.',
       '[["badminton",4,"Court","Synthetic","INDOOR",300]]'::jsonb),
      ('Pickle Point Chennai',       'pickle-point-chennai',       'Navalur (OMR)', '600130', 'OUTDOOR', array[true,  true,  true,  true,  true ], '9841011103',
       'Chennai''s dedicated pickleball venue on OMR: three floodlit courts, paddle hire and a friendly beginners'' session every Saturday.',
       '[["pickleball",3,"Court","Acrylic","OUTDOOR",700]]'::jsonb),
      ('Marina Sports Club',         'marina-sports-club',         'Besant Nagar',  '600090', 'OUTDOOR', array[true,  true,  true,  true,  false], '9841011104',
       'A sports club a short walk from the beach: badminton, pickleball and a cricket practice net, with memberships for families.',
       '[["badminton",2,"Court","Wooden","INDOOR",320],["pickleball",1,"Court","Acrylic","OUTDOOR",650],["cricket",1,"Practice Net","Artificial turf","OUTDOOR",900]]'::jsonb),
      ('Velachery Turf and Courts',  'velachery-turf-and-courts',  'Velachery',     '600042', 'OUTDOOR', array[true,  false, true,  true,  true ], '9841011105',
       'A floodlit 7-a-side football turf and a cricket turf, booked by the hour. Weekday evenings fill up fast, so book ahead.',
       '[["football",1,"Turf","Artificial turf","OUTDOOR",1400],["cricket",1,"Turf","Artificial turf","OUTDOOR",1200]]'::jsonb),
      ('Racquet Republic',           'racquet-republic',           'Mylapore',      '600004', 'OUTDOOR', array[true,  true,  true,  true,  true ], '9841011106',
       'Two hard tennis courts and two badminton courts under one roof, with a coaching academy for juniors and adults.',
       '[["tennis",2,"Court","Hard court","OUTDOOR",600],["badminton",2,"Court","Wooden","INDOOR",330]]'::jsonb),
      ('Court Nine Sports Arena',    'court-nine-sports-arena',    'Porur',         '600116', 'INDOOR',  array[true,  true,  true,  false, false], '9841011107',
       'Nine indoor courts for badminton, with an additional pickleball court. Easy parking and a large waiting lounge.',
       '[["badminton",5,"Court","Wooden","INDOOR",340],["pickleball",1,"Court","Acrylic","INDOOR",620]]'::jsonb),
      ('Elite Indoor Stadium',       'elite-indoor-stadium',       'Tambaram',      '600045', 'INDOOR',  array[true,  true,  true,  true,  true ], '9841011108',
       'A large indoor stadium with six badminton courts and a coaching academy. Special rates for students and early-morning slots.',
       '[["badminton",6,"Court","Wooden","INDOOR",280]]'::jsonb)
    ) t(name, slug, area, pin, vtype, amen, phone, descr, courts)
  loop
    insert into facilities (name, slug, owner_id, facility_type, business_email, business_phone, address_line_1, area, city, state, country, postal_code, timezone,
                            description, onboarding_step, onboarding_completed_at, status, venue_type,
                            has_parking, has_changing_rooms, has_toilets, has_cafeteria, has_equipment_rental,
                            location_url, location_verification_status, setup_review_status, setup_reviewed_at)
    values (r.name, r.slug || '-' || substr(gen_random_uuid()::text, 1, 6), v_owner, 'MULTI_SPORT', 'hello@' || r.slug || '.example.invalid', r.phone,
            (10 + (length(r.name) * 3) % 80)::text || ' Main Road', r.area, 'Chennai', 'Tamil Nadu', 'India', r.pin, v_tz,
            r.descr, 'COMPLETED', now() - interval '300 days', 'ACTIVE', r.vtype,
            r.amen[1], r.amen[2], r.amen[3], r.amen[4], r.amen[5],
            'https://www.google.com/maps/search/?api=1&query=' || replace(r.name, ' ', '+') || '+' || replace(r.area, ' ', '+') || '+Chennai',
            'VERIFIED', 'APPROVED', now() - interval '290 days')
    returning id into v_fid;
    insert into seedvenues_log values ('facilities', v_fid);
    insert into facility_users (facility_id, user_id, role) values (v_fid, v_owner, 'owner');

    -- courts, sport by sport
    for c in select * from jsonb_array_elements(r.courts) j(x) loop
      select id into v_sp from sports where key = c.x ->> 0;
      continue when v_sp is null;
      insert into facility_sports (facility_id, sport_id)
      select v_fid, v_sp where not exists (select 1 from facility_sports x where x.facility_id = v_fid and x.sport_id = v_sp and coalesce(x.custom_sport_name, '') = '');
      select id into v_fs from facility_sports where facility_id = v_fid and sport_id = v_sp and coalesce(custom_sport_name, '') = '' limit 1;
      for dd in 1..(c.x ->> 1)::int loop
        insert into courts (facility_id, facility_sport_id, sport_id, name, surface, hourly_rate_inr, area_type, display_order)
        values (v_fid, v_fs, v_sp, (c.x ->> 2) || ' ' || dd, c.x ->> 3, (c.x ->> 5)::int, (c.x ->> 4)::area_type, dd);
      end loop;
      -- a simple price list so the booking screens can price a slot
      begin
        select id into v_pp from pricing_plans where facility_id = v_fid and name = 'Standard Rates' limit 1;
        if v_pp is null then
          insert into pricing_plans (facility_id, name, currency, status) values (v_fid, 'Standard Rates', 'INR', 'ACTIVE') returning id into v_pp;
        end if;
        insert into pricing_rules (pricing_plan_id, facility_id, facility_sport_id, day_type, covers_full_day, amount_minor, currency, pricing_unit, priority, is_active)
        values (v_pp, v_fid, v_fs, 'ALL_DAYS', true, (c.x ->> 5)::int * 100, 'INR', 'PER_HOUR', 1, true);
      exception when others then raise notice 'Pricing skipped for %: %', r.name, sqlerrm; end;
    end loop;

    -- opening hours 6 AM to 10 PM every day
    begin
      insert into operating_schedules (facility_id, scope_type, timezone) values (v_fid, 'FACILITY', v_tz) returning id into v_sched;
      for dd in 0..6 loop
        insert into operating_days (schedule_id, facility_id, day_of_week, is_closed, is_24_hours) values (v_sched, v_fid, dd, false, false) returning id into v_day;
        insert into operating_time_slots (operating_day_id, facility_id, start_time, end_time, crosses_midnight, display_order) values (v_day, v_fid, '06:00', '22:00', false, 0);
      end loop;
    exception when others then raise notice 'Operating hours skipped for %: %', r.name, sqlerrm; end;

    begin
      insert into cancellation_policies (facility_id) values (v_fid) on conflict (facility_id) do nothing;
    exception when others then raise notice 'Cancellation policy skipped for %: %', r.name, sqlerrm; end;

    -- two membership plans per venue
    for plan_rec in select * from (values ('Monthly Pass', 1200, 30), ('Quarterly Pass', 3300, 90)) t(name, price, days) loop
      begin
        insert into membership_plans (facility_id, name, price_inr, duration_days, features, is_active, plan_type)
        values (v_fid, plan_rec.name, plan_rec.price, plan_rec.days, array['Court access'], true, case when plan_rec.days = 30 then 'RECURRING' else 'TIME_BASED' end::membership_plan_type);
      exception when others then raise notice 'Plan skipped for %: %', r.name, sqlerrm; end;
    end loop;

    -- photos: the ones you uploaded to the Smash Arena venue, shown here as this venue's photos too
    if v_src_fac is not null then
      insert into facility_images (facility_id, url, sort_order, verification_status, verified_at)
      select v_fid, i.url, i.sort_order, 'VERIFIED', now() from facility_images i where i.facility_id = v_src_fac;
    end if;
  end loop;

  select count(*) into v_n from facility_images where facility_id in (select id from seedvenues_log where tbl = 'facilities');
  if v_n = 0 then
    raise notice 'The venues have NO photos (Smash Arena has none yet). Upload photos there, run seed_playstore_screenshots.sql, then clean up and run this again.';
  end if;
  raise notice 'Done: % venues created in Chennai.', (select count(*) from seedvenues_log where tbl = 'facilities');
end
$venues$;

-- ═════════════════════════════════════════════════════════════════════
-- CLEANUP: select everything from here down and run it to remove the venues, their courts, plans, photos and the demo owner.
-- ═════════════════════════════════════════════════════════════════════
-- do $clean$
-- begin
--   delete from facilities where id in (select id from seedvenues_log where tbl = 'facilities');   -- courts, hours, plans, photos cascade
--   delete from profiles where id in (select id from seedvenues_log where tbl = 'auth_users');
--   delete from auth.users where id in (select id from seedvenues_log where tbl = 'auth_users');
--   delete from seedvenues_log;
-- end
-- $clean$;
