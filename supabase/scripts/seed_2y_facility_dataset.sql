-- ═══════════════════════════════════════════════════════════════════════════
-- TWO-YEAR FACILITY DATASET — one facility, 26 months of history.
--
--   3 Badminton courts · 1 Pickleball court · 1 Cricket turf
--   ~2,000+ guest/member court bookings (paid, unpaid, cancelled, refunded, future)
--   90 members who joined at different times, renewed, discontinued, or are brand new
--   AutoPay memberships, payment-incomplete / part-paid / lapsed memberships
--   membership session slots released to guests (and guest session bookings)
--   coaching: 3 coaches, 5 programs (monthly + one-time + membership-included + completed),
--             ~65 students (active, completed, cancelled, late payers), past sessions + attendance
--   finance: 26 months of expenses (paid / part-paid / unpaid), payments by every method,
--            refunds (processed + pending), failed payment orders, 60 days of daily closings
--
-- NOT a migration. Run by hand in the Supabase SQL editor.
--
-- HOW TO RUN
--   1. Put the account's e-mail in v_owner_email below (the account you will log in with).
--   2. Run the WHOLE file once.
--   3. Run verify_2y_facility_dataset.sql to check the numbers.
--   4. cleanup_2y_facility_dataset.sql removes everything this script added.
--
-- SAFETY
--   * If the account already has a facility WITH bookings the script STOPS (it never mixes fake
--     data into real data). Use a fresh test account, or a facility with no bookings yet.
--   * If the account has no facility the script creates one.
--   * Every id it creates is written to a log table (seed2y_log) so cleanup is exact.
--   * One transaction: if anything fails nothing is left behind.
--   * Dates are relative to today, so the data always looks "2+ years old".
--
-- Phones used: guests 76000000xx, members 77000000xx, coaching-only students 78000000xx.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists seed2y_log (tbl text not null, id uuid not null);

create or replace function seed2y_h(p text) returns integer
language sql immutable as $$ select (('x' || substr(md5(p), 1, 7))::bit(28)::int) $$;

do $seed$
declare
  v_owner_email   text    := 'ashwinv277@gmail.com';   -- ← CHANGE ME
  v_extra_coaches boolean := true;                      -- false = you coach everything (no extra auth users are created)

  v_tz          constant text := 'Asia/Kolkata';
  v_hist_start  date := (date_trunc('month', current_date) - interval '26 months')::date;
  v_owner       uuid;
  v_facility    uuid;
  v_created_fac boolean := false;
  v_fs_bad uuid; v_fs_pkl uuid; v_fs_crk uuid;
  v_sp_bad uuid; v_sp_pkl uuid; v_sp_crk uuid;
  v_n integer;
  v_coach_a uuid; v_coach_b uuid; v_coach_c uuid;   -- coaches.id
  v_uid_b uuid;  v_uid_c uuid;                       -- auth users for the two extra coaches
