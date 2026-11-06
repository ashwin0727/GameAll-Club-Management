-- ═══════════════════════════════════════════════════════════════════════════
-- Champz Turf — coaching demo data for the Player app's "Coaching at Champz Turf" page.
--
-- WHY: Champz Turf had two test programmes with no sport, no batches (so no coach / days / time slot) and payment mode OFFLINE,
-- so the Player page had nothing to show and every button said "Pay at club".
--
-- WHAT THIS DOES (run it in the Supabase SQL editor; safe to run again, it never duplicates):
--   • makes sure Badminton is a sport of the venue and that it has a court
--   • adds three coaches (Coach Arjun / Divya / Vignesh) as demo staff users, with certification, experience and rating
--   • creates or updates five programmes: Beginner (monthly), Intermediate (3-month recurring), Advanced (one time, with an
--     early-bird discount), Junior Badminton Academy and Adult Performance Coaching (one time). All are payment mode BOTH.
--   • adds batches (coach + days + time + seats) so the page has time slots: 6-7 AM, 5-6 PM, 6-7 PM, 7-8 PM, 7-8 AM
-- It does NOT touch bookings, members, enrolments or payments.
--
-- If the project does not allow adding auth users from SQL, the owner is used as the coach for all batches (you get a notice).
-- To remove everything again, run the CLEANUP block at the bottom.
-- ═══════════════════════════════════════════════════════════════════════════

do $seed$
declare
  v_facility_id constant uuid := '57115c62-9b45-4e4a-986f-863dbe7b71a2';   -- Champz Turf
  v_facility    uuid;
  v_owner       uuid;
  v_sp          uuid;
  v_fs          uuid;
  v_court       uuid;
  v_today       date := (now() at time zone 'Asia/Kolkata')::date;
  v_uid         uuid;
  v_coach       uuid;
  v_coaches     jsonb := '{}'::jsonb;     -- slug → coaches.id
  rec           record;
