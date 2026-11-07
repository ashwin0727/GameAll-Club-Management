-- ═══════════════════════════════════════════════════════════════════════════
-- Player app: the payment progress → payment success flow.
--
--   get_my_payment_receipt(p_kind, p_id)   signed-in player: what a membership / coaching enrolment / booking of THEIRS has paid so far,
--                                          and everything the "Payment Successful" page and its PDF receipt show.
--
--   p_kind  'membership' | 'coaching' | 'booking'      p_id  the id of that membership / enrolment / booking
--
-- The app calls it while the player is on the payment page: it asks again every few seconds until state is PAID (then the success page
-- opens) or FAILED (then it offers a retry). It returns NULL for anything that is not the caller's own, or does not exist.
--
--   state   PAID     paid in full, or nothing is owed, or the AutoPay / payment-link mandate is approved
--           PENDING  not paid yet
--           FAILED   a payment failed, AutoPay is halted, or the payment link ran out
--   Same rules as Home's prompts (0177), so the two never disagree.
--
-- Nothing is stored; it only reads memberships, plans, batches, coaching enrolments, programmes, coaches, bookings, courts, payments,
-- AutoPay / billing rows and the venue.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_my_payment_receipt(p_kind text, p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_phone   text;
  v_people  uuid[];
  v_guests  uuid[];
  r         record;
  p         record;
  v_total   bigint;
  v_paid    bigint;
  v_state   text;
  v_autopay boolean := false;
  v_sub     text;
  v_pay     record;
  v_ref     text;
  v_receipt text;
begin
  if v_uid is null or p_id is null then return null; end if;
  select pl.phone into v_phone from players pl where pl.id = v_uid;
  select coalesce(array_agg(x.id), '{}') into v_people
    from (select m.id from members m where (v_phone is not null and normalize_phone(m.phone) = v_phone) or m.user_id = v_uid
          union select v_uid) x;
  select coalesce(array_agg(g.id), '{}') into v_guests from guest_players g where v_phone is not null and normalize_phone(g.phone) = v_phone;

  -- ───────────── membership ─────────────
  if lower(p_kind) = 'membership' then
    select ms.*, coalesce(nullif(trim(ms.name), ''), mp.name, 'Membership') as plan_name, mp.features as plan_features, mp.description as plan_description,
           f.name as venue_name, f.area as venue_area, f.city as venue_city, f.business_phone as venue_phone,
           coalesce((select i.url from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED' order by i.sort_order, i.created_at limit 1), f.hero_image_url) as venue_image,
           (select count(*) from memberships x where x.facility_id = ms.facility_id and (x.created_at, x.id) <= (ms.created_at, ms.id)) as venue_seq
      into r
      from memberships ms
      left join membership_plans mp on mp.id = ms.plan_id
      join facilities f on f.id = ms.facility_id
     where ms.id = p_id and ms.member_id = any (v_people);
    if not found then return null; end if;

    v_total := coalesce(r.total_amount_inr, 0);
    select coalesce(sum(py.amount_inr), 0) into v_paid from payments py where py.membership_id = r.id and py.status = 'paid';
    -- a membership started in the Player app has only a plan price: what is owed is then the open payment row
    v_total := greatest(v_total, coalesce((select max(py.amount_inr) from payments py where py.membership_id = r.id and py.status in ('created', 'failed')), 0));
    select s.status::text into v_sub from membership_subscriptions s where s.membership_id = r.id;
    v_autopay := v_sub is not null;
    v_state := case
      when v_sub in ('halted', 'pending') then 'FAILED'
      when v_total <= 0 or v_paid >= v_total or v_sub in ('authenticated', 'active', 'completed') then 'PAID'
      when exists (select 1 from payments py where py.membership_id = r.id and py.status = 'failed') then 'FAILED'
      else 'PENDING' end;
    select py.id, py.payment_method, py.paid_at, coalesce(py.reference, py.razorpay_payment_id) as reference into v_pay
      from payments py where py.membership_id = r.id and py.status = 'paid' order by py.paid_at desc nulls last limit 1;
    v_receipt := 'RCP-' || upper(substr(replace(coalesce(v_pay.id, r.id)::text, '-', ''), 1, 8));

    return jsonb_build_object(
      'kind', 'membership', 'id', r.id, 'state', v_state, 'currency', 'INR',
      'totalInr', v_total, 'paidInr', v_paid, 'balanceInr', greatest(v_total - v_paid, 0),
      'amountInr', case when v_paid > 0 then v_paid else v_total end,
      'receiptNo', v_receipt, 'method', case when v_autopay then 'UPI AutoPay' else v_pay.payment_method end,
      'reference', v_pay.reference, 'paidAt', coalesce(v_pay.paid_at, case when v_state = 'PAID' then now() end), 'autopay', v_autopay, 'autopayStatus', v_sub,
      'title', r.plan_name,
      'venue', jsonb_build_object('id', r.facility_id, 'name', r.venue_name, 'area', r.venue_area, 'city', r.venue_city, 'phone', nullif(trim(coalesce(r.venue_phone, '')), ''), 'imageUrl', r.venue_image),
      'details', jsonb_build_object(
        'membershipRef', 'MBR-' || upper(left(coalesce(nullif(regexp_replace(r.venue_name, '[^A-Za-z]', '', 'g'), ''), 'GAM'), 3)) || '-' || lpad(r.venue_seq::text, 6, '0'),
        'planName', r.plan_name, 'durationDays', coalesce(r.duration_days, (select mp2.duration_days from membership_plans mp2 where mp2.id = r.plan_id)),
        'startDate', r.start_date, 'endDate', r.end_date, 'features', coalesce(to_jsonb(r.plan_features), '[]'::jsonb),
        'slot', (
          select jsonb_build_object('batchName', b.name, 'sport', b.sport, 'court', b.court, 'daysOfWeek', to_jsonb(b.days_of_week),
                                    'startTime', to_char(b.start_time, 'HH24:MI'), 'endTime', to_char(b.end_time, 'HH24:MI'))
            from (
              select mb.name, mb.days_of_week, mb.start_time, mb.end_time, c.name as court, coalesce(fs.custom_sport_name, sp.name) as sport
                from membership_batch_members bm
                join membership_batches mb on mb.id = bm.batch_id
                left join courts c on c.id = mb.court_id
                left join facility_sports fs on fs.id = mb.facility_sport_id
                left join sports sp on sp.id = fs.sport_id
               where bm.member_id = r.member_id and (bm.membership_id = r.id or bm.membership_id is null)
               order by (bm.membership_id = r.id) desc, bm.created_at desc limit 1
            ) b)));
  end if;

  -- ───────────── coaching enrolment ─────────────
  if lower(p_kind) = 'coaching' then
    select e.*, cp.name as program_name, cp.level as program_level, cp.program_type, cp.sessions_per_week,
           coalesce(fs.custom_sport_name, sp.name) as sport_name,
           f.name as venue_name, f.area as venue_area, f.city as venue_city, f.business_phone as venue_phone,
           coalesce((select i.url from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED' order by i.sort_order, i.created_at limit 1), f.hero_image_url) as venue_image,
           (select b.status from coaching_enrollment_billing b where b.enrollment_id = e.id) as bill_status,
           (select b.amount_minor from coaching_enrollment_billing b where b.enrollment_id = e.id) as bill_amount,
           (select pr.full_name from coaches co join profiles pr on pr.id = co.user_id where co.id = coalesce(e.coach_id, (select pb.coach_id from coaching_program_batches pb where pb.id = e.batch_id))) as coach_name
      into r
      from coaching_enrollments e
      join coaching_programs cp on cp.id = e.program_id
      left join facility_sports fs on fs.id = cp.facility_sport_id
      left join sports sp on sp.id = fs.sport_id
      join facilities f on f.id = e.facility_id
     where e.id = p_id and e.member_id = any (v_people);
    if not found then return null; end if;

    -- what is being paid NOW: one charge. A monthly (AutoPay) programme's enrolment price is the fee of the whole programme
    -- (3 months = 3 x 2,999), but the player pays 2,999 a month, so that is the figure to show.
    v_total := coalesce(case when r.fee_type = 'MONTHLY' then r.bill_amount end, r.price_minor) / 100;
    select coalesce(sum(py.amount_inr), 0) into v_paid from payments py where py.coaching_enrollment_id = r.id and py.status = 'paid';
    v_autopay := r.fee_type = 'MONTHLY';
    v_state := case
      when r.bill_status in ('HALTED', 'PENDING', 'EXPIRED', 'CANCELLED') then 'FAILED'
      when v_total <= 0 or v_paid >= v_total or r.bill_status in ('AUTHENTICATED', 'ACTIVE', 'PAID', 'COMPLETED') then 'PAID'
      when exists (select 1 from payments py where py.coaching_enrollment_id = r.id and py.status = 'failed') then 'FAILED'
      else 'PENDING' end;
    select py.id, py.payment_method, py.paid_at, coalesce(py.reference, py.razorpay_payment_id) as reference into v_pay
      from payments py where py.coaching_enrollment_id = r.id and py.status = 'paid' order by py.paid_at desc nulls last limit 1;
    v_receipt := 'RCP-' || upper(substr(replace(coalesce(v_pay.id, r.id)::text, '-', ''), 1, 8));

    return jsonb_build_object(
      'kind', 'coaching', 'id', r.id, 'state', v_state, 'currency', 'INR',
      'totalInr', v_total, 'paidInr', v_paid, 'balanceInr', greatest(v_total - v_paid, 0),
      'amountInr', case when v_paid > 0 then v_paid else v_total end,
      'receiptNo', v_receipt, 'method', case when v_autopay and v_paid = 0 then 'UPI AutoPay' else v_pay.payment_method end,
      'reference', v_pay.reference, 'paidAt', coalesce(v_pay.paid_at, case when v_state = 'PAID' then now() end), 'autopay', v_autopay, 'autopayStatus', r.bill_status,
      'title', r.program_name,
      'venue', jsonb_build_object('id', r.facility_id, 'name', r.venue_name, 'area', r.venue_area, 'city', r.venue_city, 'phone', nullif(trim(coalesce(r.venue_phone, '')), ''), 'imageUrl', r.venue_image),
      'details', jsonb_build_object(
        'programName', r.program_name, 'level', r.program_level, 'sport', r.sport_name, 'programType', r.program_type, 'feeType', r.fee_type,
        'coach', r.coach_name, 'startDate', r.start_date, 'endDate', r.end_date, 'sessionsPerWeek', r.sessions_per_week,
        'batch', (select jsonb_build_object('name', b.name, 'daysOfWeek', to_jsonb(b.days_of_week), 'startTime', to_char(b.start_time, 'HH24:MI'), 'endTime', to_char(b.end_time, 'HH24:MI'))
                    from coaching_program_batches b where b.id = r.batch_id)));
  end if;

  -- ───────────── booking ─────────────
  if lower(p_kind) = 'booking' then
    select b.*, c.name as court_name, coalesce(fs.custom_sport_name, sp.name) as sport_name,
           f.name as venue_name, f.area as venue_area, f.city as venue_city, f.business_phone as venue_phone,
           coalesce((select i.url from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED' order by i.sort_order, i.created_at limit 1), f.hero_image_url) as venue_image
      into r
      from bookings b
      join facilities f on f.id = b.facility_id
      left join courts c on c.id = b.court_id
      left join facility_sports fs on fs.id = c.facility_sport_id
      left join sports sp on sp.id = c.sport_id
     where b.id = p_id
       and (b.member_id = any (v_people)
            or b.guest_player_id = any (v_guests)
            or (b.customer_type = 'GUEST' and v_phone is not null and normalize_phone(b.guest_phone) = v_phone));
    if not found then return null; end if;

    v_total := coalesce(r.amount_minor, 0) / 100;
    select coalesce(sum(py.amount_inr), 0) into v_paid from payments py where py.booking_id = r.id and py.status = 'paid';
    v_state := case
      -- a booking is paid once its payment (the full amount, or the 50% advance that secures a booking over an hour) is in
      when r.payment_status = 'PAID' or (v_total > 0 and v_paid >= v_total) or v_total <= 0
           or (v_paid > 0 and (r.payment_status::text = 'PARTIALLY_PAID' or r.status::text = 'confirmed'))
           or exists (select 1 from payment_orders po where po.booking_id = r.id and po.status::text in ('CAPTURED', 'COMPLETED', 'SETTLEMENT_EXCEPTION')) then 'PAID'
      when exists (select 1 from payments py where py.booking_id = r.id and py.status = 'failed') then 'FAILED'
      else 'PENDING' end;
    select py.id, py.amount_inr, py.payment_method, py.paid_at, coalesce(py.reference, py.razorpay_payment_id) as reference into v_pay
      from payments py where py.booking_id = r.id and py.status = 'paid' order by py.paid_at desc nulls last limit 1;
    v_receipt := 'RCP-' || upper(substr(replace(coalesce(v_pay.id, r.id)::text, '-', ''), 1, 8));

    return jsonb_build_object(
      'kind', 'booking', 'id', r.id, 'state', v_state, 'currency', 'INR',
      'totalInr', v_total, 'paidInr', v_paid, 'balanceInr', greatest(v_total - v_paid, 0),
      'amountInr', coalesce(v_pay.amount_inr, v_total), -- the payment just made (the advance, then the balance), not the running total
      'receiptNo', v_receipt, 'method', v_pay.payment_method, 'reference', v_pay.reference,
      'paidAt', coalesce(v_pay.paid_at, case when v_state = 'PAID' then now() end), 'autopay', false, 'autopayStatus', null,
      'title', coalesce(r.sport_name, 'Court') || ' booking',
      'venue', jsonb_build_object('id', r.facility_id, 'name', r.venue_name, 'area', r.venue_area, 'city', r.venue_city, 'phone', nullif(trim(coalesce(r.venue_phone, '')), ''), 'imageUrl', r.venue_image),
      'details', jsonb_build_object(
        'bookingRef', 'GBK-' || upper(left(coalesce(nullif(regexp_replace(r.venue_name, '[^A-Za-z]', '', 'g'), ''), 'GAM'), 3)) || '-' || upper(substr(replace(r.id::text, '-', ''), 1, 5)),
        'court', r.court_name, 'sport', r.sport_name, 'startTime', r.start_time, 'endTime', r.end_time, 'status', r.status::text,
        'players', r.party_size));
  end if;

  return null;
end;
$$;
revoke all on function get_my_payment_receipt(text, uuid) from public, anon;
grant execute on function get_my_payment_receipt(text, uuid) to authenticated;
