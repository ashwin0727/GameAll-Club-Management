-- ═══════════════════════════════════════════════════════════════════════════
-- Player App: Coaching enrolment (sport → time slot → programme / coach → pay).
--
--   get_public_coaching_enroll(facility)          anon-safe: the venue's active coaching programmes, each with the batches (time
--                                                 slot, days, coach, seats left) the staff created, the fee model (ONE_TIME or
--                                                 MONTHLY), the amount of one charge, the number of charges and the dates
--   player_start_coaching_enroll(...)             signed-in player: creates (or resumes) the pending enrolment for a programme
--                                                 + batch, priced by the database (never by the app)
--   player_get_coaching_billing_context(id)       signed-in player: what create-player-coaching-billing needs, ownership-checked
--   player_record_coaching_billing(...)           signed-in player: saves the Razorpay link / subscription that function made
--   get_my_coaching_at(facility)                  signed-in player: their enrolments at this venue and whether they are paid
--
-- Money model is the one the club's own Add Student wizard already uses (0110):
--   ONE_TIME → price_minor = one fee,              paid once through a Razorpay Payment Link
--   MONTHLY  → price_minor = monthly fee × cycles, paid through a Razorpay Subscription (UPI AutoPay), cycles =
--              coaching_billing_cycles(start, programme end)
-- Settlement is unchanged: razorpay-webhook → record_coaching_gateway_payment writes the paid `payments` row.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- The amount of ONE charge for a programme, in paise: fee − early-bird discount (while it is valid) + tax, tax rounded to the
-- rupee like the club's wizard. 0 for a programme included in a membership.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function _coaching_program_charge_minor(p coaching_programs)
returns integer
language sql
stable
set search_path = public
as $$
  select case
    when p.is_membership_included then 0
    else (
      greatest(coalesce(p.default_price_minor, 0)
        - case when coalesce(p.early_bird_discount_minor, 0) > 0
                    and (p.discount_valid_till is null or p.discount_valid_till >= (now() at time zone 'Asia/Kolkata')::date)
               then p.early_bird_discount_minor else 0 end, 0)
      + case when coalesce(p.tax_percent, 0) > 0 then
          (round(greatest(coalesce(p.default_price_minor, 0)
            - case when coalesce(p.early_bird_discount_minor, 0) > 0
                        and (p.discount_valid_till is null or p.discount_valid_till >= (now() at time zone 'Asia/Kolkata')::date)
                   then p.early_bird_discount_minor else 0 end, 0) / 100.0 * p.tax_percent / 100.0) * 100)::integer
        else 0 end
    )
  end;
