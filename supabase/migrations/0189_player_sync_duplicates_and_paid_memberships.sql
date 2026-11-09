-- ═══════════════════════════════════════════════════════════════════════════
-- Player app → club management: no duplicates, and a membership only counts once it is paid.
--
--  1. Memberships    one person (matched by MOBILE NUMBER, last 10 digits) cannot hold two memberships at the same venue, on the same
--                    court, at overlapping times. Different times are fine.
--  2. Guest bookings the same person cannot book the same court at an overlapping time twice (mobile number, not name).
--                    A guest is also found by the last 10 digits of the number, so "+91 98765 43210" and "9876543210" are one guest.
--  3. The club's membership total includes the joining fee the player paid.
--  4. A membership made by a player (or the /join page) is "pending" -> shown as Payment Incomplete, is NOT put into its time slot,
--     and becomes active (and takes its slot) only when its payment is paid. Abandoned ones never touch a slot.
--  5. A membership's court time is closed to guests: the public page and the Player app no longer sell "released" seats in it, and
--     a booking inside a membership (or coaching) window is refused.
-- ═══════════════════════════════════════════════════════════════════════════

alter table memberships add column if not exists pending_batch_id uuid references membership_batches (id) on delete set null;

-- ─────────────────────────────────────────────────────────────────────────
-- 1. Does this person (by mobile number) already hold a slot that overlaps the chosen one?
-- ─────────────────────────────────────────────────────────────────────────
create or replace function member_slot_conflict(p_facility_id uuid, p_phone text, p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from membership_batches nb
    join membership_batch_members bm on true
    join membership_batches ob on ob.id = bm.batch_id
    join members m on m.id = bm.member_id
    left join memberships ms on ms.id = bm.membership_id
    where nb.id = p_batch_id
      and m.facility_id = p_facility_id
      and normalize_phone(m.phone) is not null
      and normalize_phone(m.phone) = normalize_phone(p_phone)
      and ob.status = 'ACTIVE'
      -- a slot held through a membership that has ended does not count
      and (bm.membership_id is null or (ms.status in ('active', 'pending') and ms.end_date >= current_date))
      and (
        ob.id = nb.id
        or (
          ob.court_id = nb.court_id
          and ob.days_of_week && nb.days_of_week
          and ob.start_time < nb.end_time
          and ob.end_time > nb.start_time
          and coalesce(ob.end_date, date 'infinity') >= coalesce(nb.start_date, date '-infinity')
          and coalesce(nb.end_date, date 'infinity') >= coalesce(ob.start_date, date '-infinity')
        )
      )
  );
$$;
revoke all on function member_slot_conflict(uuid, text, uuid) from public, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. A paid payment makes a pending membership active and gives it its slot (unless the person already holds a clashing one).
--    Every way a payment is settled (AutoPay charge, payment link, cash recorded by staff) ends here.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function _activate_paid_membership() returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ms memberships;
  v_tz text;
  v_today date;
  v_days integer;
  v_phone text;
begin
  select * into ms from memberships where id = new.membership_id for update;
  if ms.id is null or ms.status <> 'pending' then
    return new;
  end if;

  select coalesce(f.timezone, 'Asia/Kolkata') into v_tz from facilities f where f.id = ms.facility_id;
  v_today := (now() at time zone coalesce(v_tz, 'Asia/Kolkata'))::date;
  v_days := coalesce((select mp.duration_days from membership_plans mp where mp.id = ms.plan_id), ms.duration_days, 30);

  if ms.pending_batch_id is not null then
    select m.phone into v_phone from members m where m.id = ms.member_id;
    if not member_slot_conflict(ms.facility_id, v_phone, ms.pending_batch_id) then
      insert into membership_batch_members (batch_id, member_id, membership_id)
      values (ms.pending_batch_id, ms.member_id, ms.id)
      on conflict do nothing;
    end if;
  end if;

  update memberships
     set status = 'active', start_date = v_today, end_date = add_membership_period(v_today, v_days), pending_batch_id = null
   where id = ms.id;
  return new;
end;
$$;

drop trigger if exists payments_activate_membership on payments;
create trigger payments_activate_membership
  after insert or update of status on payments
  for each row
  when (new.status = 'paid' and new.membership_id is not null)
  execute function _activate_paid_membership();