begin
  select id, owner_id into v_facility, v_owner from facilities where id = v_facility_id;
  if v_facility is null then
    raise exception 'Champz Turf (%) was not found in this database.', v_facility_id;
  end if;

  -- ── sport + court ──────────────────────────────────────────────────────
  select id into v_sp from sports where key = 'badminton';
  if v_sp is null then raise exception 'The badminton sport is missing from the sports table.'; end if;
  insert into facility_sports (facility_id, sport_id) values (v_facility, v_sp)
  on conflict (facility_id, sport_id) do update set is_active = true;
  select id into v_fs from facility_sports where facility_id = v_facility and sport_id = v_sp;

  select id into v_court from courts where facility_sport_id = v_fs and not archived order by display_order, created_at limit 1;
  if v_court is null then
    insert into courts (facility_id, facility_sport_id, sport_id, name, surface, hourly_rate_inr, area_type, display_order)
    values (v_facility, v_fs, v_sp, 'Badminton Court 1', 'Wooden', 400, 'INDOOR', 1)
    returning id into v_court;
  end if;

  -- ── coaches ────────────────────────────────────────────────────────────
  for rec in
    select * from (values
      ('arjun',   'Coach Arjun',   'BWF Level 1 Certified', 'Badminton — beginners',    8.0, 4.9),
      ('divya',   'Coach Divya',   'State Level Player',    'Badminton — intermediate', 6.0, 4.8),
      ('vignesh', 'Coach Vignesh', 'National Level Player', 'Badminton — advanced',    10.0, 4.9)
    ) as t(slug, full_name, cert, spec, yrs, rating)
  loop
    select id into v_uid from auth.users where email = 'coach.' || rec.slug || '.champz@example.invalid';
    if v_uid is null then
      begin
        v_uid := gen_random_uuid();
        insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                                created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
        values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', 'coach.' || rec.slug || '.champz@example.invalid', '', now(),
                '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', rec.full_name), now(), now(), '', '', '', '');
        -- the sign-up trigger normally makes the profile; make sure it exists with the coach's name
        insert into profiles (id, full_name, email, role)
        values (v_uid, rec.full_name, 'coach.' || rec.slug || '.champz@example.invalid', 'member')
        on conflict (id) do update set full_name = excluded.full_name;
      exception when others then
        raise notice 'Could not add the auth user for % (%): the owner will coach instead.', rec.full_name, sqlerrm;
        v_uid := v_owner;
      end;
    else
      update profiles set full_name = rec.full_name where id = v_uid;
    end if;

    insert into coaches (facility_id, user_id, specialization, certifications, experience_years, hourly_rate_minor, status, joined_on, rating, created_by)
    values (v_facility, v_uid, rec.spec, rec.cert, rec.yrs, 80000, 'ACTIVE', v_today - 365, rec.rating, v_owner)
    on conflict (facility_id, user_id) do update
      set specialization = excluded.specialization, certifications = excluded.certifications, experience_years = excluded.experience_years,
          rating = excluded.rating, status = 'ACTIVE'
    returning id into v_coach;

    insert into coach_sports (coach_id, facility_id, facility_sport_id) values (v_coach, v_facility, v_fs) on conflict do nothing;
    v_coaches := v_coaches || jsonb_build_object(rec.slug, v_coach);
  end loop;

  -- ── programmes (re-running updates them; the two old test programmes are brought up to date by name) ──
  insert into coaching_programs (
    facility_id, name, level, age_group, category, description, facility_sport_id, default_duration_minutes, default_capacity,
    default_price_minor, status, created_by, program_type, start_date, end_date, payment_mode, fee_type, sessions_per_week,
    program_structure, early_bird_discount_minor, discount_valid_till, is_membership_included, enrollment_deadline
  )
  select v_facility, p.name, p.level, p.age_group, 'Coaching', p.descr, v_fs, 60, p.cap,
         p.price, 'ACTIVE', v_owner, 'GROUP', p.st, p.en, 'BOTH', p.fee, p.spw,
         p.struct, p.disc, p.disc_till, false, null
  from (values
    ('Beginner Program',           'Beginner',     'All Ages',  'Build a strong foundation with skills, fitness and game basics.',               299900, 'MONTHLY',  v_today, v_today + 29,                                 3, array['Basic Techniques','Footwork','Fitness & Agility'],                0,     null::date,    8),
    ('Intermediate Program',       'Intermediate', 'Teens & Adults', 'Improve technique, footwork and match play strategy.',                    399900, 'MONTHLY',  v_today, (v_today + interval '3 months' - interval '1 day')::date, 3, array['Footwork','Smash','Net Play','Game Strategy'],             0,     null::date,    6),
    ('Advanced Program',           'Advanced',     'Teens & Adults', 'Performance training, advanced tactics and tournament preparation.',      499900, 'ONE_TIME', v_today, v_today + 60,                                     4, array['Smash','Drop Shot','Game Strategy','Match Practice'],            50000, v_today + 14,  4),
    ('Junior Badminton Academy',   'Beginner',     'Kids 8-14', 'A fun, structured start to badminton for kids.',                                150000, 'ONE_TIME', v_today, v_today + 42,                                     2, array['Basic Techniques','Footwork','Fitness & Agility'],                0,     null::date,   10),
    ('Adult Performance Coaching', 'Intermediate', 'Adults',    'Weekend sessions to sharpen your game and fitness.',                            250000, 'ONE_TIME', v_today, v_today + 56,                                     2, array['Footwork','Net Play','Match Practice'],                           0,     null::date,    8)
  ) as p(name, level, age_group, descr, price, fee, st, en, spw, struct, disc, disc_till, cap)
  on conflict (facility_id, lower(name)) do update set
    level = excluded.level, age_group = excluded.age_group, description = excluded.description, facility_sport_id = excluded.facility_sport_id,
    default_capacity = excluded.default_capacity, default_price_minor = excluded.default_price_minor, status = 'ACTIVE',
    program_type = excluded.program_type, start_date = excluded.start_date, end_date = excluded.end_date, payment_mode = 'BOTH',
    fee_type = excluded.fee_type, sessions_per_week = excluded.sessions_per_week, program_structure = excluded.program_structure,
    early_bird_discount_minor = excluded.early_bird_discount_minor, discount_valid_till = excluded.discount_valid_till,
    is_membership_included = false, enrollment_deadline = null;

  -- ── batches: coach + days + time + seats (0 = Sunday … 6 = Saturday) ──
  insert into coaching_program_batches (facility_id, program_id, court_id, coach_id, name, days_of_week, start_time, end_time, capacity, status, created_by)
  select v_facility, pr.id, v_court, (v_coaches ->> b.coach)::uuid, b.name, b.dow, b.st, b.et, b.cap, 'ACTIVE', v_owner
  from (values
    ('Beginner Program',           'Beginner Evening',     'arjun',   array[1,3,5]::smallint[], time '18:00', time '19:00',  8),
    ('Beginner Program',           'Beginner Early Morning','arjun',  array[2,4,6]::smallint[], time '06:00', time '07:00',  8),
    ('Intermediate Program',       'Intermediate Evening', 'divya',   array[1,3,5]::smallint[], time '18:00', time '19:00',  6),
    ('Advanced Program',           'Advanced Evening',     'vignesh', array[2,4,6]::smallint[], time '19:00', time '20:00',  4),
    ('Junior Badminton Academy',   'Junior Weekday',       'divya',   array[2,4]::smallint[],   time '17:00', time '18:00', 10),
    ('Adult Performance Coaching', 'Adult Weekend',        'arjun',   array[6,0]::smallint[],   time '07:00', time '08:00',  8)
  ) as b(prog, name, coach, dow, st, et, cap)
  join coaching_programs pr on pr.facility_id = v_facility and lower(pr.name) = lower(b.prog)
  where not exists (select 1 from coaching_program_batches x where x.program_id = pr.id and x.name = b.name);

  raise notice 'Done. Champz Turf now has % active programmes and % active batches.',
    (select count(*) from coaching_programs where facility_id = v_facility and status = 'ACTIVE'),
    (select count(*) from coaching_program_batches where facility_id = v_facility and status = 'ACTIVE');
end
$seed$;


-- Check what the Player app will receive (programs, batches, coaches, prices, cycles):
-- select jsonb_pretty(get_public_coaching_enroll('57115c62-9b45-4e4a-986f-863dbe7b71a2'));


-- ═══════════════ CLEANUP (uncomment and run to remove the demo data again) ═══════════════
-- delete from coaching_program_batches where facility_id = '57115c62-9b45-4e4a-986f-863dbe7b71a2'
--   and name in ('Beginner Evening','Beginner Early Morning','Intermediate Evening','Advanced Evening','Junior Weekday','Adult Weekend');
-- delete from coaching_programs p where p.facility_id = '57115c62-9b45-4e4a-986f-863dbe7b71a2'
--   and p.name in ('Beginner Program','Intermediate Program','Advanced Program')
--   and not exists (select 1 from coaching_enrollments e where e.program_id = p.id);
-- delete from coaches where facility_id = '57115c62-9b45-4e4a-986f-863dbe7b71a2'
--   and user_id in (select id from auth.users where email like 'coach.%.champz@example.invalid');
-- delete from auth.users where email like 'coach.%.champz@example.invalid';
