-- A player joining a membership in the Player app may pick MORE THAN ONE time slot of the plan (they play only the timings they
-- choose, and at least one is required — the app enforces that). The first slot keeps riding in memberships.pending_batch_id exactly as
-- before; the others wait in the new pending_extra_batch_ids and are joined together with the first when the first payment is made.
-- Nothing about the single-slot path changes: with no extra slots, both functions below behave as they did in 0189 / 0190.

alter table memberships add column if not exists pending_extra_batch_ids uuid[] not null default '{}';


-- ─────────────────────────────────────────────────────────────────────────
-- The Player app's enrolment: same as 0189, plus the extra slots (each one must be an active slot of this club for this plan).
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists player_start_membership_enroll(uuid, uuid, uuid);

create or replace function player_start_membership_enroll(
  p_facility_id uuid,
  p_plan_id uuid,
  p_batch_id uuid default null,
  p_extra_batch_ids uuid[] default '{}'
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
  v_extra uuid[];
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

  -- the other slots the player ticked: distinct, not the first one again, and each must belong to this club and plan
  select coalesce(array_agg(distinct b), '{}') into v_extra
    from unnest(coalesce(p_extra_batch_ids, '{}')) as b
   where b is distinct from p_batch_id;
  if exists (
    select 1 from unnest(v_extra) as b
     where not exists (
       select 1 from membership_batches mb
        where mb.id = b and mb.facility_id = p_facility_id and mb.is_active
          and (mb.plan_id is null or mb.plan_id = p_plan_id)
     )
  ) then
    raise exception 'That time slot is not available.' using errcode = '23503';
  end if;

  signup := public_start_membership_signup(p_facility_id, me.full_name, me.phone, coalesce(me.email, ''), p_plan_id, p_batch_id);
  v_membership_id := (signup ->> 'membershipId')::uuid;

  -- the club sees what the player pays: plan price + joining fee
  update memberships
     set registration_fee_inr = v_fee, membership_fee_inr = plan.price_inr, total_amount_inr = v_total,
         pending_extra_batch_ids = v_extra
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
revoke all on function player_start_membership_enroll(uuid, uuid, uuid, uuid[]) from public, anon;
grant execute on function player_start_membership_enroll(uuid, uuid, uuid, uuid[]) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- The first payment makes a pending membership active (0190), and now also joins it to the extra slots the player ticked.
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
  v_extra uuid;
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

  -- the other slots the player ticked (a slot the person already holds an overlapping place in is skipped, as for the first)
  foreach v_extra in array coalesce(ms.pending_extra_batch_ids, '{}') loop
    if not member_slot_conflict(ms.facility_id, v_phone, v_extra) then
      insert into membership_batch_members (batch_id, member_id, membership_id)
      values (v_extra, ms.member_id, ms.id)
      on conflict do nothing;
    end if;
  end loop;

  update memberships
     set status = 'active', start_date = v_today, end_date = add_membership_period(v_today, v_days),
         pending_batch_id = null, pending_extra_batch_ids = '{}'
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
        update memberships set status = 'cancelled', pending_batch_id = null, pending_extra_batch_ids = '{}' where id = r.id;
      else
        delete from payments where membership_id = r.id;
        delete from memberships where id = r.id;
      end if;
    end loop;
  end if;
  return new;
end;
$$;