-- ─────────────────────────────────────────────────────────────────────────
-- Joining a membership from the club's /join page or the Player app. The member is found by mobile number; the membership is
-- "pending" (Payment Incomplete) and holds NO slot until it is paid. Coming back reuses the same pending one.
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
  v_membership_id uuid;
  v_payment_id uuid;
  v_resumed boolean := false;
  v_free boolean;
begin
  if coalesce(trim(p_full_name), '') = '' or coalesce(trim(p_phone), '') = '' then
    raise exception 'Name and phone are required.' using errcode = '22023';
  end if;

  if not plan_has_feature(p_facility_id, 'PLAYER_MEMBERSHIPS') then
    raise exception 'This club is not taking online memberships.' using errcode = '42501';
  end if;

  select * into plan from membership_plans where id = p_plan_id and facility_id = p_facility_id and is_active;
  if plan.id is null then
    raise exception 'Membership plan not available.' using errcode = '23503';
  end if;

  if p_batch_id is not null then
    select * into batch from membership_batches where id = p_batch_id and facility_id = p_facility_id and is_active;
    if batch.id is null or (batch.plan_id is not null and batch.plan_id <> p_plan_id) then
      raise exception 'That time slot is not available.' using errcode = '23503';
    end if;
    if member_slot_conflict(p_facility_id, p_phone, p_batch_id) then
      raise exception 'Please choose another time: you already have a membership at this court at this time.' using errcode = '23505';
    end if;
  end if;

  select id into v_member_id from members
   where facility_id = p_facility_id and normalize_phone(phone) = normalize_phone(p_phone)
   order by created_at limit 1;
  if v_member_id is null then
    insert into members (facility_id, full_name, phone, email)
    values (p_facility_id, trim(p_full_name), trim(p_phone), nullif(trim(coalesce(p_email, '')), ''))
    returning id into v_member_id;
  end if;

  v_free := plan.price_inr + coalesce(plan.joining_fee_inr, 0) <= 0;

  -- an unpaid membership for this person and plan is picked up again, not duplicated
  if not v_free then
    select ms.id into v_membership_id
      from memberships ms
     where ms.member_id = v_member_id and ms.plan_id = p_plan_id and ms.status = 'pending'
       and not exists (select 1 from payments x where x.membership_id = ms.id and x.status = 'paid')
     order by ms.created_at desc limit 1;
  end if;

  if v_membership_id is not null then
    v_resumed := true;
    update memberships set pending_batch_id = coalesce(p_batch_id, pending_batch_id) where id = v_membership_id;
  else
    insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date, created_by, monthly_price_inr,
                             membership_fee_inr, total_amount_inr, pending_batch_id)
    values (p_facility_id, v_member_id, p_plan_id,
            case when v_free then 'active'::membership_status else 'pending'::membership_status end,
            current_date, current_date + plan.duration_days, null, plan.price_inr,
            plan.price_inr, plan.price_inr + coalesce(plan.joining_fee_inr, 0),
            case when v_free then null else p_batch_id end)
    returning id into v_membership_id;

    -- nothing to pay: the member takes the slot straight away
    if v_free and p_batch_id is not null then
      insert into membership_batch_members (batch_id, member_id, membership_id)
      values (p_batch_id, v_member_id, v_membership_id)
      on conflict do nothing;
    end if;
  end if;

  select id into v_payment_id from payments
   where membership_id = v_membership_id and status = 'created' and razorpay_payment_id is null
   order by created_at limit 1;
  if v_payment_id is null and plan.price_inr > 0 and not v_resumed then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status)
    values (p_facility_id, v_member_id, v_membership_id, plan.price_inr, 'created')
    returning id into v_payment_id;
  end if;

  return jsonb_build_object(
    'membershipId', v_membership_id,
    'memberId', v_member_id,
    'paymentId', v_payment_id,
    'amountInr', plan.price_inr,
    'resumed', v_resumed
  );
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- The Player app's enrolment. Same rules; adds the joining fee to what is charged and to the club's total (item 3).
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
  v_membership_id uuid;
  v_payment_id uuid;
  v_fee integer;
  v_total integer;
  signup jsonb;
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
  v_total := plan.price_inr + v_fee;

  signup := public_start_membership_signup(p_facility_id, me.full_name, me.phone, coalesce(me.email, ''), p_plan_id, p_batch_id);
  v_membership_id := (signup ->> 'membershipId')::uuid;

  -- the club sees what the player pays: plan price + joining fee
  update memberships
     set registration_fee_inr = v_fee, membership_fee_inr = plan.price_inr, total_amount_inr = v_total
   where id = v_membership_id;

  select id into v_payment_id from payments
   where membership_id = v_membership_id and status = 'created' and razorpay_payment_id is null
   order by created_at limit 1;
  if v_payment_id is null and v_total > 0 then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status)
    values (p_facility_id, (signup ->> 'memberId')::uuid, v_membership_id, v_total, 'created')
    returning id into v_payment_id;
  elsif v_payment_id is not null then
    update payments set amount_inr = v_total where id = v_payment_id;
  end if;

  return jsonb_build_object(
    'membershipId', v_membership_id, 'paymentId', v_payment_id,
    'amountInr', v_total,
    'joiningFeeInr', v_fee, 'planType', plan.plan_type, 'planName', plan.name,
    'durationDays', plan.duration_days, 'resumed', coalesce((signup ->> 'resumed')::boolean, false));