$$;
revoke all on function _coaching_program_charge_minor(coaching_programs) from public, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- What the Coaching page shows. Only programmes a club has made ACTIVE and that have not finished; only ACTIVE batches.
-- Coach name / photo come from the staff profile behind the coach, the rating from the coach's own rating (null until staff set it),
-- "sessions" is the number of sessions the coach has actually completed.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_public_coaching_enroll(p_facility_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with today as (select (now() at time zone 'Asia/Kolkata')::date as d),
  prog as (
    select cp.*,
           coalesce(fs.custom_sport_name, sp.name) as sport_name,
           greatest(coalesce(cp.start_date, t.d), t.d) as eff_start,
           _coaching_program_charge_minor(cp) as charge_minor
      from coaching_programs cp
      cross join today t
      left join facility_sports fs on fs.id = cp.facility_sport_id
      left join sports sp on sp.id = fs.sport_id
     where cp.facility_id = p_facility_id
       and cp.status = 'ACTIVE'
       and (cp.end_date is null or cp.end_date >= t.d)
  )
  select case when f.id is null then null else jsonb_build_object(
    'facilityId', f.id,
    'facilityName', f.name,
    'accepting', plan_has_feature(f.id, 'PLAYER_MEMBERSHIPS'),
    'autopayAvailable', plan_has_feature(f.id, 'AUTOPAY'),
    'sports', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name)
        from (select distinct cp.facility_sport_id as id, cp.sport_name as name from prog cp where cp.facility_sport_id is not null) s
    ), '[]'::jsonb),
    'programs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cp.id,
        'name', cp.name,
        'level', cp.level,
        'ageGroup', cp.age_group,
        'description', nullif(trim(coalesce(cp.description, '')), ''),
        'facilitySportId', cp.facility_sport_id,
        'sportName', cp.sport_name,
        'programType', cp.program_type,
        'feeType', cp.fee_type,
        'durationMinutes', cp.default_duration_minutes,
        'sessionsPerWeek', cp.sessions_per_week,
        'sessionCount', cp.session_count,
        'structure', to_jsonb(cp.program_structure),
        'imageUrl', cp.image_url,
        'baseMinor', coalesce(cp.default_price_minor, 0),
        'discountMinor', case when coalesce(cp.early_bird_discount_minor, 0) > 0
                                   and (cp.discount_valid_till is null or cp.discount_valid_till >= (select d from today))
                              then cp.early_bird_discount_minor else 0 end,
        'taxPercent', coalesce(cp.tax_percent, 0),
        'chargeMinor', cp.charge_minor,
        'cycles', case when cp.fee_type = 'MONTHLY' then coaching_billing_cycles(cp.eff_start, cp.end_date) else 1 end,
        'startDate', cp.eff_start,
        'endDate', cp.end_date,
        'enrollmentDeadline', cp.enrollment_deadline,
        'membershipIncluded', cp.is_membership_included,
        'paymentNotes', nullif(trim(coalesce(cp.payment_notes, '')), ''),
        'enrollmentOpen', (cp.enrollment_deadline is null or cp.enrollment_deadline >= (select d from today)),
        'onlinePayable', (cp.payment_mode <> 'OFFLINE' and cp.charge_minor > 0
                          and (cp.fee_type <> 'MONTHLY' or cp.end_date is not null)),
        'batches', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', b.id,
            'name', b.name,
            'daysOfWeek', b.days_of_week,
            'startTime', b.start_time,
            'endTime', b.end_time,
            'capacity', b.capacity,
            'enrolled', (select count(*) from coaching_enrollments e where e.batch_id = b.id and e.status in ('ACTIVE', 'PAUSED')),
            'coach', case when co.id is null then null else jsonb_build_object(
              'id', co.id,
              'name', coalesce(nullif(trim(pr.full_name), ''), 'Coach'),
              'avatarUrl', pr.avatar_url,
              'certifications', nullif(trim(coalesce(co.certifications, '')), ''),
              'specialization', nullif(trim(coalesce(co.specialization, '')), ''),
              'rating', co.rating,
              'sessions', (select count(*) from coaching_sessions cs where cs.coach_id = co.id and cs.status = 'COMPLETED')
            ) end
          ) order by b.start_time, b.name)
          from coaching_program_batches b
          left join coaches co on co.id = b.coach_id
          left join profiles pr on pr.id = co.user_id
          where b.program_id = cp.id and b.status = 'ACTIVE'
        ), '[]'::jsonb)
      ) order by cp.name)
      from prog cp
    ), '[]'::jsonb)
  ) end
  from (select 1) one
  left join facilities f on f.id = p_facility_id and f.status = 'ACTIVE' and f.onboarding_step = 'COMPLETED';