begin
  if exists (select 1 from seed2y_log limit 1) then
    raise exception 'seed2y_log already has rows — run cleanup_2y_facility_dataset.sql first.';
  end if;

  -- ───────────────────────── 0. owner + facility ─────────────────────────
  select id into v_owner from profiles where lower(email) = lower(v_owner_email);
  if v_owner is null then
    raise exception 'No profile with e-mail %. Sign up that account first.', v_owner_email;
  end if;

  select f.id into v_facility from facilities f where f.owner_id = v_owner order by f.created_at limit 1;

  if v_facility is null then
    insert into facilities (
      name, slug, owner_id, facility_type, business_email, business_phone,
      address_line_1, area, city, state, country, postal_code, timezone,
      description, onboarding_step, onboarding_completed_at, created_at
    ) values (
      'Smash Arena Sports Hub', 'smash-arena-' || substr(gen_random_uuid()::text, 1, 8), v_owner,
      'MULTI_SPORT', v_owner_email, '9000000000',
      '12 Court Road', 'Indiranagar', 'Bengaluru', 'Karnataka', 'India', '560038', v_tz,
      'Two-year demo dataset', 'COMPLETED', now(), (v_hist_start::timestamp at time zone v_tz)
    ) returning id into v_facility;
    insert into facility_users (facility_id, user_id, role) values (v_facility, v_owner, 'owner');
    update profiles set onboarding_completed = true where id = v_owner;
    v_created_fac := true;
    insert into seed2y_log values ('facility', v_facility);
    raise notice 'Created facility %.', v_facility;
  else
    select count(*) into v_n from bookings where facility_id = v_facility;
    if v_n > 0 then
      raise exception 'Facility % already has % bookings. Refusing to mix demo data into real data — use a fresh account.', v_facility, v_n;
    end if;
    raise notice 'Using your existing (empty) facility %.', v_facility;
  end if;

  -- ───────────────────────── 1. sports, courts, hours, pricing ───────────
  select id into v_sp_bad from sports where key = 'badminton';
  select id into v_sp_pkl from sports where key = 'pickleball';
  select id into v_sp_crk from sports where key = 'cricket';

  insert into facility_sports (facility_id, sport_id) values (v_facility, v_sp_bad), (v_facility, v_sp_pkl), (v_facility, v_sp_crk)
  on conflict (facility_id, sport_id) do update set is_active = true;
  select id into v_fs_bad from facility_sports where facility_id = v_facility and sport_id = v_sp_bad;
  select id into v_fs_pkl from facility_sports where facility_id = v_facility and sport_id = v_sp_pkl;
  select id into v_fs_crk from facility_sports where facility_id = v_facility and sport_id = v_sp_crk;

  create temp table t_pre_courts on commit drop as select id from courts where facility_id = v_facility;
  create temp table t_courts (idx int, id uuid, fs_id uuid, sport text, name text, rate_inr int, area text, surface text) on commit drop;
  insert into t_courts values
    (1, null, v_fs_bad, 'BAD', 'Badminton Court 1',  400,  'INDOOR',  'Wooden'),
    (2, null, v_fs_bad, 'BAD', 'Badminton Court 2',  400,  'INDOOR',  'Wooden'),
    (3, null, v_fs_bad, 'BAD', 'Badminton Court 3',  450,  'INDOOR',  'Synthetic'),
    (4, null, v_fs_pkl, 'PKL', 'Pickleball Court 1', 600,  'OUTDOOR', 'Acrylic'),
    (5, null, v_fs_crk, 'CRK', 'Cricket Turf',       1200, 'OUTDOOR', 'Artificial turf');

  insert into courts (facility_id, facility_sport_id, sport_id, name, surface, hourly_rate_inr, area_type, display_order, created_at)
  select v_facility, c.fs_id,
         case c.sport when 'BAD' then v_sp_bad when 'PKL' then v_sp_pkl else v_sp_crk end,
         c.name, c.surface, c.rate_inr, c.area::area_type, c.idx, (v_hist_start::timestamp at time zone v_tz)
  from t_courts c
  where not exists (select 1 from courts x where x.facility_sport_id = c.fs_id and lower(x.name) = lower(c.name) and not x.archived);

  update t_courts c set id = (select x.id from courts x where x.facility_sport_id = c.fs_id and lower(x.name) = lower(c.name) and not x.archived limit 1);
  insert into seed2y_log select 'courts', id from t_courts where id not in (select id from t_pre_courts);

  -- Operating hours 06:00–22:00 every day, a default cancellation policy and a simple price list. Each is optional:
  -- if the facility already has its own we leave it, and a problem here never stops the seed.
  begin
    if not exists (select 1 from operating_schedules where facility_id = v_facility and scope_type = 'FACILITY') then
      declare v_sched uuid; v_day uuid; dd int;
      begin
        insert into operating_schedules (facility_id, scope_type, timezone) values (v_facility, 'FACILITY', v_tz) returning id into v_sched;
        for dd in 0..6 loop
          insert into operating_days (schedule_id, facility_id, day_of_week, is_closed, is_24_hours) values (v_sched, v_facility, dd, false, false) returning id into v_day;
          insert into operating_time_slots (operating_day_id, facility_id, start_time, end_time, crosses_midnight, display_order) values (v_day, v_facility, '06:00', '22:00', false, 0);
        end loop;
      end;
    end if;
  exception when others then raise notice 'Operating hours skipped: %', sqlerrm; end;

  begin
    insert into cancellation_policies (facility_id) values (v_facility) on conflict (facility_id) do nothing;
  exception when others then raise notice 'Cancellation policy skipped: %', sqlerrm; end;

  begin
    declare v_pp uuid;
    begin
      select id into v_pp from pricing_plans where facility_id = v_facility and name = 'Standard Rates' limit 1;
      if v_pp is null then
        insert into pricing_plans (facility_id, name, currency, status) values (v_facility, 'Standard Rates', 'INR', 'ACTIVE') returning id into v_pp;
        insert into pricing_rules (pricing_plan_id, facility_id, facility_sport_id, day_type, covers_full_day, amount_minor, currency, pricing_unit, priority, is_active)
        values (v_pp, v_facility, v_fs_bad, 'ALL_DAYS', true, 40000,  'INR', 'PER_HOUR', 1, true),
               (v_pp, v_facility, v_fs_pkl, 'ALL_DAYS', true, 60000,  'INR', 'PER_HOUR', 1, true),
               (v_pp, v_facility, v_fs_crk, 'ALL_DAYS', true, 120000, 'INR', 'PER_HOUR', 1, true);
      end if;
    end;
  exception when others then raise notice 'Pricing skipped: %', sqlerrm; end;

  -- ───────────────────────── 2. people ───────────────────────────────────
  create temp table t_names (i int, first text, last text) on commit drop;
  insert into t_names
  select g,
         (array['Aarav','Vivaan','Aditya','Vihaan','Arjun','Sai','Krishna','Ishaan','Rohan','Karthik','Ananya','Diya','Isha','Meera','Priya','Sneha','Kavya','Riya','Divya','Pooja','Rahul','Suresh','Manoj','Deepak','Naveen','Lakshmi','Swathi','Nisha','Varun','Harini'])[1 + (g % 30)],
         (array['Sharma','Iyer','Nair','Reddy','Menon','Rao','Kumar','Pillai','Verma','Shetty','Gupta','Bhat','Joshi','Das','Krishnan','Patel','Singh','Naidu','Chandran','Murthy','Hegde','Kulkarni','Desai','Mehta','Banerjee','Ghosh','Bose','Mishra','Pandey','Saxena'])[1 + ((g * 7) % 30)]
  from generate_series(1, 300) g;

  create temp table t_guests (idx int, id uuid, name text, phone text) on commit drop;
  insert into t_guests
  select g, gen_random_uuid(), n.first || ' ' || n.last, '76000000' || lpad(g::text, 2, '0')
  from generate_series(1, 60) g join t_names n on n.i = g + 100;
  insert into guest_players (id, facility_id, name, phone, status, created_at, updated_at)
  select id, v_facility, name, phone, 'ACTIVE', (v_hist_start + idx * 12)::timestamp at time zone v_tz, (v_hist_start + idx * 12)::timestamp at time zone v_tz from t_guests;
  insert into seed2y_log select 'guest_players', id from t_guests;

  -- members: 1..90 are membership people, 91..145 are coaching-only students
  create temp table t_members (idx int, id uuid, kind text, name text, phone text, join_date date) on commit drop;
  insert into t_members
  select g, gen_random_uuid(), case when g <= 90 then 'MEM' else 'STU' end, n.first || ' ' || n.last,
         case when g <= 90 then '77000000' else '78000000' end || lpad((case when g <= 90 then g else g - 90 end)::text, 2, '0'),
         case when g <= 90 then v_hist_start + ((g - 1) * 775 / 89) + (seed2y_h('j' || g) % 6)
              else current_date - 420 + ((g - 91) * 410 / 54) end
  from generate_series(1, 145) g join t_names n on n.i = g;
  insert into members (id, facility_id, full_name, phone, status, created_at, updated_at)
  select id, v_facility, name, phone, 'ACTIVE', join_date::timestamp at time zone v_tz, join_date::timestamp at time zone v_tz from t_members;
  insert into seed2y_log select 'members', id from t_members;

  -- ───────────────────────── 3. membership plans + session batches ──────
  create temp table t_pre_plans on commit drop as select id from membership_plans where facility_id = v_facility;
  create temp table t_plans (code text, id uuid, name text, price int, days int, ptype text) on commit drop;
  insert into t_plans values
    ('BAD_M', gen_random_uuid(), 'Badminton Monthly',   1500,  30,  'RECURRING'),
    ('BAD_Q', gen_random_uuid(), 'Badminton Quarterly', 4000,  90,  'TIME_BASED'),
    ('BAD_A', gen_random_uuid(), 'Badminton Annual',    12000, 365, 'TIME_BASED'),
    ('PKL_M', gen_random_uuid(), 'Pickleball Monthly',  1800,  30,  'RECURRING'),
    ('CRK_W', gen_random_uuid(), 'Cricket Weekend',     2500,  30,  'TIME_BASED');
  insert into membership_plans (id, facility_id, name, price_inr, duration_days, features, is_active, plan_type, created_at)
  select id, v_facility, name, price, days, array['Court access'], true, ptype::membership_plan_type, (v_hist_start::timestamp at time zone v_tz) from t_plans
  on conflict (facility_id, name) do nothing;
  update t_plans p set id = (select x.id from membership_plans x where x.facility_id = v_facility and x.name = p.name);
  insert into seed2y_log select 'membership_plans', id from t_plans where id not in (select id from t_pre_plans);

  create temp table t_batches (code text, id uuid, court_idx int, fs_id uuid, plan_code text, name text, dow smallint[], st time, et time, cap int, status text, end_date date) on commit drop;
  insert into t_batches values
    ('B1', gen_random_uuid(), 1, v_fs_bad, 'BAD_M', 'Badminton Morning Batch',  array[1,2,3,4,5,6]::smallint[], '06:00', '07:00', 20, 'ACTIVE',  null),
    ('B2', gen_random_uuid(), 2, v_fs_bad, 'BAD_M', 'Badminton Evening Batch',  array[1,2,3,4,5,6]::smallint[], '18:00', '19:00', 20, 'ACTIVE',  null),
    ('B3', gen_random_uuid(), 4, v_fs_pkl, 'PKL_M', 'Pickleball Evening Batch', array[1,2,3,4,5]::smallint[],   '19:00', '20:00', 12, 'ACTIVE',  null),
    ('B4', gen_random_uuid(), 5, v_fs_crk, 'CRK_W', 'Cricket Weekend Nets',     array[0,6]::smallint[],         '07:00', '09:00', 20, 'ACTIVE',  null),
    ('B5', gen_random_uuid(), 3, v_fs_bad, 'BAD_M', 'Badminton Night (ended)',  array[1,3,5]::smallint[],       '20:00', '21:00', 20, 'EXPIRED', current_date - 240);
  insert into membership_batches (id, facility_id, plan_id, facility_sport_id, court_id, name, days_of_week, start_time, end_time, capacity, status, start_date, end_date, created_by, created_at)
  select b.id, v_facility, (select p.id from t_plans p where p.code = b.plan_code), b.fs_id, (select c.id from t_courts c where c.idx = b.court_idx),
         b.name, b.dow, b.st, b.et, b.cap, b.status, v_hist_start, b.end_date, v_owner, (v_hist_start::timestamp at time zone v_tz)
  from t_batches b;
  insert into seed2y_log select 'membership_batches', id from t_batches;

  -- ───────────────────────── 4. memberships over 26 months ───────────────
  create temp table t_mcfg (idx int, member_id uuid, join_date date, plan_code text, ongoing boolean, tenure int) on commit drop;
  insert into t_mcfg
  select m.idx, m.id, m.join_date,
         case when seed2y_h('plan' || m.idx) % 100 < 45 then 'BAD_M' when seed2y_h('plan' || m.idx) % 100 < 70 then 'BAD_Q'
              when seed2y_h('plan' || m.idx) % 100 < 78 then 'BAD_A' when seed2y_h('plan' || m.idx) % 100 < 90 then 'PKL_M' else 'CRK_W' end,
         seed2y_h('ong' || m.idx) % 100 < 38,
         1 + seed2y_h('ten' || m.idx) % 13
  from t_members m where m.kind = 'MEM';

  create temp table t_ms0 (id uuid, idx int, member_id uuid, plan_code text, plan_id uuid, plan_name text, price int, pdays int, pm int, k int,
                           start_date date, end_date date, ongoing boolean, tenure int) on commit drop;
  insert into t_ms0
  select gen_random_uuid(), c.idx, c.member_id, c.plan_code, p.id, p.name, p.price, p.days, pm.months, k.k,
         (c.join_date + make_interval(months => k.k * pm.months))::date,
         (c.join_date + make_interval(months => (k.k + 1) * pm.months))::date,
         c.ongoing, c.tenure
  from t_mcfg c
  join t_plans p on p.code = c.plan_code
  cross join lateral (select case p.days when 30 then 1 when 90 then 3 else 12 end as months) pm
  cross join generate_series(0, 40) k(k)
  where (c.join_date + make_interval(months => k.k * pm.months))::date <= current_date
    and (c.ongoing or k.k * pm.months < c.tenure);

  create temp table t_ms (id uuid, idx int, member_id uuid, plan_code text, plan_id uuid, plan_name text, price int, pdays int, pm int, k int,
                          start_date date, end_date date, is_last boolean, status text, pay_mode text, reg_fee int, total int, autopay boolean) on commit drop;
  insert into t_ms
  select s.id, s.idx, s.member_id, s.plan_code, s.plan_id, s.plan_name, s.price, s.pdays, s.pm, s.k, s.start_date, s.end_date, s.is_last,
         case when s.is_last and not s.ongoing and s.end_date < current_date and seed2y_h('can' || s.idx) % 100 < 22 then 'cancelled'
              when s.end_date < current_date then 'expired' else 'active' end,
         case when s.end_date >= current_date and s.is_last and seed2y_h('pm' || s.idx || s.k) % 100 < 9  then 'NONE'
              when s.end_date >= current_date and s.is_last and seed2y_h('pm' || s.idx || s.k) % 100 < 14 then 'HALF'
              when s.end_date < current_date and seed2y_h('old' || s.idx || s.k) % 1000 < 8 then 'NONE'
              else 'PAID' end,
         case when s.k = 0 then 500 else 0 end,
         s.price + case when s.k = 0 then 500 else 0 end,
         (s.plan_code in ('BAD_M', 'PKL_M') and s.ongoing and s.is_last and s.end_date >= current_date and seed2y_h('ap' || s.idx) % 100 < 22)
  from (select o.*, (o.k = max(o.k) over (partition by o.idx)) as is_last from t_ms0 o) s;

  update t_ms set pay_mode = 'PAID' where autopay;   -- an AutoPay membership is always paid up

  insert into memberships (id, facility_id, member_id, plan_id, status, start_date, end_date, auto_renew, created_by, monthly_price_inr, name,
                           membership_type, duration_days, membership_fee_inr, registration_fee_inr, gst_percent, total_amount_inr, created_at)
  select id, v_facility, member_id, plan_id, status::membership_status, start_date, end_date, autopay, v_owner,
         price / pm, plan_name, 'INDIVIDUAL', pdays, price, reg_fee, 0, total, start_date::timestamp at time zone v_tz
  from t_ms;
  insert into seed2y_log select 'memberships', id from t_ms;

  -- membership payments (one per period; part-paid = half; unpaid = none)
  create temp table t_mpay (id uuid, ms_id uuid, member_id uuid, amount int, method text, paid_at timestamptz) on commit drop;
  insert into t_mpay
  select gen_random_uuid(), m.id, m.member_id,
         case m.pay_mode when 'HALF' then m.total / 2 else m.total end,
         (array['UPI','UPI','Cash','Card','Online','Bank Transfer','UPI'])[1 + seed2y_h('mm' || m.id) % 7],
         least((m.start_date::timestamp + make_interval(hours => 9 + seed2y_h('mh' || m.id) % 9)) at time zone v_tz, now())
  from t_ms m where m.pay_mode <> 'NONE';
  insert into payments (id, facility_id, member_id, membership_id, amount_inr, status, payment_method, paid_at, created_at)
  select id, v_facility, member_id, ms_id, amount, 'paid'::payment_status, method, paid_at, paid_at from t_mpay;
  insert into seed2y_log select 'payments', id from t_mpay;

  -- AutoPay subscriptions
  create temp table t_sub (id uuid, ms_id uuid, member_id uuid, idx int, amount int, k int, cstart date, cend date) on commit drop;
  insert into t_sub select gen_random_uuid(), m.id, m.member_id, m.idx, m.price, m.k, m.start_date, m.end_date from t_ms m where m.autopay;
  insert into membership_subscriptions (id, membership_id, facility_id, member_id, razorpay_plan_id, razorpay_subscription_id, status, amount_inr,
                                        charge_count, current_start, current_end, interval_months, one_time_inr, created_at)
  select id, ms_id, v_facility, member_id, 'plan_seed2y_' || idx, 'sub_seed2y_' || idx, 'active'::membership_subscription_status, amount,
         k + 1, cstart, cend, 1, 0, cstart::timestamp at time zone v_tz
  from t_sub;
  insert into seed2y_log select 'membership_subscriptions', id from t_sub;

  -- batch rosters: each member sits in ONE batch and their LATEST membership is the link (so earlier renewals have no sport
  -- of their own — a real-world shape the reports must cope with); about 1 member in 13 was never assigned a batch at all.
  alter table membership_batch_members disable trigger membership_batch_members_eligible;
  create temp table t_roster (id uuid, batch_id uuid, member_id uuid, ms_id uuid, created timestamptz) on commit drop;
  insert into t_roster
  select gen_random_uuid(),
         (select b.id from t_batches b where b.code = case c.plan_code when 'PKL_M' then 'B3' when 'CRK_W' then 'B4'
                                                           else case when seed2y_h('bat' || c.idx) % 2 = 0 then 'B1' else 'B2' end end),
         c.member_id, l.id, c.join_date::timestamp at time zone v_tz
  from t_mcfg c
  join lateral (select m.id from t_ms m where m.idx = c.idx order by m.k desc limit 1) l on true
  where c.idx % 13 <> 0;
  insert into membership_batch_members (id, batch_id, member_id, membership_id, created_at)
  select id, batch_id, member_id, ms_id, created from t_roster;
  alter table membership_batch_members enable trigger membership_batch_members_eligible;
  insert into seed2y_log select 'membership_batch_members', id from t_roster;

  -- a member with no current membership has discontinued
  update members m set status = 'INACTIVE'
  where m.id in (select c.member_id from t_mcfg c)
    and not exists (select 1 from t_ms x where x.member_id = m.id and x.status = 'active');

  -- ───────────────────────── 5. court bookings ───────────────────────────
  -- slots held by membership batches and coaching batches are not offered to walk-ins
  create temp table t_block (cidx int, dow int, hr int) on commit drop;
  insert into t_block
  select 1, d, 6 from generate_series(1, 6) d
  union all select 2, d, 18 from generate_series(1, 6) d
  union all select 4, d, 19 from generate_series(1, 5) d
  union all select 5, d, h from (values (0), (6)) v(d), (values (7), (8)) w(h)
  union all select 3, d, 16 from (values (2), (4), (6)) v(d)
  union all select 4, 6, 9
  union all select 5, 0, h from (values (16), (17)) w(h);

  create temp table t_bk0 (id uuid, cidx int, court_id uuid, rate int, sport text, day date, hr int) on commit drop;
  insert into t_bk0
  select gen_random_uuid(), c.idx, c.id, c.rate_inr, c.sport, d.d::date, h.h
  from generate_series(v_hist_start::timestamp, (current_date + 10)::timestamp, interval '1 day') d(d)
  cross join t_courts c
  cross join generate_series(6, 21) h(h)
  where not exists (select 1 from t_block b where b.cidx = c.idx and b.dow = extract(dow from d.d)::int and b.hr = h.h)
    and (seed2y_h(d.d::date::text || '-' || c.idx || '-' || h.h) % 1000)
        < ( (case c.sport when 'BAD' then 60 when 'PKL' then 45 else 40 end)                               -- base per-mille
          * (case when h.h <= 8 then 0.8 when h.h <= 15 then 0.4 else 1.6 end)                              -- peak hours
          * (case when extract(dow from d.d) in (0, 6) then 1.5 else 1.0 end)                               -- weekends
          * (0.5 + 0.5 * (d.d::date - v_hist_start)::numeric / ((current_date + 10) - v_hist_start)) );     -- the business grows

  create temp table t_bk1 (id uuid, court_id uuid, cidx int, sport text, day date, hr int, start_ts timestamptz, end_ts timestamptz, amount_minor int,
                           cust text, member_id uuid, guest_id uuid, gname text, gphone text, status text, paid boolean, refund_pct int, refund_status text,
                           method text) on commit drop;
  insert into t_bk1
  select b.id, b.court_id, b.cidx, b.sport, b.day, b.hr, t.start_ts, t.start_ts + interval '1 hour',
         (b.rate * 100 * case when b.hr >= 18 and extract(dow from b.day) not in (0, 6) then 125 else 100 end / 100)::int,
         case when mm.id is not null then 'MEMBER' else 'GUEST' end,
         mm.id, case when mm.id is null then g.id end, case when mm.id is null then g.name end, case when mm.id is null then g.phone end,
         x.status, x.paid, x.refund_pct, x.refund_status,
         case when seed2y_h('pmeth' || b.id) % 100 < 2 then null
              when b.sport = 'CRK' then (array['UPI','Bank Transfer','Cash','UPI'])[1 + seed2y_h('pm' || b.id) % 4]
              else (array['UPI','UPI','Cash','Card','UPI','Cash','Online'])[1 + seed2y_h('pm' || b.id) % 7] end
  from t_bk0 b
  cross join lateral (select (b.day::timestamp + make_interval(hours => b.hr)) at time zone v_tz as start_ts) t
  left join t_members mm on mm.kind = 'MEM' and mm.idx = 1 + seed2y_h('mem' || b.id) % 90 and mm.join_date <= b.day and seed2y_h('ism' || b.id) % 100 < 22
  join t_guests g on g.idx = 1 + seed2y_h('gst' || b.id) % 60
  cross join lateral (
    select
      case when t.start_ts >= now() then 'confirmed'
           when seed2y_h('st' || b.id) % 1000 < (case when b.day >= current_date - 45 then 90 else 15 end) then 'completed'    -- played but never paid
           when seed2y_h('st' || b.id) % 1000 < (case when b.day >= current_date - 45 then 160 else 85 end) then 'cancelled'
           else 'completed' end as status,
      case when t.start_ts >= now() then seed2y_h('adv' || b.id) % 100 < 35                                                    -- advance paid
           when seed2y_h('st' || b.id) % 1000 < (case when b.day >= current_date - 45 then 90 else 15 end) then false
           when seed2y_h('st' || b.id) % 1000 < (case when b.day >= current_date - 45 then 160 else 85 end) then seed2y_h('cp' || b.id) % 100 < 60
           else true end as paid,
      case when seed2y_h('rf' || b.id) % 100 < 50 then 100 else 50 end as refund_pct,
      case when t.start_ts > now() - interval '20 days' and seed2y_h('rs' || b.id) % 100 < 30
             then (case when seed2y_h('rs2' || b.id) % 2 = 0 then 'REQUESTED' else 'PENDING' end)
           else 'PROCESSED' end as refund_status
  ) x;

  create temp table t_bk (id uuid, court_id uuid, cidx int, sport text, day date, hr int, start_ts timestamptz, end_ts timestamptz, amount_minor int,
                          cust text, member_id uuid, guest_id uuid, gname text, gphone text, status text, paid boolean, refund_pct int, refund_status text,
                          method text, pay_status text, pay_ts timestamptz, failed_order boolean) on commit drop;
  insert into t_bk
  select b.*,
         case when b.status = 'cancelled' and b.paid then 'REFUNDED' when b.paid then 'PAID' else 'PENDING' end,
         least(case when b.start_ts >= now() then now() - make_interval(hours => 1 + seed2y_h('fp' || b.id) % 100)
                    when seed2y_h('pt' || b.id) % 2 = 0 then b.start_ts - interval '45 minutes'
                    else b.start_ts + interval '1 hour' end, now()),
         (b.status = 'completed' and not b.paid and seed2y_h('fo' || b.id) % 100 < 14)
  from t_bk1 b;

  insert into bookings (id, facility_id, court_id, member_id, customer_type, guest_name, guest_phone, guest_player_id, start_time, end_time, status,
                        amount_minor, currency, payment_status, cancellation_reason, notes, party_size, payment_method, created_by, created_at)
  select id, v_facility, court_id, member_id, cust, gname, gphone, guest_id, start_ts, end_ts, status::booking_status,
         amount_minor, 'INR', pay_status, case when status = 'cancelled' then 'Cancelled by customer' end, 'SEED2Y',
         case when sport = 'CRK' then 12 when sport = 'PKL' then 4 else 2 end,
         case when paid then method end, v_owner, least(start_ts - interval '2 days', now())
  from t_bk;
  insert into seed2y_log select 'bookings', id from t_bk;

  -- payment orders: one for every refunded / refund-pending booking, and a failed attempt on some unpaid ones
  create temp table t_po (id uuid, bk_id uuid, cust text, amount int, status text, created timestamptz) on commit drop;
  insert into t_po
  select gen_random_uuid(), b.id, b.cust, b.amount_minor,
         case when b.failed_order then 'FAILED'
              when b.refund_status = 'PROCESSED' and b.refund_pct = 100 then 'REFUNDED'
              when b.refund_status = 'PROCESSED' then 'PARTIALLY_REFUNDED' else 'REFUND_REQUESTED' end,
         least(b.start_ts - interval '2 days', now())
  from t_bk b
  where b.failed_order or (b.status = 'cancelled' and b.paid);
  insert into payment_orders (id, facility_id, source_type, booking_id, amount_minor, currency, status, receipt, expires_at, created_by, created_at)
  select id, v_facility, (case cust when 'MEMBER' then 'MEMBER_BOOKING' else 'GUEST_BOOKING' end)::payment_source_type, bk_id,
         amount, 'INR', status::payment_order_status, 'seed2y-' || substr(id::text, 1, 8), created + interval '30 minutes', v_owner, created
  from t_po;
  insert into seed2y_log select 'payment_orders', id from t_po;

  -- booking payments
  create temp table t_bpay (id uuid, bk_id uuid, po_id uuid) on commit drop;
  insert into t_bpay
  select gen_random_uuid(), b.id, (select o.id from t_po o where o.bk_id = b.id and o.status <> 'FAILED')
  from t_bk b where b.paid;
  insert into payments (id, facility_id, member_id, booking_id, guest_player_id, payment_order_id, amount_inr, status, payment_method, paid_at, created_at)
  select p.id, v_facility, b.member_id, b.id, b.guest_id, p.po_id, b.amount_minor / 100, 'paid'::payment_status, b.method, b.pay_ts, b.pay_ts
  from t_bpay p join t_bk b on b.id = p.bk_id;
  insert into seed2y_log select 'payments', id from t_bpay;

  -- refunds (the payment stays 'paid'; the refund is its own row — that is how the app records it)
  create temp table t_rf (id uuid, bk_id uuid, po_id uuid, pay_id uuid) on commit drop;
  insert into t_rf
  select gen_random_uuid(), b.id, bp.po_id, bp.id from t_bk b join t_bpay bp on bp.bk_id = b.id
  where b.status = 'cancelled' and bp.po_id is not null;
  insert into refunds (id, facility_id, payment_order_id, transaction_id, source_type, source_id, razorpay_payment_id, razorpay_refund_id, amount_minor,
                       currency, reason, status, is_override, policy_percent_applied, initiated_by, created_at, processed_at)
  select r.id, v_facility, r.po_id, r.pay_id, (case b.cust when 'MEMBER' then 'MEMBER_BOOKING' else 'GUEST_BOOKING' end)::payment_source_type, b.id,
         'pay_seed2y_' || substr(r.id::text, 1, 10), case when b.refund_status = 'PROCESSED' then 'rfnd_seed2y_' || substr(r.id::text, 1, 10) end,
         b.amount_minor * b.refund_pct / 100, 'INR', 'CUSTOMER_CANCELLATION'::refund_reason, b.refund_status::refund_status, false, b.refund_pct, v_owner,
         b.start_ts - interval '6 hours', case when b.refund_status = 'PROCESSED' then b.start_ts - interval '5 hours' end
  from t_rf r join t_bk b on b.id = r.bk_id;
  insert into seed2y_log select 'refunds', id from t_rf;

  -- ───────────────────────── 6. membership sessions + guests in released slots
  create temp table t_ses (id uuid, batch_id uuid, court_id uuid, fs_id uuid, d date, st time, et time, cap int, rel int) on commit drop;
  insert into t_ses
  select gen_random_uuid(), b.id, (select c.id from t_courts c where c.idx = b.court_idx), b.fs_id, g.d::date, b.st, b.et, b.cap, seed2y_h('rel' || b.id || g.d) % 4
  from t_batches b
  cross join generate_series((current_date - 150)::timestamp, (current_date + 7)::timestamp, interval '1 day') g(d)
  where b.code in ('B1', 'B2', 'B3', 'B4') and extract(dow from g.d)::int = any (b.dow);
  insert into membership_sessions (id, batch_id, facility_id, court_id, facility_sport_id, session_date, start_time, end_time, capacity, released_capacity, created_at)
  select id, batch_id, v_facility, court_id, fs_id, d, st, et, cap, rel, d::timestamp at time zone v_tz from t_ses;
  insert into seed2y_log select 'membership_sessions', id from t_ses;

  create temp table t_sb (id uuid, ses_id uuid, guest_id uuid, amount int, d date, paid boolean, method text) on commit drop;
  insert into t_sb
  select gen_random_uuid(), s.id, g.id, case when s.fs_id = v_fs_crk then 30000 else 20000 end, s.d, seed2y_h('sbp' || s.id) % 100 < 85,
         (array['UPI','Cash','UPI','Card'])[1 + seed2y_h('sbm' || s.id) % 4]
  from t_ses s join t_guests g on g.idx = 1 + seed2y_h('sbg' || s.id) % 60
  where s.rel > 0 and s.d < current_date and seed2y_h('sbx' || s.id) % 100 < 50;
  insert into membership_session_bookings (id, session_id, facility_id, participant_type, guest_player_id, status, slot_source, amount_minor, currency, created_by, created_at)
  select id, ses_id, v_facility, 'GUEST', guest_id, 'CONFIRMED', 'RELEASED', amount, 'INR', v_owner, d::timestamp at time zone v_tz from t_sb;
  insert into seed2y_log select 'membership_session_bookings', id from t_sb;

  create temp table t_sbp (id uuid, sb_id uuid) on commit drop;
  insert into t_sbp select gen_random_uuid(), id from t_sb where paid;
  insert into payments (id, facility_id, guest_player_id, membership_session_booking_id, amount_inr, status, payment_method, paid_at, created_at)
  select p.id, v_facility, s.guest_id, s.id, s.amount / 100, 'paid'::payment_status, s.method, (s.d::timestamp + interval '7 hours') at time zone v_tz, (s.d::timestamp + interval '7 hours') at time zone v_tz
  from t_sbp p join t_sb s on s.id = p.sb_id;
  insert into seed2y_log select 'payments', id from t_sbp;

  -- ───────────────────────── 7. coaching ─────────────────────────────────
  -- coaches: you, plus two extra users (if this project lets us add auth users; otherwise you coach everything)
  v_uid_b := gen_random_uuid(); v_uid_c := gen_random_uuid();
  begin
    if not v_extra_coaches then raise exception 'extra coaches switched off'; end if;
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                            created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', v_uid_b, 'authenticated', 'authenticated', 'coach.priya.seed2y@example.invalid', '', now(),
            '{"provider":"email","providers":["email"]}', '{"full_name":"Priya Coach"}', now(), now(), '', '', '', ''),
           ('00000000-0000-0000-0000-000000000000', v_uid_c, 'authenticated', 'authenticated', 'coach.ravi.seed2y@example.invalid', '', now(),
            '{"provider":"email","providers":["email"]}', '{"full_name":"Ravi Coach"}', now(), now(), '', '', '', '');
    insert into seed2y_log values ('auth_users', v_uid_b), ('auth_users', v_uid_c);
  exception when others then
    raise notice 'Extra coach users not added (%): you will be the only coach.', sqlerrm;
    v_uid_b := v_owner; v_uid_c := v_owner;
  end;

  insert into coaches (facility_id, user_id, specialization, experience_years, hourly_rate_minor, status, joined_on, created_by)
  values (v_facility, v_owner, 'Head coach — Badminton', 12, 90000, 'ACTIVE', current_date - 600, v_owner)
  on conflict (facility_id, user_id) do nothing;
  select id into v_coach_a from coaches where facility_id = v_facility and user_id = v_owner;
  if v_uid_b <> v_owner then
    insert into coaches (facility_id, user_id, specialization, experience_years, hourly_rate_minor, status, joined_on, created_by)
    values (v_facility, v_uid_b, 'Pickleball', 6, 70000, 'ACTIVE', current_date - 400, v_owner),
           (v_facility, v_uid_c, 'Cricket',    9, 80000, 'ACTIVE', current_date - 500, v_owner);
    select id into v_coach_b from coaches where facility_id = v_facility and user_id = v_uid_b;
    select id into v_coach_c from coaches where facility_id = v_facility and user_id = v_uid_c;
  else
    v_coach_b := v_coach_a; v_coach_c := v_coach_a;
  end if;
  insert into seed2y_log select 'coaches', c from unnest(array[v_coach_a, v_coach_b, v_coach_c]) c group by c;
  insert into coach_sports (coach_id, facility_id, facility_sport_id)
  values (v_coach_a, v_facility, v_fs_bad), (v_coach_b, v_facility, v_fs_pkl), (v_coach_c, v_facility, v_fs_crk)
  on conflict do nothing;

  create temp table t_prog (code text, id uuid, name text, fs_id uuid, fee text, price int, st date, en date, status text, incl boolean, ptype text, spw int) on commit drop;
  insert into t_prog values
    ('P1', gen_random_uuid(), 'Badminton Junior Academy',       v_fs_bad, 'MONTHLY',  300000, current_date - 450, current_date + 120, 'ACTIVE',    false, 'GROUP', 3),
    ('P2', gen_random_uuid(), 'Badminton Weekend Camp (ended)', v_fs_bad, 'ONE_TIME', 600000, current_date - 280, current_date - 220, 'COMPLETED', false, 'GROUP', 2),
    ('P3', gen_random_uuid(), 'Pickleball Starter Program',     v_fs_pkl, 'ONE_TIME', 500000, current_date - 70,  current_date + 40,  'ACTIVE',    false, 'GROUP', 1),
    ('P4', gen_random_uuid(), 'Cricket Academy Under-14',       v_fs_crk, 'MONTHLY',  450000, current_date - 360, current_date + 90,  'ACTIVE',    false, 'GROUP', 1),
    ('P5', gen_random_uuid(), 'Fitness Clinic (members only)',  v_fs_bad, 'ONE_TIME', 0,      current_date - 200, current_date + 100, 'ACTIVE',    true,  'GROUP', 1);
  insert into coaching_programs (id, facility_id, name, level, age_group, category, facility_sport_id, default_duration_minutes, default_capacity, default_price_minor,
                                 is_membership_included, status, created_by, program_type, start_date, end_date, payment_mode, fee_type, sessions_per_week, created_at)
  select id, v_facility, name, 'Beginner', 'All Ages', 'Coaching', fs_id, 60, 20, price, incl, status, v_owner, ptype, st, en, 'BOTH', fee, spw, st::timestamp at time zone v_tz
  from t_prog;
  insert into seed2y_log select 'coaching_programs', id from t_prog;

  create temp table t_cb (code text, id uuid, prog text, court_idx int, coach uuid, name text, dow smallint[], st time, et time, cap int, status text) on commit drop;
  insert into t_cb values
    ('CB1', gen_random_uuid(), 'P1', 3, v_coach_a, 'Junior Tue/Thu/Sat',    array[2,4,6]::smallint[], '16:00', '17:00', 20, 'ACTIVE'),
    ('CB2', gen_random_uuid(), 'P2', 3, v_coach_a, 'Weekend Camp (ended)',  array[1,3]::smallint[],   '19:00', '20:00', 20, 'INACTIVE'),
    ('CB3', gen_random_uuid(), 'P3', 4, v_coach_b, 'Pickleball Saturday',   array[6]::smallint[],     '09:00', '10:00', 12, 'ACTIVE'),
    ('CB4', gen_random_uuid(), 'P4', 5, v_coach_c, 'Cricket Sunday',        array[0]::smallint[],     '16:00', '18:00', 20, 'ACTIVE'),
    ('CB5', gen_random_uuid(), 'P5', 3, v_coach_a, 'Fitness Clinic Monday', array[1]::smallint[],     '12:00', '13:00', 20, 'ACTIVE');
  insert into coaching_program_batches (id, facility_id, program_id, court_id, coach_id, name, days_of_week, start_time, end_time, capacity, status, created_by, created_at)
  select b.id, v_facility, (select p.id from t_prog p where p.code = b.prog), (select c.id from t_courts c where c.idx = b.court_idx), b.coach, b.name, b.dow,
         b.st, b.et, b.cap, b.status, v_owner, ((select p.st from t_prog p where p.code = b.prog)::timestamp at time zone v_tz)
  from t_cb b;
  insert into seed2y_log select 'coaching_program_batches', id from t_cb;

  -- enrollments: the 55 coaching-only students plus a few membership holders (members who also take coaching).
  -- A MONTHLY enrollment is for every month from its start to the program's end (that is how the app prices it), so after
  -- the first instalment most of the fee is still outstanding — exactly the "paid month 1, next due next month" case.
  create temp table t_en0 (id uuid, member_id uuid, prog text, st date, en date, cycles int, status text, cancel_at date, price int, fee text, ptype text, idx int) on commit drop;
  insert into t_en0
  select gen_random_uuid(), m.id, pr.code, s.st, s.en, s.cycles,
         case when s.cancel_at is not null then 'CANCELLED' when s.en < current_date then 'COMPLETED' when seed2y_h('pa' || m.idx) % 100 < 3 then 'PAUSED' else 'ACTIVE' end,
         s.cancel_at,
         case when pr.incl then 0 when pr.fee = 'MONTHLY' then (pr.price * s.cycles) else pr.price end,
         pr.fee, case when pr.incl then 'MEMBERSHIP_INCLUDED' else 'STANDARD' end, m.idx
  from t_members m
  join lateral (select p.code, p.price, p.fee, p.st, p.en, p.incl from t_prog p
                where p.code = case when m.kind = 'STU' then (array['P1','P1','P1','P4','P4','P3','P2','P2'])[1 + seed2y_h('ep' || m.idx) % 8] else 'P5' end) pr on true
  cross join lateral (select greatest(pr.st, least(current_date - 3, m.join_date + 3 + seed2y_h('es' || m.idx) % 40))::date as st) base
  cross join lateral (
    select base.st as st, pr.en as en,
           case when pr.fee = 'MONTHLY' then coaching_billing_cycles(base.st, pr.en) else 1 end as cycles,
           case when pr.code not in ('P2', 'P5') and seed2y_h('ex' || m.idx) % 100 < 15 and base.st < current_date - 45
                then (base.st + 30 + seed2y_h('ed' || m.idx) % 60)::date end as cancel_at
  ) s
  where (m.kind = 'STU' or (m.kind = 'MEM' and m.idx % 9 = 0))
    and s.st <= pr.en;

  insert into coaching_enrollments (id, facility_id, member_id, program_id, batch_id, start_date, end_date, price_minor, pricing_type, status, notes,
                                    created_by, created_at, cancelled_at, cancel_reason, fee_type, billing_cycles)
  select e.id, v_facility, e.member_id, (select p.id from t_prog p where p.code = e.prog), (select b.id from t_cb b where b.prog = e.prog),
         e.st, e.en, e.price, e.ptype, e.status, 'SEED2Y', v_owner, e.st::timestamp at time zone v_tz,
         case when e.status = 'CANCELLED' then e.cancel_at::timestamp at time zone v_tz end, case when e.status = 'CANCELLED' then 'Stopped attending' end,
         e.fee, e.cycles
  from t_en0 e;
  insert into seed2y_log select 'coaching_enrollments', id from t_en0;

  -- instalments + subscription billing for the MONTHLY enrollments
  create temp table t_enb (id uuid, en_id uuid, amount int, cycles int, charges int, status text, cstart date, cend date, idx int) on commit drop;
  insert into t_enb
  select gen_random_uuid(), e.id, e.price / e.cycles, e.cycles,
         greatest(0, least(e.cycles,
           (extract(year from age(least(current_date, coalesce(e.cancel_at, current_date), e.en)::timestamp, e.st::timestamp)) * 12
            + extract(month from age(least(current_date, coalesce(e.cancel_at, current_date), e.en)::timestamp, e.st::timestamp)))::int + 1
           - case when e.status = 'ACTIVE' and seed2y_h('late' || e.id) % 100 < 14 then 1 else 0 end)),
         case when e.status = 'CANCELLED' then 'CANCELLED' when e.status = 'COMPLETED' then 'COMPLETED'
              when seed2y_h('late' || e.id) % 100 < 14 then (case when seed2y_h('halt' || e.id) % 2 = 0 then 'PENDING' else 'HALTED' end)
              else 'ACTIVE' end,
         null::date, null::date, e.idx
  from t_en0 e where e.fee = 'MONTHLY' and e.ptype = 'STANDARD';
  update t_enb b set cstart = (e.st + make_interval(months => greatest(b.charges - 1, 0)))::date,
                     cend   = (e.st + make_interval(months => b.charges))::date
    from t_en0 e where e.id = b.en_id;

  create temp table t_enp (id uuid, en_id uuid, member_id uuid, amount_inr int, method text, paid_at timestamptz) on commit drop;
  insert into t_enp
  select gen_random_uuid(), b.en_id, e.member_id, b.amount / 100,
         (array['UPI','Card','Online','UPI','Bank Transfer'])[1 + seed2y_h('em' || b.en_id || i.i) % 5],
         least(((e.st + make_interval(months => i.i))::timestamp + interval '10 hours') at time zone v_tz, now())
  from t_enb b join t_en0 e on e.id = b.en_id
  cross join lateral generate_series(0, b.charges - 1) i(i)
  where b.charges > 0;

  -- ONE_TIME: 70% paid in full, 15% paid half, 15% not paid yet (overdue)
  insert into t_enp
  select gen_random_uuid(), e.id, e.member_id,
         case when seed2y_h('op' || e.id) % 100 < 70 then e.price / 100 else e.price / 200 end,
         (array['UPI','Cash','Card','UPI'])[1 + seed2y_h('om' || e.id) % 4],
         least((e.st::timestamp + interval '10 hours') at time zone v_tz, now())
  from t_en0 e where e.fee = 'ONE_TIME' and e.ptype = 'STANDARD' and seed2y_h('op' || e.id) % 100 < 85;

  insert into payments (id, facility_id, member_id, coaching_enrollment_id, amount_inr, status, payment_method, paid_at, created_at)
  select id, v_facility, member_id, en_id, amount_inr, 'paid'::payment_status, method, paid_at, paid_at from t_enp;
  insert into seed2y_log select 'payments', id from t_enp;

  insert into coaching_enrollment_billing (id, enrollment_id, facility_id, kind, status, amount_minor, total_cycles, charge_count, razorpay_subscription_id, razorpay_plan_id,
                                            current_start, current_end, created_by, created_at)
  select b.id, b.en_id, v_facility, 'SUBSCRIPTION', b.status, b.amount, b.cycles, b.charges, 'sub_seed2y_en_' || b.idx, 'plan_seed2y_en', b.cstart, b.cend, v_owner,
         (select e.st::timestamp at time zone v_tz from t_en0 e where e.id = b.en_id)
  from t_enb b where b.charges > 0;
  insert into seed2y_log select 'coaching_enrollment_billing', id from t_enb where charges > 0;

  -- past sessions + attendance (future ones are generated by the program triggers)
  create temp table t_cs (id uuid, batch_id uuid, prog_id uuid, court_id uuid, coach uuid, fs_id uuid, st timestamptz, et timestamptz, cap int, status text, d date, bcode text) on commit drop;
  insert into t_cs
  select gen_random_uuid(), b.id, p.id, (select c.id from t_courts c where c.idx = b.court_idx), b.coach, p.fs_id,
         (g.d::date::timestamp + b.st) at time zone v_tz, (g.d::date::timestamp + b.et) at time zone v_tz, b.cap,
         case when seed2y_h('cs' || b.id || g.d) % 100 < 5 then 'CANCELLED' else 'COMPLETED' end, g.d::date, b.code
  from t_cb b join t_prog p on p.code = b.prog
  cross join lateral generate_series(p.st::timestamp, (least(p.en, current_date - 1))::timestamp, interval '1 day') g(d)
  where extract(dow from g.d)::int = any (b.dow);
  insert into coaching_sessions (id, facility_id, program_id, coach_id, court_id, facility_sport_id, batch_id, start_at, end_at, capacity, status, created_by,
                                 completed_at, cancelled_at, cancel_reason, created_at)
  select id, v_facility, prog_id, coach, court_id, fs_id, batch_id, st, et, cap, status, v_owner,
         case when status = 'COMPLETED' then et end, case when status = 'CANCELLED' then st - interval '3 hours' end,
         case when status = 'CANCELLED' then 'Coach unavailable' end, st - interval '1 day'
  from t_cs;
  insert into seed2y_log select 'coaching_sessions', id from t_cs;

  create temp table t_css (id uuid, ses_id uuid, en_id uuid, added timestamptz) on commit drop;
  insert into t_css
  select gen_random_uuid(), s.id, e.id, s.st - interval '1 day'
  from t_cs s
  join t_cb b on b.id = s.batch_id
  join t_en0 e on e.prog = b.prog
  where s.status = 'COMPLETED'
    and e.st <= s.d and e.en >= s.d
    and (e.cancel_at is null or e.cancel_at >= s.d)
    and seed2y_h('att' || s.id || e.id) % 100 < 88;   -- about 88% attendance
  insert into coaching_session_students (id, session_id, enrollment_id, facility_id, status, added_by, added_at)
  select id, ses_id, en_id, v_facility, 'ENROLLED', v_owner, added from t_css;
  insert into seed2y_log select 'coaching_session_students', id from t_css;

  -- ───────────────────────── 8. expenses (26 months) ─────────────────────
  create temp table t_exp (id uuid, cat text, vendor text, spent_on date, amount_rupees int, method text, pstatus text, paid_rupees int, due date) on commit drop;
  insert into t_exp
  select gen_random_uuid(), x.cat, x.vendor, x.spent_on, x.amount, x.method,
         case when x.spent_on < current_date - 40 then 'PAID'
              when x.cat in ('Utilities', 'Maintenance') and seed2y_h('ps' || x.cat || x.spent_on) % 100 < 60 then 'PENDING'
              when x.cat = 'Equipment' then 'PARTIAL' else 'PAID' end,
         0, x.spent_on + 10
  from (
    select (m::date) as spent_on, 'Rent' as cat, 'City Properties' as vendor,
           (45000 + case when m >= v_hist_start::timestamp + interval '12 months' then 3000 else 0 end) as amount, 'Bank Transfer' as method
      from generate_series(v_hist_start::timestamp, date_trunc('month', current_date)::timestamp, interval '1 month') m
    union all select m::date + 27, 'Staff', 'Payroll', 60000 + case when m >= v_hist_start::timestamp + interval '12 months' then 4000 else 0 end, 'Bank Transfer'
      from generate_series(v_hist_start::timestamp, date_trunc('month', current_date - 30)::timestamp, interval '1 month') m
    union all select m::date + 9, 'Utilities', 'State Electricity Board', 18000 + seed2y_h('ut' || m) % 14000, 'UPI'
      from generate_series(v_hist_start::timestamp, date_trunc('month', current_date)::timestamp, interval '1 month') m
    union all select m::date + 14, 'Cleaning', 'Sparkle Services', 8000, 'Cash'
      from generate_series(v_hist_start::timestamp, date_trunc('month', current_date)::timestamp, interval '1 month') m
    union all select m::date + 4, 'Software', 'GameAll Subscription', 1999, 'UPI'
      from generate_series(v_hist_start::timestamp, date_trunc('month', current_date)::timestamp, interval '1 month') m
    union all select m::date + 19, 'Marketing', 'Local Ads', 10000 + seed2y_h('mk' || m) % 8000, 'UPI'
      from generate_series(v_hist_start::timestamp, date_trunc('month', current_date)::timestamp, interval '2 months') m
    union all select m::date + 21, 'Equipment', 'Sports Mart', 15000 + seed2y_h('eq' || m) % 25000, 'Card'
      from generate_series(v_hist_start::timestamp, date_trunc('month', current_date)::timestamp, interval '3 months') m
    union all select m::date + 12, 'Maintenance', 'Court Care Co.', 3000 + seed2y_h('mt' || m) % 22000, (array['Cash','UPI'])[1 + seed2y_h('mtm' || m) % 2]
      from generate_series(v_hist_start::timestamp, date_trunc('month', current_date)::timestamp, interval '1 month') m
      where seed2y_h('mtx' || m) % 100 < 55
  ) x
  where x.spent_on <= current_date;
  -- only the last 40 days can be unpaid / part-paid
  update t_exp set pstatus = 'PAID' where spent_on < current_date - 40;
  update t_exp set paid_rupees = case pstatus when 'PAID' then amount_rupees when 'PARTIAL' then amount_rupees * 6 / 10 else 0 end;

  insert into expenses (id, facility_id, category_id, amount_minor, currency, payment_method, spent_on, vendor, reference, notes, status, created_by,
                        amount_paid_minor, payment_status, due_on, created_at)
  select e.id, v_facility, (select c.id from expense_categories c where c.facility_id is null and c.name = e.cat limit 1), e.amount_rupees * 100, 'INR',
         case when e.pstatus = 'PENDING' then null else e.method end, e.spent_on, e.vendor, 'SEED2Y', 'SEED2Y ' || e.cat, 'RECORDED', v_owner,
         e.paid_rupees * 100, e.pstatus, case when e.pstatus <> 'PAID' then e.due end, e.spent_on::timestamp at time zone v_tz
  from t_exp e;
  insert into seed2y_log select 'expenses', id from t_exp;

  create temp table t_expp (id uuid, exp_id uuid, amount int, paid_on date, method text) on commit drop;
  insert into t_expp select gen_random_uuid(), e.id, e.paid_rupees * 100, least(e.spent_on + case when e.pstatus = 'PARTIAL' then 1 else 0 end, current_date), e.method
  from t_exp e where e.paid_rupees > 0;
  insert into expense_payments (id, expense_id, facility_id, amount_minor, paid_on, payment_method, reference, created_by, created_at)
  select id, exp_id, v_facility, amount, paid_on, method, 'SEED2Y', v_owner, paid_on::timestamp at time zone v_tz from t_expp;
  insert into seed2y_log select 'expense_payments', id from t_expp;

  -- ───────────────────────── 9. daily closings (last 60 days) ────────────
  declare
    d date; v_open int := 500000; v_cash int; v_upi int; v_card int; v_onl int; v_bank int; v_oth int; v_tot int; v_cexp int; v_texp int; v_expc int;
    v_act int; v_var int; v_id uuid; v_h int; v_status text;
  begin
    for d in select g::date from generate_series((current_date - 60)::timestamp, current_date::timestamp, interval '1 day') g loop
      v_h := seed2y_h('dc' || d);
      continue when d < current_date and v_h % 100 < 4;            -- a few days nobody closed
      select coalesce(sum(case when finance_method_bucket(p.payment_method) = 'CASH' then p.amount_inr * 100 end), 0),
             coalesce(sum(case when finance_method_bucket(p.payment_method) = 'UPI' then p.amount_inr * 100 end), 0),
             coalesce(sum(case when finance_method_bucket(p.payment_method) = 'CARD' then p.amount_inr * 100 end), 0),
             coalesce(sum(case when finance_method_bucket(p.payment_method) = 'ONLINE' then p.amount_inr * 100 end), 0),
             coalesce(sum(case when finance_method_bucket(p.payment_method) = 'BANK_TRANSFER' then p.amount_inr * 100 end), 0),
             coalesce(sum(case when finance_method_bucket(p.payment_method) = 'OTHER' then p.amount_inr * 100 end), 0),
             coalesce(sum(p.amount_inr * 100), 0)
        into v_cash, v_upi, v_card, v_onl, v_bank, v_oth, v_tot
        from payments p
       where p.facility_id = v_facility and p.status = 'paid'
         and (coalesce(p.paid_at, p.created_at) at time zone v_tz)::date = d;
      select coalesce(sum(case when finance_method_bucket(ep.payment_method) = 'CASH' then ep.amount_minor end), 0), coalesce(sum(ep.amount_minor), 0)
        into v_cexp, v_texp
        from expense_payments ep join expenses e on e.id = ep.expense_id
       where ep.facility_id = v_facility and e.status = 'RECORDED' and ep.paid_on = d;
      v_expc := v_open + v_cash - v_cexp;
      v_id := gen_random_uuid();
      if d = current_date then
        insert into daily_closings (id, facility_id, closing_date, opening_cash_minor, status, opened_by, opened_at)
        values (v_id, v_facility, d, v_open, 'OPEN', v_owner, now());
      else
        v_var := case when v_h % 100 < 70 then 0 else ((v_h % 7) - 3) * 5000 end;
        v_act := greatest(v_expc + v_var, 0);
        v_var := v_act - v_expc;
        v_status := case when v_h % 100 between 70 and 72 then 'REOPENED' else 'CLOSED' end;
        insert into daily_closings (id, facility_id, closing_date, opening_cash_minor, cash_collected_minor, upi_collected_minor, card_collected_minor, online_collected_minor,
                                    bank_transfer_collected_minor, other_collected_minor, total_collected_minor, cash_expense_minor, total_expense_minor, expected_cash_minor,
                                    actual_cash_minor, variance_minor, variance_reason, status, opened_by, opened_at, closed_by, closed_at, reopened_by, reopened_at, reopen_reason)
        values (v_id, v_facility, d, v_open, v_cash, v_upi, v_card, v_onl, v_bank, v_oth, v_tot, v_cexp, v_texp, v_expc, v_act, v_var,
                case when v_var <> 0 then 'Counted differently at close' end, v_status, v_owner, (d::timestamp + interval '6 hours') at time zone v_tz,
                v_owner, (d::timestamp + interval '22 hours 30 minutes') at time zone v_tz,
                case when v_status = 'REOPENED' then v_owner end, case when v_status = 'REOPENED' then (d::timestamp + interval '23 hours') at time zone v_tz end,
                case when v_status = 'REOPENED' then 'Late cash entry' end);
        v_open := v_act;
      end if;
      insert into seed2y_log values ('daily_closings', v_id);
    end loop;
  end;

  -- ───────────────────────── done ────────────────────────────────────────
  raise notice 'SEED COMPLETE for facility % (%).', v_facility, case when v_created_fac then 'created by this script' else 'existing, empty facility' end;
  raise notice 'bookings=% payments=% memberships=% members=% enrollments=% coaching sessions=% expenses=%',
    (select count(*) from t_bk), (select count(*) from seed2y_log where tbl = 'payments'), (select count(*) from t_ms), (select count(*) from t_members),
    (select count(*) from t_en0), (select count(*) from t_cs), (select count(*) from t_exp);
end
$seed$;