end;
$$;
revoke all on function player_start_membership_enroll(uuid, uuid, uuid) from public, anon;
grant execute on function player_start_membership_enroll(uuid, uuid, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Existing unpaid memberships that a player (or the /join page) made and that already sit in a slot: they go back to "pending"
-- (Payment Incomplete) and leave the slot until they pay. Staff-made memberships (created_by set) are untouched.
-- ─────────────────────────────────────────────────────────────────────────
with legacy as (
  select ms.id
    from memberships ms
   where ms.created_by is null and ms.status = 'active'
     and exists (select 1 from payments p where p.membership_id = ms.id and p.status = 'created')
     and not exists (select 1 from payments p where p.membership_id = ms.id and p.status = 'paid')
),
slot as (
  select distinct on (bm.membership_id) bm.membership_id, bm.batch_id
    from membership_batch_members bm
   where bm.membership_id in (select id from legacy)
   order by bm.membership_id, bm.created_at
),
moved as (
  update memberships ms set status = 'pending', pending_batch_id = slot.batch_id
    from legacy left join slot on slot.membership_id = legacy.id
   where ms.id = legacy.id
  returning ms.id
)
delete from membership_batch_members where membership_id in (select id from moved);


-- ─────────────────────────────────────────────────────────────────────────
-- 2. A guest is the same person when the last 10 digits of the number match (staff and public paths both use this).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function find_or_create_guest(
  p_facility_id uuid,
  p_name text,
  p_phone text,
  p_email text default null,
  p_notes text default null
) returns guest_players
language plpgsql
as $$
declare
  result guest_players;
  v_norm text := normalize_phone(p_phone);
begin
  perform require_page_access_any(p_facility_id, array['GUEST_BOOKINGS_CREATE', 'BOOKINGS_CREATE', 'GUEST_PLAYERS_EDIT']);
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Guest name is required.' using errcode = '23514';
  end if;

  if v_norm is not null then
    select * into result from guest_players
     where facility_id = p_facility_id and normalize_phone(phone) = v_norm
     order by created_at limit 1;
    if result.id is not null then
      return result;
    end if;
  end if;

  insert into guest_players (facility_id, name, phone, email, notes)
  values (p_facility_id, trim(p_name), p_phone, p_email, p_notes)
  returning * into result;

  return result;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- 5. The public availability list: a membership's court time is not for sale to guests any more (it used to sell the seats the
--    owner "released"). Maintenance and coaching blocks stay as they were.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_public_court_availability(
  p_facility_id uuid,
  p_facility_sport_id uuid,
  p_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  fac facilities;
  tz text;
  result jsonb := '[]'::jsonb;
  c record;
  h integer;
  slot_start timestamptz;
  slot_end timestamptz;
  slots jsonb;
  is_available boolean;
  price integer;
begin
  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    return '[]'::jsonb;
  end if;
  tz := coalesce(fac.timezone, 'Asia/Kolkata');

  for c in
    select ct.id, ct.name
    from courts ct
    where ct.facility_id = p_facility_id
      and ct.facility_sport_id = p_facility_sport_id
      and not ct.archived
    order by ct.display_order, ct.name
  loop
    slots := '[]'::jsonb;

    for h in 0..23 loop
      slot_start := (p_date::text || ' ' || lpad(h::text, 2, '0') || ':00:00')::timestamp at time zone tz;
      slot_end := slot_start + interval '1 hour';

      continue when slot_end <= now();
      continue when not booking_window_fits_operating_hours(p_facility_id, c.id, slot_start, slot_end);

      is_available := not exists (
        select 1
        from bookings b
        where b.court_id = c.id
          and b.status in ('pending', 'confirmed')
          and tstzrange(b.start_time, b.end_time) && tstzrange(slot_start, slot_end)
      );

      if is_available and court_has_active_maintenance_block(c.id, slot_start, slot_end) then
        is_available := false;
      end if;

      if is_available and court_has_active_coaching_session(c.id, slot_start, slot_end) then
        is_available := false;
      end if;

      if is_available and court_has_active_membership_window(c.id, slot_start, slot_end, tz) then
        is_available := false;
      end if;

      price := resolve_booking_price(p_facility_sport_id, c.id, slot_start, slot_end, tz);

      slots := slots || jsonb_build_object(
        'startTime', slot_start,
        'endTime', slot_end,
        'available', is_available,
        'priceMinor', coalesce(price, 0)
      );
    end loop;

    if jsonb_array_length(slots) > 0 then
      result := result || jsonb_build_object('courtId', c.id, 'courtName', c.name, 'slots', slots);
    end if;
  end loop;

  return result;
end;
$$;
grant execute on function get_public_court_availability(uuid, uuid, date) to anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2 + 5. The one routine behind the Player app and the public page's "Book": the guest is found by mobile number, a repeat of the
-- same person's booking on the same court at an overlapping time is refused, and membership / coaching time is not bookable.
-- (Everything else is as 0188.)
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public_create_guest_booking(
  p_facility_id uuid,
  p_court_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_name text,
  p_phone text,
  p_email text default null,
  p_purpose text default null,
  p_notes text default null,
  p_party_size integer default 1,
  p_payment_option text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  fac facilities;
  court courts;
  tz text;
  guest guest_players;
  digits text;
  booking bookings;
  combined_notes text;
  booking_code text;
  sport_name text;
  unpaid_pending integer;
  v_norm text;
  v_option text := nullif(upper(btrim(coalesce(p_payment_option, ''))), '');
begin
  if v_option is not null and v_option not in ('ADVANCE', 'FULL') then
    raise exception 'Choose 50%% now or the full amount.' using errcode = '23514';
  end if;
  perform release_expired_booking_holds();

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Please enter your name.' using errcode = '23514';
  end if;

  digits := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  if length(digits) < 10 or length(digits) > 15 then
    raise exception 'Please enter a valid mobile number.' using errcode = '23514';
  end if;
  v_norm := normalize_phone(p_phone);

  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    raise exception 'We could not find that venue.' using errcode = '23503';
  end if;
  tz := coalesce(fac.timezone, 'Asia/Kolkata');

  select * into court from courts where id = p_court_id and facility_id = p_facility_id and not archived;
  if court.id is null then
    raise exception 'We could not find that court.' using errcode = '23503';
  end if;

  if p_end_time <= p_start_time then
    raise exception 'Please choose a valid time.' using errcode = '23514';
  end if;
  if p_start_time <= now() then
    raise exception 'That time has already passed. Please choose another time.' using errcode = '23514';
  end if;

  -- The same person (by mobile number) already has this court at an overlapping time.
  if exists (
    select 1 from bookings b
     where b.facility_id = p_facility_id and b.court_id = p_court_id
       and b.status in ('pending', 'confirmed')
       and tstzrange(b.start_time, b.end_time) && tstzrange(p_start_time, p_end_time)
       and (
         normalize_phone(b.guest_phone) = v_norm
         or b.guest_player_id in (select g.id from guest_players g where g.facility_id = p_facility_id and normalize_phone(g.phone) = v_norm)
         or b.member_id in (select m.id from members m where m.facility_id = p_facility_id and normalize_phone(m.phone) = v_norm)
       )
  ) then
    raise exception 'Please check My Bookings: you already have a booking at this court at this time.' using errcode = '23505';
  end if;

  -- Court time kept for members or for a coaching session is not for guests.
  if court_has_active_membership_window(p_court_id, p_start_time, p_end_time, tz) then
    raise exception 'Please choose another time: this court is reserved for members then.' using errcode = '23514';
  end if;
  if court_has_active_coaching_session(p_court_id, p_start_time, p_end_time) then
    raise exception 'Please choose another time: this court is reserved for a coaching session then.' using errcode = '23514';
  end if;

  select coalesce(fs.custom_sport_name, sp.name) into sport_name
  from facility_sports fs
  left join sports sp on sp.id = fs.sport_id
  where fs.id = court.facility_sport_id;

  combined_notes := nullif(trim(concat_ws(
    ' — ',
    nullif(trim(coalesce(p_purpose, '')), ''),
    nullif(trim(coalesce(p_notes, '')), '')
  )), '');

  -- the guest, found by the last 10 digits of the mobile number
  select * into guest from guest_players
   where facility_id = p_facility_id and normalize_phone(phone) = v_norm
   order by created_at limit 1;
  if guest.id is null then
    insert into guest_players (facility_id, name, phone, email)
    values (p_facility_id, trim(p_name), p_phone, nullif(trim(coalesce(p_email, '')), ''))
    returning * into guest;
  end if;

  select count(*) into unpaid_pending
  from bookings b
  where b.guest_player_id = guest.id
    and b.customer_type = 'GUEST'
    and b.status in ('pending', 'confirmed')
    and b.payment_status = 'PENDING'
    and b.start_time > now();
  if unpaid_pending >= 4 then
    raise exception 'You have unpaid bookings still pending. Please complete or cancel them before booking again.'
      using errcode = '23514';
  end if;

  begin
    booking := create_booking(
      p_facility_id := p_facility_id,
      p_court_id := p_court_id,
      p_start_time := p_start_time,
      p_end_time := p_end_time,
      p_customer_type := 'GUEST',
      p_member_id := null,
      p_guest_name := null,
      p_guest_phone := null,
      p_notes := combined_notes,
      p_payment_status := 'PENDING',
      p_guest_player_id := guest.id,
      p_party_size := greatest(coalesce(p_party_size, 1), 1),
      p_payment_method := null
    );
  exception
    when exclusion_violation then
      raise exception 'Sorry, this court is no longer available.' using errcode = '23514';
    when check_violation then
      raise exception 'Sorry, this court is no longer available.' using errcode = '23514';
  end;

  if v_option is not null or booking.end_time - booking.start_time > interval '1 hour' then
    update bookings
      set status = 'pending', hold_expires_at = now() + interval '30 minutes', payment_option = v_option
      where id = booking.id
      returning * into booking;
  end if;

  booking_code := 'GBK' || upper(substr(replace(booking.id::text, '-', ''), 1, 4));

  return jsonb_build_object(
    'bookingId', booking.id,
    'code', booking_code,
    'facilityName', fac.name,
    'sportName', coalesce(sport_name, 'Sport'),
    'courtName', court.name,
    'startTime', booking.start_time,
    'endTime', booking.end_time,
    'guestName', guest.name,
    'guestPhone', guest.phone,
    'amountMinor', coalesce(booking.amount_minor, 0),
    'currency', coalesce(booking.currency, 'INR'),
    'paymentStatus', booking.payment_status,
    'bookingStatus', booking.status,
    'advanceRequired', booking.hold_expires_at is not null,
    'advanceMinor', case when booking.hold_expires_at is not null then booking_due_now_minor(booking) else 0 end,
    'paymentOption', booking.payment_option,
    'holdExpiresAt', booking.hold_expires_at
  );
end;
$$;
grant execute on function public_create_guest_booking(uuid, uuid, timestamptz, timestamptz, text, text, text, text, text, integer, text) to anon, authenticated;

notify pgrst, 'reload schema';
