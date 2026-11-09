-- ═══════════════════════════════════════════════════════════════════════════
-- Follow-up to 0189.
--
--  A. Coaching enrolments follow the same rule as memberships: an enrolment made by a player is "Payment Incomplete"
--     (status PENDING_PAYMENT), holds no seat in its batch and is not put on the class roster until it is paid. The same person
--     (matched by mobile number) cannot hold two coaching batches on the same court at overlapping times.
--  B. When a payment arrives for a slot, the same person's OTHER unpaid memberships / coaching enrolments for an overlapping slot are
--     removed automatically (deleted; cancelled instead if a payment link or AutoPay mandate was already created for them).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- Slot overlap helpers
-- ─────────────────────────────────────────────────────────────────────────
create or replace function _batches_overlap(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from membership_batches x, membership_batches y
     where x.id = p_a and y.id = p_b
       and (x.id = y.id or (
         x.court_id = y.court_id and x.days_of_week && y.days_of_week
         and x.start_time < y.end_time and x.end_time > y.start_time
         and coalesce(x.end_date, date 'infinity') >= coalesce(y.start_date, date '-infinity')
         and coalesce(y.end_date, date 'infinity') >= coalesce(x.start_date, date '-infinity')))
  );
$$;
revoke all on function _batches_overlap(uuid, uuid) from public, anon, authenticated;

create or replace function _coaching_batches_overlap(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
      from coaching_program_batches x join coaching_programs xp on xp.id = x.program_id,
           coaching_program_batches y join coaching_programs yp on yp.id = y.program_id
     where x.id = p_a and y.id = p_b
       and (x.id = y.id or (
         x.court_id = y.court_id and x.days_of_week && y.days_of_week
         and x.start_time < y.end_time and x.end_time > y.start_time
         and coalesce(xp.end_date, date 'infinity') >= coalesce(yp.start_date, date '-infinity')
         and coalesce(yp.end_date, date 'infinity') >= coalesce(xp.start_date, date '-infinity')))
  );
$$;
revoke all on function _coaching_batches_overlap(uuid, uuid) from public, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- B (memberships). Activation also clears the person's other unpaid memberships for an overlapping slot.
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
  v_batch uuid;
  r record;
begin
  select * into ms from memberships where id = new.membership_id for update;
  if ms.id is null or ms.status <> 'pending' then
    return new;
  end if;

  select coalesce(f.timezone, 'Asia/Kolkata') into v_tz from facilities f where f.id = ms.facility_id;
  v_today := (now() at time zone coalesce(v_tz, 'Asia/Kolkata'))::date;
  v_days := coalesce((select mp.duration_days from membership_plans mp where mp.id = ms.plan_id), ms.duration_days, 30);
  select m.phone into v_phone from members m where m.id = ms.member_id;
  v_batch := ms.pending_batch_id;

  if v_batch is not null and not member_slot_conflict(ms.facility_id, v_phone, v_batch) then
    insert into membership_batch_members (batch_id, member_id, membership_id)
    values (v_batch, ms.member_id, ms.id)
    on conflict do nothing;
  end if;

  update memberships
     set status = 'active', start_date = v_today, end_date = add_membership_period(v_today, v_days), pending_batch_id = null
   where id = ms.id;

  -- the same person's other unpaid memberships for a slot that overlaps this one are not needed any more
  if v_batch is not null then
    for r in
      select ms2.id,
             exists (select 1 from membership_subscriptions s where s.membership_id = ms2.id) as has_link
        from memberships ms2
        join members m2 on m2.id = ms2.member_id
       where ms2.id <> ms.id and ms2.facility_id = ms.facility_id and ms2.status = 'pending'
         and ms2.pending_batch_id is not null
         and normalize_phone(m2.phone) = normalize_phone(v_phone)
         and not exists (select 1 from payments p where p.membership_id = ms2.id and p.status = 'paid')
         and _batches_overlap(ms2.pending_batch_id, v_batch)
    loop
      if r.has_link then
        -- an AutoPay link already exists at Razorpay: keep the record, close it
        update memberships set status = 'cancelled', pending_batch_id = null where id = r.id;
      else
        delete from payments where membership_id = r.id;
        delete from memberships where id = r.id;
      end if;
    end loop;
  end if;
  return new;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- A. Coaching: a new status for an enrolment that is waiting for its payment
-- ─────────────────────────────────────────────────────────────────────────
alter table coaching_enrollments drop constraint if exists coaching_enrollments_status_check;
alter table coaching_enrollments add constraint coaching_enrollments_status_check
  check (status in ('ACTIVE', 'PAUSED', 'COMPLETED', 'CANCELLED', 'PENDING_PAYMENT'));