$$;
revoke all on function get_public_coaching_enroll(uuid) from public;
grant execute on function get_public_coaching_enroll(uuid) to anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Start (or resume) the signed-in player's enrolment. The club's student record is found by phone number (or made), the programme
-- and batch are checked, and the fee is worked out here. A player who backs out of the payment page and comes back gets the same
-- pending enrolment, not a second one; one who already paid (or set up AutoPay) is told they are enrolled.
-- Returns { enrollmentId, feeType, cycles, chargeMinor, totalMinor, resumed }.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function player_start_coaching_enroll(
  p_facility_id uuid,
  p_program_id uuid,
  p_batch_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me players;
  prog coaching_programs;
  v_batch coaching_program_batches;
  v_member_id uuid;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_start date;
  v_charge integer;
  v_cycles integer;
  v_enrollment coaching_enrollments;
  v_billing coaching_enrollment_billing;
  v_paid bigint;
  v_has_batches boolean;
  v_enrolled integer;
begin
  select * into me from players where id = auth.uid();
  if me.id is null then
    raise exception 'Sign in to join coaching.' using errcode = '42501';
  end if;
  if not plan_has_feature(p_facility_id, 'PLAYER_MEMBERSHIPS') then
    raise exception 'This club is not taking online enrolments.' using errcode = '42501';
  end if;

  select * into prog from coaching_programs
   where id = p_program_id and facility_id = p_facility_id and status = 'ACTIVE';
  if prog.id is null then
    raise exception 'That coaching programme is not available.' using errcode = '23503';
  end if;
  if prog.payment_mode = 'OFFLINE' or prog.is_membership_included then
    raise exception 'This programme is enrolled at the club.' using errcode = '23514';
  end if;
  if prog.enrollment_deadline is not null and prog.enrollment_deadline < v_today then
    raise exception 'Enrolment for this programme has closed.' using errcode = '23514';
  end if;
  if prog.end_date is not null and prog.end_date < v_today then
    raise exception 'This programme has already ended.' using errcode = '23514';
  end if;
  if prog.fee_type = 'MONTHLY' and prog.end_date is null then
    raise exception 'This programme is enrolled at the club.' using errcode = '23514';
  end if;

  v_charge := _coaching_program_charge_minor(prog);
  if v_charge <= 0 then
    raise exception 'This programme is enrolled at the club.' using errcode = '23514';
  end if;
  v_start := greatest(coalesce(prog.start_date, v_today), v_today);
  v_cycles := case when prog.fee_type = 'MONTHLY' then coaching_billing_cycles(v_start, prog.end_date) else 1 end;

  -- A programme with batches needs one; one without batches is joined without a slot.
  select exists (select 1 from coaching_program_batches where program_id = prog.id and status = 'ACTIVE') into v_has_batches;
  if v_has_batches and p_batch_id is null then
    raise exception 'Pick a time slot.' using errcode = '23514';
  end if;
  if p_batch_id is not null then
    select * into v_batch from coaching_program_batches
     where id = p_batch_id and program_id = prog.id and facility_id = p_facility_id;
    if v_batch.id is null or v_batch.status <> 'ACTIVE' then
      raise exception 'That time slot is not available.' using errcode = '23503';
    end if;
  end if;

  -- The club's student record for this phone number, or a new one.
  select m.id into v_member_id from members m
   where m.facility_id = p_facility_id and normalize_phone(m.phone) = normalize_phone(me.phone)
   order by m.created_at limit 1;
  if v_member_id is null then
    insert into members (facility_id, full_name, phone, email)
    values (p_facility_id, trim(me.full_name), trim(me.phone), nullif(trim(coalesce(me.email, '')), ''))
    returning id into v_member_id;
  end if;

  -- Already enrolled here?
  select * into v_enrollment from coaching_enrollments
   where facility_id = p_facility_id and member_id = v_member_id and program_id = prog.id and status in ('ACTIVE', 'PAUSED')
   limit 1;

  if v_enrollment.id is not null then
    select coalesce(sum(p.amount_inr) * 100, 0)::bigint into v_paid
      from payments p where p.coaching_enrollment_id = v_enrollment.id and p.status = 'paid';
    select * into v_billing from coaching_enrollment_billing where enrollment_id = v_enrollment.id;
    if v_paid > 0 or (v_billing.id is not null and v_billing.status in ('AUTHENTICATED', 'ACTIVE', 'PENDING', 'PAID', 'COMPLETED')) then
      raise exception 'You are already enrolled in this programme.' using errcode = '23505';
    end if;

    -- Unpaid and nothing live behind it: carry on with it, moved to the batch just picked.
    if p_batch_id is not null and v_enrollment.batch_id is distinct from p_batch_id then
      perform 1 from coaching_program_batches where id = p_batch_id for update;
      select count(*) into v_enrolled from coaching_enrollments
       where batch_id = p_batch_id and status in ('ACTIVE', 'PAUSED') and id <> v_enrollment.id;
      if v_enrolled >= v_batch.capacity then
        raise exception 'This batch is full.' using errcode = '23514';
      end if;
    end if;
    if v_billing.id is null or v_billing.status in ('CANCELLED', 'EXPIRED') then
      update coaching_enrollments
         set batch_id = coalesce(p_batch_id, batch_id),
             coach_id = coalesce(v_batch.coach_id, coach_id),
             start_date = v_start,
             price_minor = v_charge * v_cycles,
             billing_cycles = v_cycles,
             fee_type = prog.fee_type
       where id = v_enrollment.id;
    end if;
    return jsonb_build_object('enrollmentId', v_enrollment.id, 'feeType', prog.fee_type, 'cycles', v_cycles,
      'chargeMinor', v_charge, 'totalMinor', v_charge * v_cycles, 'resumed', true);
  end if;

  -- A new enrolment. The batch row is locked so two players cannot both take its last seat.
  if p_batch_id is not null then
    perform 1 from coaching_program_batches where id = p_batch_id for update;
    select count(*) into v_enrolled from coaching_enrollments where batch_id = p_batch_id and status in ('ACTIVE', 'PAUSED');
    if v_enrolled >= v_batch.capacity then
      raise exception 'This batch is full.' using errcode = '23514';
    end if;
  end if;

  begin
    insert into coaching_enrollments (
      facility_id, member_id, program_id, coach_id, start_date, sessions_total, price_minor, pricing_type, batch_id, notes
    ) values (
      p_facility_id, v_member_id, prog.id, v_batch.coach_id, v_start, prog.session_count,
      v_charge * v_cycles, 'STANDARD', p_batch_id, 'Enrolled from the Player app'
    ) returning * into v_enrollment;
  exception when unique_violation then
    raise exception 'You are already enrolled in this programme.' using errcode = '23505';
  end;

  return jsonb_build_object('enrollmentId', v_enrollment.id, 'feeType', v_enrollment.fee_type, 'cycles', v_enrollment.billing_cycles,
    'chargeMinor', v_charge, 'totalMinor', v_enrollment.price_minor, 'resumed', false);
end;
$$;
revoke all on function player_start_coaching_enroll(uuid, uuid, uuid) from public, anon;
grant execute on function player_start_coaching_enroll(uuid, uuid, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- The enrolment belongs to the signed-in player when its student's phone number is theirs.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function _player_coaching_enrollment(p_enrollment_id uuid)
returns coaching_enrollments
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  e coaching_enrollments;
begin
  select e2.* into e
    from coaching_enrollments e2
    join members m on m.id = e2.member_id
    join players pl on pl.id = auth.uid() and normalize_phone(pl.phone) = normalize_phone(m.phone)
   where e2.id = p_enrollment_id;
  if e.id is null then
    raise exception 'Enrollment not found.' using errcode = 'P0002';
  end if;
  return e;
end;
$$;
revoke all on function _player_coaching_enrollment(uuid) from public, anon, authenticated;


-- Same shape as get_coaching_billing_context (0110), for the player who owns the enrolment instead of staff.
create or replace function player_get_coaching_billing_context(p_enrollment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  e coaching_enrollments;
  prog coaching_programs;
  m members;
  b coaching_enrollment_billing;
  v_paid bigint;
begin
  e := _player_coaching_enrollment(p_enrollment_id);
  select * into prog from coaching_programs where id = e.program_id;
  select * into m from members where id = e.member_id;
  select * into b from coaching_enrollment_billing where enrollment_id = e.id;
  select coalesce(sum(p.amount_inr) * 100, 0)::bigint into v_paid
    from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid';

  return jsonb_build_object(
    'enrollmentId', e.id,
    'facilityId', e.facility_id,
    'status', e.status,
    'feeType', e.fee_type,
    'billingCycles', e.billing_cycles,
    'priceMinor', e.price_minor,
    'paidMinor', v_paid,
    'outstandingMinor', greatest(e.price_minor - v_paid, 0),
    'programName', prog.name,
    'startDate', e.start_date,
    'programEndDate', prog.end_date,
    'memberName', m.full_name,
    'memberPhone', m.phone,
    'memberEmail', m.email,
    'billing', case when b.id is null then null else jsonb_build_object(
      'kind', b.kind,
      'status', b.status,
      'amountMinor', b.amount_minor,
      'totalCycles', b.total_cycles,
      'chargeCount', b.charge_count,
      'razorpayPaymentLinkId', b.razorpay_payment_link_id,
      'razorpaySubscriptionId', b.razorpay_subscription_id,
      'shortUrl', b.short_url
    ) end
  );
end;
$$;
revoke all on function player_get_coaching_billing_context(uuid) from public, anon;
grant execute on function player_get_coaching_billing_context(uuid) to authenticated;


-- Same as record_coaching_enrollment_billing (0110), for the owning player. A dead (CANCELLED / EXPIRED) link is replaced.
create or replace function player_record_coaching_billing(
  p_enrollment_id uuid,
  p_kind text,
  p_amount_minor integer,
  p_total_cycles integer,
  p_payment_link_id text default null,
  p_plan_id text default null,
  p_subscription_id text default null,
  p_short_url text default null
) returns coaching_enrollment_billing
language plpgsql
security definer
set search_path = public
as $$
declare
  e coaching_enrollments;
  result coaching_enrollment_billing;
begin
  e := _player_coaching_enrollment(p_enrollment_id);
  if p_kind not in ('PAYMENT_LINK', 'SUBSCRIPTION') then
    raise exception 'Unknown billing kind.' using errcode = '22023';
  end if;

  insert into coaching_enrollment_billing (
    enrollment_id, facility_id, kind, amount_minor, total_cycles,
    razorpay_payment_link_id, razorpay_plan_id, razorpay_subscription_id, short_url, created_by
  ) values (
    e.id, e.facility_id, p_kind, p_amount_minor, greatest(p_total_cycles, 1),
    p_payment_link_id, p_plan_id, p_subscription_id, p_short_url, null
  )
  on conflict (enrollment_id) do update set
    kind = excluded.kind,
    status = 'CREATED',
    amount_minor = excluded.amount_minor,
    total_cycles = excluded.total_cycles,
    charge_count = 0,
    razorpay_payment_link_id = excluded.razorpay_payment_link_id,
    razorpay_plan_id = excluded.razorpay_plan_id,
    razorpay_subscription_id = excluded.razorpay_subscription_id,
    short_url = excluded.short_url,
    current_start = null,
    current_end = null
  where coaching_enrollment_billing.status in ('CANCELLED', 'EXPIRED')
  returning * into result;

  if result.id is null then
    select * into result from coaching_enrollment_billing where enrollment_id = e.id;
  end if;
  return result;
end;
$$;
revoke all on function player_record_coaching_billing(uuid, text, integer, integer, text, text, text, text) from public, anon;
grant execute on function player_record_coaching_billing(uuid, text, integer, integer, text, text, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- The signed-in player's enrolments at a venue (matched by phone, so ones the club added by hand count), so the page can say
-- "you are enrolled" or "finish your payment".
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_my_coaching_at(p_facility_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'enrollmentId', e.id,
    'programId', e.program_id,
    'programName', cp.name,
    'batchId', e.batch_id,
    'status', e.status,
    'feeType', e.fee_type,
    'priceMinor', e.price_minor,
    'paidMinor', coalesce((select sum(p.amount_inr) * 100 from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid'), 0)::bigint,
    'startDate', e.start_date,
    'endDate', e.end_date,
    'billingKind', b.kind,
    'billingStatus', b.status,
    'billingUrl', case when b.status in ('CREATED', 'AUTHENTICATED') then b.short_url end
  ) order by e.created_at desc), '[]'::jsonb)
  from coaching_enrollments e
  join members m on m.id = e.member_id
  join players pl on pl.id = auth.uid() and normalize_phone(pl.phone) = normalize_phone(m.phone)
  join coaching_programs cp on cp.id = e.program_id
  left join coaching_enrollment_billing b on b.enrollment_id = e.id
  where e.facility_id = p_facility_id and e.status in ('ACTIVE', 'PAUSED');
$$;
revoke all on function get_my_coaching_at(uuid) from public, anon;
grant execute on function get_my_coaching_at(uuid) to authenticated;

notify pgrst, 'reload schema';
