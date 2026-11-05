-- ═══════════════════════════════════════════════════════════════════════════
-- Player App: Enroll Membership (time slot → plan → pay).
--
--   get_public_membership_enroll(facility)        anon-safe: the venue's sports, the time slots (with how many members
--                                                 play there now and how many seats are left) and the plans each slot offers
--   player_start_membership_enroll(...)           signed-in player: creates (or reuses) the pending membership and its
--                                                 payment row, returns what to pay (settled through UPI AutoPay)
--   get_my_memberships_at(facility)               signed-in player: the memberships their phone number already has at this venue
--
-- Every plan is paid through UPI AutoPay (create-membership-subscription); nothing there changes.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- What the Enroll page shows. Slots are grouped by sport and clock time; each carries the batches behind it, and each
-- batch belongs to one plan, so a slot offers exactly the plans its batches were created for.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_public_membership_enroll(p_facility_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with b as (
    select * from _list_assignable_batches_impl(p_facility_id => p_facility_id, p_plan_id => null)
  ),
  slots as (
    select
      facility_sport_id,
      min(sport_name) as sport_name,
      start_time,
      end_time,
      sum(capacity)::integer as capacity,
      sum(enrolled_count)::integer as members_now,
      sum(spare)::integer as spare,
      jsonb_agg(jsonb_build_object(
        'batchId', batch_id, 'planId', plan_id, 'courtName', court_name,
        'daysOfWeek', days_of_week, 'capacity', capacity, 'enrolled', enrolled_count, 'spare', spare
      ) order by court_name, name) as batches
    from b
    group by facility_sport_id, start_time, end_time
  )
  select case when f.id is null then null else jsonb_build_object(
    'facilityId', f.id,
    'facilityName', f.name,
    'city', coalesce(f.city, ''),
    'accepting', plan_has_feature(f.id, 'PLAYER_MEMBERSHIPS'),
    'autopayAvailable', plan_has_feature(f.id, 'AUTOPAY'),
    'sports', coalesce((select jsonb_agg(distinct jsonb_build_object('id', facility_sport_id, 'name', sport_name)) from b), '[]'::jsonb),
    'slots', coalesce((select jsonb_agg(jsonb_build_object(
        'facilitySportId', facility_sport_id, 'sportName', sport_name,
        'startTime', start_time, 'endTime', end_time,
        'capacity', capacity, 'membersNow', members_now, 'spare', spare, 'batches', batches
      ) order by sport_name, start_time) from slots), '[]'::jsonb),
    'plans', coalesce((select jsonb_agg(jsonb_build_object(
        'id', mp.id, 'name', mp.name, 'priceInr', mp.price_inr, 'durationDays', mp.duration_days,
        'planType', mp.plan_type, 'description', mp.description, 'category', mp.category,
        'badgeText', mp.badge_text, 'features', to_jsonb(mp.features),
        'joiningFeeInr', coalesce(mp.joining_fee_inr, 0)
      ) order by mp.duration_days, mp.price_inr)
      from membership_plans mp where mp.facility_id = f.id and mp.is_active), '[]'::jsonb)
  ) end
  from (select 1) one
  left join facilities f on f.id = p_facility_id;
$$;
grant execute on function get_public_membership_enroll(uuid) to anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Start (or resume) the signed-in player's enrolment. A player who backs out of the payment page and comes back gets the same
-- pending membership instead of a second one.
-- Returns { membershipId, paymentId, amountInr, joiningFeeInr, planType, planName, durationDays, resumed }.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function player_start_membership_enroll(
  p_facility_id uuid,
  p_plan_id uuid,
  p_batch_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me players;
  plan membership_plans;
  v_member_id uuid;
  v_membership_id uuid;
  v_payment_id uuid;
  v_fee integer;
  signup jsonb;
  v_batch membership_batches;
begin
  select * into me from players where id = auth.uid();
  if me.id is null then
    raise exception 'Sign in to join a membership.' using errcode = '42501';
  end if;

  select * into plan from membership_plans where id = p_plan_id and facility_id = p_facility_id and is_active;
  if plan.id is null then
    raise exception 'Membership plan not available.' using errcode = '23503';
  end if;
  v_fee := coalesce(plan.joining_fee_inr, 0);

  -- A pending one for this player and plan (unpaid, nothing recorded yet) is reused.
  select ms.id, ms.member_id, p.id into v_membership_id, v_member_id, v_payment_id
    from memberships ms
    join members m on m.id = ms.member_id
    join payments p on p.membership_id = ms.id and p.status = 'created' and p.razorpay_payment_id is null
   where ms.facility_id = p_facility_id and ms.plan_id = p_plan_id
     and normalize_phone(m.phone) = normalize_phone(me.phone)
     and not exists (select 1 from payments x where x.membership_id = ms.id and x.status = 'paid')
   order by ms.created_at desc
   limit 1;

  if v_membership_id is not null then
    return jsonb_build_object(
      'membershipId', v_membership_id, 'paymentId', v_payment_id,
      'amountInr', (select amount_inr from payments where id = v_payment_id),
      'joiningFeeInr', v_fee, 'planType', plan.plan_type, 'planName', plan.name,
      'durationDays', plan.duration_days, 'resumed', true);
  end if;

  -- The time slot, if one was chosen: it must belong to this club and plan. (assign_batch_member is for staff, so the
  -- player is placed here. A slot holds as many members as join it: clubs removed the capacity limit in 0089.)
  if p_batch_id is not null then
    select * into v_batch from membership_batches
     where id = p_batch_id and facility_id = p_facility_id and is_active for update;
    if v_batch.id is null or (v_batch.plan_id is not null and v_batch.plan_id <> p_plan_id) then
      raise exception 'That time slot is not available.' using errcode = '23503';
    end if;
  end if;

  signup := public_start_membership_signup(p_facility_id, me.full_name, me.phone, coalesce(me.email, ''), p_plan_id, null);
  v_membership_id := (signup ->> 'membershipId')::uuid;
  if p_batch_id is not null then
    insert into membership_batch_members (batch_id, member_id, membership_id)
    values (p_batch_id, (signup ->> 'memberId')::uuid, v_membership_id)
    on conflict do nothing;
  end if;

  -- The joining fee is charged once, with the first payment.
  if v_fee > 0 then
    update memberships set registration_fee_inr = v_fee where id = v_membership_id;
  end if;
  select id into v_payment_id from payments where membership_id = v_membership_id and status = 'created' order by created_at limit 1;
  if v_payment_id is null and (plan.price_inr + v_fee) > 0 then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status)
    values (p_facility_id, (signup ->> 'memberId')::uuid, v_membership_id, plan.price_inr + v_fee, 'created')
    returning id into v_payment_id;
  elsif v_fee > 0 then
    update payments set amount_inr = amount_inr + v_fee where id = v_payment_id;
  end if;

  return jsonb_build_object(
    'membershipId', v_membership_id, 'paymentId', v_payment_id,
    'amountInr', plan.price_inr + v_fee,
    'joiningFeeInr', v_fee, 'planType', plan.plan_type, 'planName', plan.name,
    'durationDays', plan.duration_days, 'resumed', false);
end;
$$;
revoke all on function player_start_membership_enroll(uuid, uuid, uuid) from public, anon;
grant execute on function player_start_membership_enroll(uuid, uuid, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- A player who already has memberships here (matched by phone, so ones the club added by hand count) sees them on the Enroll
-- page. Joining another is still allowed.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_my_memberships_at(p_facility_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'membershipId', ms.id,
    'planName', coalesce(mp.name, ms.name),
    'status', ms.status,
    'startDate', ms.start_date,
    'endDate', ms.end_date,
    'autoRenew', coalesce(ms.auto_renew, false),
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object('name', bt.name, 'startTime', bt.start_time, 'endTime', bt.end_time, 'daysOfWeek', bt.days_of_week))
        from membership_batch_members bm join membership_batches bt on bt.id = bm.batch_id
       where bm.member_id = ms.member_id and bt.facility_id = ms.facility_id), '[]'::jsonb)
  ) order by ms.end_date desc), '[]'::jsonb)
  from memberships ms
  join members m on m.id = ms.member_id
  join players pl on pl.id = auth.uid() and normalize_phone(pl.phone) = normalize_phone(m.phone)
  left join membership_plans mp on mp.id = ms.plan_id
  where ms.facility_id = p_facility_id and ms.status = 'active' and ms.end_date >= current_date;