-- Does this person (by mobile number) already hold a coaching batch that overlaps the chosen one?
create or replace function coaching_slot_conflict(p_facility_id uuid, p_phone text, p_batch_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
      from coaching_enrollments e
      join members m on m.id = e.member_id
     where e.facility_id = p_facility_id
       and e.status in ('ACTIVE', 'PAUSED')
       and e.batch_id is not null
       and normalize_phone(m.phone) is not null
       and normalize_phone(m.phone) = normalize_phone(p_phone)
       and _coaching_batches_overlap(e.batch_id, p_batch_id)
  );
$$;
revoke all on function coaching_slot_conflict(uuid, text, uuid) from public, anon, authenticated;

-- A payment for the enrolment makes it active (and the existing session sync puts it on the class roster).
create or replace function _activate_paid_coaching() returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  e coaching_enrollments;
  v_phone text;
  r record;
begin
  select * into e from coaching_enrollments where id = new.coaching_enrollment_id for update;
  if e.id is null or e.status <> 'PENDING_PAYMENT' then
    return new;
  end if;

  begin
    update coaching_enrollments set status = 'ACTIVE' where id = e.id;
  exception when unique_violation then
    -- this person is already enrolled in the programme some other way: leave this one alone, never fail the payment
    return new;
  end;

  if e.batch_id is not null then
    select m.phone into v_phone from members m where m.id = e.member_id;
    for r in
      select e2.id,
             exists (select 1 from coaching_enrollment_billing b where b.enrollment_id = e2.id) as has_link
        from coaching_enrollments e2
        join members m2 on m2.id = e2.member_id
       where e2.id <> e.id and e2.facility_id = e.facility_id and e2.status = 'PENDING_PAYMENT'
         and e2.batch_id is not null
         and normalize_phone(m2.phone) = normalize_phone(v_phone)
         and not exists (select 1 from payments p where p.coaching_enrollment_id = e2.id and p.status = 'paid')
         and _coaching_batches_overlap(e2.batch_id, e.batch_id)
    loop
      if r.has_link then
        update coaching_enrollments set status = 'CANCELLED', cancelled_at = now(),
               cancel_reason = 'Another enrolment for the same time was paid'
         where id = r.id;
      else
        delete from payments where coaching_enrollment_id = r.id;
        delete from coaching_enrollments where id = r.id;
      end if;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists payments_activate_coaching on payments;
create trigger payments_activate_coaching
  after insert or update of status on payments
  for each row
  when (new.status = 'paid' and new.coaching_enrollment_id is not null)
  execute function _activate_paid_coaching();


