-- ═════════════════════════════════════════════════════════════════════
-- PLAY STORE SCREENSHOT DATA — makes the demo venue look like a real, busy, approved venue, and fills the test PLAYER's login
-- (9360428761) with bookings, memberships and coaching at the demo venue and at the extra Chennai venues.
-- Run it AFTER seed_2y_facility_dataset.sql, and (for the extra venues) after seed_playstore_venues.sql.
--
-- NOT a migration. Run by hand in the Supabase SQL editor (use a TEST project / Razorpay test mode, never your live data).
--
-- WHAT IT DOES
--   1. Venue "Smash Arena Sports Hub" (Adyar, Chennai): a proper description, phone, indoor venue, all five amenities, the map link and the
--      photos marked VERIFIED, and the setup marked APPROVED, so GameAll lists it with photos and amenities.
--   2. The player (v_player_phone) is added as a customer at Smash Arena and at the extra Chennai venues (if you created them) and gets:
--        Smash Arena:   3 upcoming PAID bookings, 1 upcoming booking with the balance still to pay, 4 past completed bookings,
--                       1 cancelled booking that was refunded, an active paid membership (with its batch and timings), an older expired
--                       membership, a monthly coaching enrolment on Auto Pay with attendance, and a one-time coaching enrolment, fully paid.
--        Other venues:  1 upcoming paid booking and 1 past booking each; the first two also an active paid membership.
--   3. Everything it inserts is written to seed2y_log, so cleanup_2y_facility_dataset.sql removes it with the rest.
--
-- BEFORE YOU RUN IT
--   a. Run seed_2y_facility_dataset.sql first (the Venue app screenshots: bookings, members, coaching, finance, reports come from it).
--   b. In GameAll Venue, open Profile > Facility > Photos and upload 3 to 4 REAL photos of a court (you may use free-licence or
--      your own photos). This script cannot create photos. It only marks the ones you uploaded as verified.
--   c. Sign in once to GameAll with the test number (v_player_phone) so that player exists, and give it a name.
--   d. Optional: run seed_playstore_venues.sql so the player also has data at the extra venues. Then run THIS file after it.
--   e. Check the three values just below.
--
-- NOTES ON PRIVACY
--   Every name below is made up, and the phone numbers are placeholders. Do not put a real customer's name or number in a screenshot.
-- ═════════════════════════════════════════════════════════════════════