$$;
revoke all on function get_my_memberships_at(uuid) from public, anon;
grant execute on function get_my_memberships_at(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- public_start_membership_signup (from 0162) failed on every call: its CASE of two plain literals is text, and the status column is an
-- enum ("column status is of type membership_status but expression is of type text"). Same function, with the enum cast. This is
-- what the club's /join page and the Enroll page both call.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public_start_membership_signup(
  p_facility_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_plan_id uuid,
  p_batch_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  plan membership_plans;
  batch membership_batches;
  v_member_id uuid;
  computed_end date;
  v_membership_id uuid;
begin
  if coalesce(trim(p_full_name), '') = '' or coalesce(trim(p_phone), '') = '' then
    raise exception 'Name and phone are required.' using errcode = '22023';
  end if;

  -- Players joining a membership from the Player App / join link is part of the Advanced plan. A club with no plan yet is
  -- unrestricted; Basic clubs take guest bookings only.
  if not plan_has_feature(p_facility_id, 'PLAYER_MEMBERSHIPS') then
    raise exception 'This club is not taking online memberships.' using errcode = '42501';
  end if;

  select * into plan from membership_plans
    where id = p_plan_id and facility_id = p_facility_id and is_active;
  if plan.id is null then
    raise exception 'Membership plan not available.' using errcode = '23503';
  end if;

  if p_batch_id is not null then
    select * into batch from membership_batches where id = p_batch_id and facility_id = p_facility_id and is_active;
    if batch.id is null then
      raise exception 'That time slot is not available.' using errcode = '23503';
    end if;
  end if;

  select id into v_member_id from members
    where facility_id = p_facility_id and phone = trim(p_phone);
  if v_member_id is null then
    insert into members (facility_id, full_name, phone, email)
    values (p_facility_id, trim(p_full_name), trim(p_phone), nullif(trim(p_email), ''))
    returning id into v_member_id;
  end if;

  computed_end := current_date + plan.duration_days;

  insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date, created_by, monthly_price_inr)
  values (p_facility_id, v_member_id, p_plan_id,
          case when computed_end >= current_date then 'active'::membership_status else 'expired'::membership_status end,
          current_date, computed_end, null, plan.price_inr)
  returning id into v_membership_id;

  if p_batch_id is not null then
    perform assign_batch_member(p_batch_id, v_member_id, v_membership_id);
  end if;

  if plan.price_inr > 0 then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status)
    values (p_facility_id, v_member_id, v_membership_id, plan.price_inr, 'created');
  end if;

  return jsonb_build_object(
    'membershipId', v_membership_id,
    'memberId', v_member_id,
    'amountInr', plan.price_inr
  );
end;
$$;

-- Make the new functions visible to the API straight away.
notify pgrst, 'reload schema';