-- ─────────────────────────────────────────────────────────────────────────
-- The Player app's coaching enrolment: pending until paid, no seat held, duplicate/overlap check by mobile number.
-- (Everything else is as 0176.)
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

  -- The club's student record for this mobile number, or a new one.
  select m.id into v_member_id from members m
   where m.facility_id = p_facility_id and normalize_phone(m.phone) = normalize_phone(me.phone)
   order by m.created_at limit 1;
  if v_member_id is null then
    insert into members (facility_id, full_name, phone, email)
    values (p_facility_id, trim(me.full_name), trim(me.phone), nullif(trim(coalesce(me.email, '')), ''))
    returning id into v_member_id;
  end if;

  -- Already enrolled here (paid, or waiting for payment)?
  select * into v_enrollment from coaching_enrollments
   where facility_id = p_facility_id and member_id = v_member_id and program_id = prog.id
     and status in ('ACTIVE', 'PAUSED', 'PENDING_PAYMENT')
   order by (status = 'PENDING_PAYMENT'), created_at desc
   limit 1;

  if v_enrollment.id is not null then
    select coalesce(sum(p.amount_inr) * 100, 0)::bigint into v_paid
      from payments p where p.coaching_enrollment_id = v_enrollment.id and p.status = 'paid';
    select * into v_billing from coaching_enrollment_billing where enrollment_id = v_enrollment.id;
    if v_enrollment.status <> 'PENDING_PAYMENT'
       and (v_paid > 0 or (v_billing.id is not null and v_billing.status in ('AUTHENTICATED', 'ACTIVE', 'PENDING', 'PAID', 'COMPLETED'))) then
      raise exception 'You are already enrolled in this programme.' using errcode = '23505';
    end if;

    -- A waiting enrolment takes no seat, so check there is still one before it goes on to be paid.
    if v_enrollment.status = 'PENDING_PAYMENT' and coalesce(p_batch_id, v_enrollment.batch_id) is not null then
      select * into v_batch from coaching_program_batches where id = coalesce(p_batch_id, v_enrollment.batch_id);
      select count(*) into v_enrolled from coaching_enrollments
       where batch_id = v_batch.id and status in ('ACTIVE', 'PAUSED') and id <> v_enrollment.id;
      if v_batch.id is not null and v_enrolled >= v_batch.capacity then
        raise exception 'This batch is full.' using errcode = '23514';
      end if;
    end if;

    -- Unpaid and nothing live behind it: carry on with it, moved to the batch just picked.
    if p_batch_id is not null and v_enrollment.batch_id is distinct from p_batch_id then
      if coaching_slot_conflict(p_facility_id, me.phone, p_batch_id) then
        raise exception 'Please choose another time: you already have coaching at this court at this time.' using errcode = '23505';
      end if;
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

  -- A new enrolment. The batch row is locked so two players cannot both take its last seat; an unpaid enrolment takes no seat.
  if p_batch_id is not null then
    if coaching_slot_conflict(p_facility_id, me.phone, p_batch_id) then
      raise exception 'Please choose another time: you already have coaching at this court at this time.' using errcode = '23505';
    end if;
    perform 1 from coaching_program_batches where id = p_batch_id for update;
    select count(*) into v_enrolled from coaching_enrollments where batch_id = p_batch_id and status in ('ACTIVE', 'PAUSED');
    if v_enrolled >= v_batch.capacity then
      raise exception 'This batch is full.' using errcode = '23514';
    end if;
  end if;

  begin
    insert into coaching_enrollments (
      facility_id, member_id, program_id, coach_id, start_date, sessions_total, price_minor, pricing_type, batch_id, notes, status
    ) values (
      p_facility_id, v_member_id, prog.id, v_batch.coach_id, v_start, prog.session_count,
      v_charge * v_cycles, 'STANDARD', p_batch_id, 'Enrolled from the Player app', 'PENDING_PAYMENT'
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
-- The player-facing reads must still show an enrolment that is waiting for its payment (so "Pay now" keeps working).
-- Same functions, with PENDING_PAYMENT added to their status filters.
-- ─────────────────────────────────────────────────────────────────────────
do $$
declare
  f record;
  v_def text;
  v_new text;
begin
  for f in
    select p.oid, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('get_my_player_home', 'get_player_dashboard', 'get_my_coaching_details', 'get_my_coaching_at')
  loop
    v_def := pg_get_functiondef(f.oid);
    v_new := replace(v_def, 'e.status = ''ACTIVE''', 'e.status in (''ACTIVE'', ''PENDING_PAYMENT'')');
    v_new := replace(v_new, 'e.status in (''ACTIVE'', ''PAUSED'')', 'e.status in (''ACTIVE'', ''PAUSED'', ''PENDING_PAYMENT'')');
    if v_new <> v_def then
      execute v_new;
    end if;
  end loop;
end $$;


-- Same for memberships (0189 made them "pending" until paid): the player's own Home, My Membership and payment prompts list
-- active AND pending memberships, so a membership waiting for its payment is still there to pay.
do $$
declare
  f record;
  v_def text;
  v_new text;
begin
  for f in
    select p.oid
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('get_my_player_home', 'get_player_dashboard', 'get_my_membership_details')
  loop
    v_def := pg_get_functiondef(f.oid);
    v_new := replace(v_def, 'ms.status::text = ''active''', 'ms.status::text in (''active'', ''pending'')');
    if v_new <> v_def then
      execute v_new;
    end if;
  end loop;
end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- Existing unpaid enrolments the Player app made go back to "payment incomplete" and leave their class roster.
-- Staff-made ones (created_by set, or a different note) are untouched; so is anything with a payment or a live AutoPay.
-- ─────────────────────────────────────────────────────────────────────────
with legacy as (
  select e.id from coaching_enrollments e
   where e.status = 'ACTIVE' and e.created_by is null and e.notes = 'Enrolled from the Player app' and e.price_minor > 0
     and not exists (select 1 from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid')
     and not exists (select 1 from coaching_enrollment_billing b where b.enrollment_id = e.id and b.status in ('AUTHENTICATED', 'ACTIVE', 'PAID', 'COMPLETED'))
),
roster as (
  delete from coaching_session_students where enrollment_id in (select id from legacy) returning 1
)
update coaching_enrollments set status = 'PENDING_PAYMENT' where id in (select id from legacy);

notify pgrst, 'reload schema';