do $shots$
declare
  v_owner_email  text := 'ashwinv277@gmail.com';   -- ← the account that owns the demo venue
  v_player_phone text := '9000012345';             -- ← the test player's 10-digit phone ('' = skip the player part)
  v_player_name  text := 'Karthik Subramanian';    -- ← used only if the player has not given a name in the app yet

  v_tz        constant text := 'Asia/Kolkata';
  v_today     date := (now() at time zone 'Asia/Kolkata')::date;
  v_owner     uuid;
  v_facility  uuid;
  v_others    uuid[] := '{}';
  v_vid       uuid;
  v_vowner    uuid;
  v_member    uuid;
  v_ms        uuid;
  v_plan      uuid;
  v_batch     uuid;
  v_court     uuid;
  v_court2    uuid;
  v_bk        uuid;
  v_po        uuid;
  v_pay       uuid;
  v_prog      uuid;
  v_cb        uuid;
  v_en        uuid;
  v_billing   uuid;
  v_n         integer;
  v_idx       integer := 0;
  v_pst       date;
  v_pen       date;
  v_cycles    integer;
  v_price     integer;
  r           record;
  b           record;
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
  -- use the name the player gave in the app, if there is one
  select coalesce((select full_name from players where phone = normalize_phone(v_player_phone) limit 1), v_player_name) into v_player_name;

  -- the venues: Smash Arena first (index 0), then the extra Chennai venues if seed_playstore_venues.sql was run
  if to_regclass('seedvenues_log') is not null then
    execute 'select coalesce(array_agg(id), ''{}''::uuid[]) from seedvenues_log where tbl = ''facilities''' into v_others;
  end if;

  for r in select u.vid, u.ord from unnest(array[v_facility] || v_others) with ordinality as u(vid, ord) order by u.ord loop
    v_vid := r.vid;
    v_idx := r.ord::int - 1;
    select owner_id into v_vowner from facilities where id = v_vid;

    if exists (select 1 from members where facility_id = v_vid and normalize_phone(phone) = normalize_phone(v_player_phone)) then
      raise notice 'The player already has a record at venue %, so nothing was added there again.', v_vid;
      continue;
    end if;
    select id, hourly_rate_inr into v_court, v_price from courts where facility_id = v_vid and not archived and status = 'ACTIVE' order by display_order, name limit 1;
    if v_court is null then continue; end if;

    insert into members (facility_id, full_name, phone, status) values (v_vid, v_player_name, v_player_phone, 'ACTIVE') returning id into v_member;
    insert into seed2y_log values ('members', v_member);

    -- ── bookings: upcoming paid, one with the balance still to pay (Smash only), past completed, one cancelled and refunded ──
    for b in
      select * from (values (2, 18, 'confirmed', 'PAID'), (4, 19, 'confirmed', 'PAID'), (8, 7, 'confirmed', 'PAID'), (3, 20, 'confirmed', 'PENDING'),
                            (-2, 18, 'completed', 'PAID'), (-5, 19, 'completed', 'PAID'), (-9, 18, 'completed', 'PAID'), (-14, 7, 'completed', 'PAID'),
                            (-20, 19, 'cancelled', 'REFUNDED')) t(d, h, st, ps) where v_idx = 0
      union all
      select * from (values (2 + v_idx, 18, 'confirmed', 'PAID'), (-3 - v_idx, 19, 'completed', 'PAID')) t2(d, h, st, ps) where v_idx > 0
    loop
      -- a court of this venue that is free at that hour (the demo data already fills many slots)
      select c.id into v_court2 from courts c
       where c.facility_id = v_vid and not c.archived and c.status = 'ACTIVE'
         and not exists (select 1 from bookings x where x.court_id = c.id and x.status <> 'cancelled'
                           and tstzrange(x.start_time, x.end_time) && tstzrange(((v_today + b.d) + make_time(b.h, 0, 0)) at time zone v_tz, ((v_today + b.d) + make_time(b.h + 1, 0, 0)) at time zone v_tz))
       order by c.display_order, c.name limit 1;
      continue when v_court2 is null;

      insert into bookings (facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status,
                            amount_minor, currency, payment_status, notes, party_size, payment_method, created_by)
      values (v_vid, v_court2, 'GUEST', v_player_name, v_player_phone,
              ((v_today + b.d) + make_time(b.h, 0, 0)) at time zone v_tz, ((v_today + b.d) + make_time(b.h + 1, 0, 0)) at time zone v_tz,
              b.st::booking_status, v_price * 100, 'INR', b.ps, 'SEED2Y', 2, case when b.ps = 'PENDING' then null else 'UPI' end, v_vowner)
      returning id into v_bk;
      insert into seed2y_log values ('bookings', v_bk);

      if b.ps = 'PAID' then
        insert into payments (facility_id, booking_id, amount_inr, status, payment_method, paid_at)
        values (v_vid, v_bk, v_price, 'paid'::payment_status, 'UPI', ((v_today + b.d) + make_time(b.h, 0, 0)) at time zone v_tz - interval '2 days')
        returning id into v_pay;
        insert into seed2y_log values ('payments', v_pay);
      elsif b.ps = 'REFUNDED' then
        v_po := gen_random_uuid();
        insert into payment_orders (id, facility_id, source_type, booking_id, amount_minor, currency, status, receipt, expires_at, created_by, created_at)
        values (v_po, v_vid, 'GUEST_BOOKING'::payment_source_type, v_bk, v_price * 100, 'INR', 'PARTIALLY_REFUNDED'::payment_order_status,
                'seed2y-pl-' || substr(v_po::text, 1, 8), now(), v_vowner, now() - interval '22 days');
        insert into seed2y_log values ('payment_orders', v_po);
        insert into payments (facility_id, booking_id, payment_order_id, amount_inr, status, payment_method, paid_at)
        values (v_vid, v_bk, v_po, v_price, 'paid'::payment_status, 'UPI', now() - interval '22 days') returning id into v_pay;
        insert into seed2y_log values ('payments', v_pay);
        insert into refunds (id, facility_id, payment_order_id, transaction_id, source_type, source_id, razorpay_payment_id, razorpay_refund_id, amount_minor,
                             currency, reason, status, is_override, policy_percent_applied, initiated_by, created_at, processed_at)
        values (gen_random_uuid(), v_vid, v_po, v_pay, 'GUEST_BOOKING'::payment_source_type, v_bk, 'pay_seed2y_pl_' || substr(v_po::text, 1, 6),
                'rfnd_seed2y_pl_' || substr(v_po::text, 1, 6), v_price * 95, 'INR', 'CUSTOMER_CANCELLATION'::refund_reason, 'PROCESSED'::refund_status, false, 95,
                v_vowner, now() - interval '21 days', now() - interval '20 days')
        returning id into v_pay;
        insert into seed2y_log values ('refunds', v_pay);
      end if;
    end loop;

    -- ── memberships ──────────────────────────────────────────────────────────
    for b in
      select * from (values ('Badminton Monthly', 'active', -10, 20, true), ('Badminton Quarterly', 'expired', -120, -30, false)) t(pname, pst, so, eo, withbatch) where v_idx = 0
      union all
      select * from (values ('Monthly Pass', 'active', -8, 22, false)) t2(pname, pst, so, eo, withbatch) where v_idx in (1, 2)
    loop
      select id, price_inr into v_plan, v_n from membership_plans where facility_id = v_vid and name = b.pname limit 1;
      continue when v_plan is null;
      insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date, auto_renew, created_by, monthly_price_inr, name,
                               membership_type, duration_days, membership_fee_inr, registration_fee_inr, gst_percent, total_amount_inr)
      values (v_vid, v_member, v_plan, b.pst::membership_status, v_today + b.so, v_today + b.eo, false, v_vowner, v_n, b.pname,
              'INDIVIDUAL', b.eo - b.so, v_n, 0, 0, v_n)
      returning id into v_ms;
      insert into seed2y_log values ('memberships', v_ms);
      insert into payments (facility_id, member_id, membership_id, amount_inr, status, payment_method, paid_at)
      values (v_vid, v_member, v_ms, v_n, 'paid'::payment_status, 'UPI', (v_today + b.so)::timestamp at time zone v_tz) returning id into v_pay;
      insert into seed2y_log values ('payments', v_pay);

      -- the active Smash membership sits in the evening batch, so its days and timings show in the app
      if b.withbatch then
        select id into v_batch from membership_batches where facility_id = v_vid and name = 'Badminton Evening Batch' limit 1;
        if v_batch is not null then
          begin
            alter table membership_batch_members disable trigger membership_batch_members_eligible;
            insert into membership_batch_members (id, batch_id, member_id, membership_id) values (gen_random_uuid(), v_batch, v_member, v_ms) returning id into v_pay;
            insert into seed2y_log values ('membership_batch_members', v_pay);
            alter table membership_batch_members enable trigger membership_batch_members_eligible;
          exception when others then
            raise notice 'Batch link skipped: %', sqlerrm;
            alter table membership_batch_members enable trigger membership_batch_members_eligible;
          end;
        end if;
      end if;
    end loop;

    -- ── coaching (Smash only): one monthly programme on Auto Pay with attendance, one one-time programme paid in full ──
    if v_idx = 0 then
      for b in
        select * from (values ('Badminton Junior Academy', 'MONTHLY'), ('Pickleball Starter Program', 'ONE_TIME')) t(pname, fee)
      loop
        select p.id, p.default_price_minor, p.start_date, p.end_date into v_prog, v_price, v_pst, v_pen
          from coaching_programs p where p.facility_id = v_vid and p.name = b.pname limit 1;
        continue when v_prog is null;
        select id into v_cb from coaching_program_batches where program_id = v_prog and status = 'ACTIVE' limit 1;
        v_pst := greatest(v_pst, v_today - 40);
        v_cycles := case when b.fee = 'MONTHLY' then coaching_billing_cycles(v_pst, v_pen) else 1 end;

        insert into coaching_enrollments (id, facility_id, member_id, program_id, batch_id, start_date, end_date, price_minor, pricing_type, status, notes,
                                          created_by, fee_type, billing_cycles)
        values (gen_random_uuid(), v_vid, v_member, v_prog, v_cb, v_pst, v_pen, v_price * v_cycles, 'STANDARD', 'ACTIVE', 'SEED2Y', v_vowner, b.fee, v_cycles)
        returning id into v_en;
        insert into seed2y_log values ('coaching_enrollments', v_en);

        insert into payments (facility_id, member_id, coaching_enrollment_id, amount_inr, status, payment_method, paid_at)
        values (v_vid, v_member, v_en, v_price / 100, 'paid'::payment_status, 'UPI', v_pst::timestamp at time zone v_tz) returning id into v_pay;
        insert into seed2y_log values ('payments', v_pay);

        if b.fee = 'MONTHLY' then
          v_billing := gen_random_uuid();
          insert into coaching_enrollment_billing (id, enrollment_id, facility_id, kind, status, amount_minor, total_cycles, charge_count, razorpay_subscription_id,
                                                    razorpay_plan_id, current_start, current_end, created_by)
          values (v_billing, v_en, v_vid, 'SUBSCRIPTION', 'ACTIVE', v_price, v_cycles, 1, 'sub_seed2y_pl_' || substr(v_en::text, 1, 8), 'plan_seed2y_pl', v_pst, (v_pst + interval '1 month')::date, v_vowner);
          insert into seed2y_log values ('coaching_enrollment_billing', v_billing);
        end if;

        -- attendance on the sessions that already took place
        with ins as (
          insert into coaching_session_students (id, session_id, enrollment_id, facility_id, status, added_by, added_at)
          select gen_random_uuid(), s.id, v_en, v_vid, 'ENROLLED', v_vowner, s.start_at - interval '1 day'
            from coaching_sessions s
           where s.program_id = v_prog and s.status = 'COMPLETED' and s.start_at >= v_pst::timestamp at time zone v_tz and s.start_at < now()
           order by s.start_at desc limit 8
          returning id)
        insert into seed2y_log select 'coaching_session_students', id from ins;
      end loop;
    end if;
  end loop;

  raise notice 'Done. Sign in to GameAll as % and check Home, My Bookings, Memberships and Coaching.', v_player_phone;
end
$shots$;
