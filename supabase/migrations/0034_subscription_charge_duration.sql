-- ═══════════════════════════════════════════════════════════════════════════
-- Subscription charge rolls end_date by the membership's own Duration.
--
-- record_subscription_charge advanced end_date by
-- `coalesce(plan.duration_days, 30)` — so a self-contained membership (no
-- plan) with a 1-year Duration was only rolled 30 days per charge, out of
-- step with both the membership's Duration and the (now matching) Razorpay
-- billing cadence. Fall back to the membership's own duration_days.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function record_subscription_charge(
  p_razorpay_subscription_id text,
  p_amount_inr integer,
  p_razorpay_payment_id text,
  p_paid_at timestamptz default now()
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  sub membership_subscriptions;
  mship memberships;
  plan membership_plans;
  cyc integer;
begin
  select * into sub from membership_subscriptions
    where razorpay_subscription_id = p_razorpay_subscription_id;
  if sub.id is null then
    return;
  end if;

  if exists (select 1 from payments where razorpay_payment_id = p_razorpay_payment_id) then
    return;
  end if;

  select * into mship from memberships where id = sub.membership_id;
  select * into plan from membership_plans where id = mship.plan_id;
  cyc := coalesce(plan.duration_days, mship.duration_days, 30);

  insert into payments (facility_id, member_id, membership_id, amount_inr, status, razorpay_payment_id, paid_at, payment_method)
  values (sub.facility_id, sub.member_id, sub.membership_id, p_amount_inr, 'paid', p_razorpay_payment_id, p_paid_at, 'upi_autopay');

  update memberships
    set end_date = greatest(end_date, current_date) + cyc,
        status = 'active'
    where id = sub.membership_id;

  update membership_subscriptions
    set status = 'active', charge_count = charge_count + 1, updated_at = now()
    where id = sub.id;
end;
$$;