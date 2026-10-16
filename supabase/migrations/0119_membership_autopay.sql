-- ═══════════════════════════════════════════════════════════════════════════
-- Membership AutoPay — scheduling, amounts and next payment date.
--
-- WHAT WAS WRONG
--   • The AutoPay amount came from memberships.monthly_price_inr, which the wizard filled with the whole
--     first payment — so the registration fee (and GST) were charged again every cycle.
--   • "Next payment date" was worked out in days (start + 30), so a membership started on the 14th came
--     due on the 13th; and every successful charge added a cycle on top of an end_date that already
--     covered the first one, so the first payment pushed the due date out by a whole extra cycle.
--   • memberships.auto_renew was never switched on, so AutoPay memberships were labelled "Expiry".
--   • The first payment left a second, never-settled "created" payment row behind.
--
-- WHAT THIS DOES
--   1. A membership's period now runs in CALENDAR MONTHS: 14 Oct + 1 month = 14 Nov, then 14 Dec, 14 Jan…
--      (3-month plans every 3 months, a 1-year plan every 12). Applied to memberships created or edited
--      from now on; existing rows are left as they are.
--   2. A successful AutoPay charge settles the pending first-payment row (no duplicate), and sets the
--      next payment date from Razorpay's own schedule, falling back to calendar months.
--   3. auto_renew follows the subscription: on while it is authorised / active, off once it is cancelled,
--      completed or halted.
--   4. The subscription row records its billing interval and the one-time amount taken with the first
--      payment, so the app can show "₹2,500 every 1 month, next 14 Nov".
--   5. The three subscription RPCs only the Edge Functions call are no longer callable by signed-in or
--      anonymous users — before, anyone could have recorded a fake charge against a membership.
-- ═══════════════════════════════════════════════════════════════════════════

alter table membership_subscriptions add column if not exists interval_months integer;
alter table membership_subscriptions add column if not exists one_time_inr integer not null default 0;


-- ─────────────────────────────────────────────────────────────────────────
-- Calendar-month period maths.
-- ─────────────────────────────────────────────────────────────────────────

-- Whole months in a membership's period: 30 → 1, 90 → 3, 180 → 6, 365 → 12. Null for a custom length
-- of under four weeks, which stays a plain number of days.
create or replace function membership_period_months(p_duration_days integer) returns integer
language sql immutable
as $$
  select case
    when p_duration_days is null or p_duration_days < 28 then null
    else greatest(round(p_duration_days / 30.0)::integer, 1)
  end;
$$;

-- The date a period starting on p_from ends / the next one is due: same day next month.
-- (31 Jan + 1 month is 28 Feb, as Razorpay clamps it.)
create or replace function add_membership_period(p_from date, p_duration_days integer) returns date
language sql immutable
as $$
  select case
    when membership_period_months(p_duration_days) is null then p_from + coalesce(p_duration_days, 0)
    else (p_from + make_interval(months => membership_period_months(p_duration_days)))::date
  end;
$$;

-- Keep a self-contained membership's end / next-payment date on the calendar whenever it is created or its
-- start date or duration changes.
create or replace function _memberships_calendar_end() returns trigger
language plpgsql
as $$
begin
  if new.duration_days is not null and new.duration_days > 0 and new.start_date is not null then
    new.end_date := add_membership_period(new.start_date, new.duration_days);
  end if;
  return new;
end;
$$;

drop trigger if exists memberships_calendar_end on memberships;
create trigger memberships_calendar_end
  before insert or update of start_date, duration_days on memberships
  for each row execute function _memberships_calendar_end();


-- ─────────────────────────────────────────────────────────────────────────
-- record_membership_subscription — now also stores the interval and the one-time amount.
-- (Dropped first: a second overload would make calls ambiguous.)
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists record_membership_subscription(uuid, text, text, integer, text, text);

create or replace function record_membership_subscription(
  p_membership_id uuid,
  p_razorpay_plan_id text,
  p_razorpay_subscription_id text,
  p_amount_inr integer,
  p_short_url text default null,
  p_razorpay_customer_id text default null,
  p_interval_months integer default null,
  p_one_time_inr integer default 0
) returns membership_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  mship memberships;
  result membership_subscriptions;
begin
  select * into mship from memberships where id = p_membership_id;
  if mship.id is null then
    raise exception 'Membership not found.' using errcode = '23503';
  end if;

  insert into membership_subscriptions (
    membership_id, facility_id, member_id, razorpay_plan_id,
    razorpay_subscription_id, razorpay_customer_id, amount_inr, short_url,
    interval_months, one_time_inr
  )
  values (
    p_membership_id, mship.facility_id, mship.member_id, p_razorpay_plan_id,
    p_razorpay_subscription_id, p_razorpay_customer_id, p_amount_inr, p_short_url,
    p_interval_months, greatest(coalesce(p_one_time_inr, 0), 0)
  )
  on conflict (razorpay_subscription_id) do update
    set short_url = excluded.short_url, updated_at = now()
  returning * into result;

  return result;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- apply_subscription_webhook — same forward-only status update, plus auto_renew follows the subscription.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function apply_subscription_webhook(
  p_razorpay_subscription_id text,
  p_status membership_subscription_status,
  p_charge_count integer default null,
  p_current_start date default null,
  p_current_end date default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  sub membership_subscriptions;
  v_status membership_subscription_status;
  rank_map jsonb := '{"created":0,"authenticated":1,"active":2,"pending":2,"halted":3,"cancelled":4,"completed":4}';
begin
  select * into sub from membership_subscriptions
    where razorpay_subscription_id = p_razorpay_subscription_id;
  if sub.id is null then
    -- A subscription Razorpay knows about that we don't — nothing to do.
    return;
  end if;

  update membership_subscriptions
    set status = case
          -- never downgrade past a terminal state; allow active<->pending both ways
          when (rank_map ->> sub.status::text)::int > (rank_map ->> p_status::text)::int
               and sub.status not in ('active', 'pending') then sub.status
          else p_status
        end,
        charge_count = coalesce(p_charge_count, charge_count),
        current_start = coalesce(p_current_start, current_start),
        current_end = coalesce(p_current_end, current_end),
        updated_at = now()
    where id = sub.id
    returning status into v_status;

  -- AutoPay is "on" while the mandate is authorised and charging; off once it has stopped.
  update memberships
    set auto_renew = (v_status in ('authenticated', 'active', 'pending'))
    where id = sub.membership_id;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- record_subscription_charge — one successful AutoPay cycle.
--
--   * The first charge SETTLES the pending first-payment row the membership was created with (no second
--     row); later charges add a payment each.
--   * The next payment date is Razorpay's own current_end when it sent one, else calendar months:
--     first charge → paid-on date + one period; later charges → the previous due date + one period, so
--     the day of the month never drifts (14 Nov → 14 Dec → 14 Jan).
--   * Idempotent on razorpay_payment_id.
-- ─────────────────────────────────────────────────────────────────────────
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
  v_cycle_days integer;
  v_tz text;
  v_paid_on date;
  v_first boolean;
  v_pending payments;
  v_next date;
begin
  select * into sub from membership_subscriptions
    where razorpay_subscription_id = p_razorpay_subscription_id;
  if sub.id is null then
    return;
  end if;

  -- Idempotency: a redelivered subscription.charged must not double-count.
  if exists (select 1 from payments where razorpay_payment_id = p_razorpay_payment_id) then
    return;
  end if;

  select * into mship from memberships where id = sub.membership_id;
  if mship.plan_id is not null then
    select * into plan from membership_plans where id = mship.plan_id;
  end if;
  v_cycle_days := coalesce(plan.duration_days, mship.duration_days, 30);

  v_tz := coalesce((select f.timezone from facilities f where f.id = sub.facility_id), 'Asia/Kolkata');
  v_paid_on := (p_paid_at at time zone v_tz)::date;

  v_first := not exists (
    select 1 from payments
    where membership_id = sub.membership_id and payment_method = 'upi_autopay' and status = 'paid'
  );

  -- The first charge settles the pending payment row created with the membership.
  select * into v_pending from payments
    where membership_id = sub.membership_id and status = 'created' and razorpay_payment_id is null
    order by created_at
    limit 1;

  if v_first and v_pending.id is not null then
    update payments
      set status = 'paid', amount_inr = p_amount_inr, razorpay_payment_id = p_razorpay_payment_id,
          paid_at = p_paid_at, payment_method = 'upi_autopay'
      where id = v_pending.id;
  else
    insert into payments (facility_id, member_id, membership_id, amount_inr, status, razorpay_payment_id, paid_at, payment_method)
    values (sub.facility_id, sub.member_id, sub.membership_id, p_amount_inr, 'paid', p_razorpay_payment_id, p_paid_at, 'upi_autopay');
  end if;

  -- Next payment date.
  if sub.current_end is not null and sub.current_end > v_paid_on then
    v_next := sub.current_end;                                    -- Razorpay's own schedule
  elsif v_first then
    v_next := add_membership_period(v_paid_on, v_cycle_days);     -- 14 Oct paid → 14 Nov
  else
    v_next := add_membership_period(mship.end_date, v_cycle_days); -- previous due date + one period
    if v_next <= v_paid_on then
      v_next := add_membership_period(v_paid_on, v_cycle_days);
    end if;
  end if;

  update memberships
    set end_date = v_next, status = 'active', auto_renew = true
    where id = sub.membership_id;

  update membership_subscriptions
    set status = 'active',
        charge_count = (select count(*) from payments
                         where membership_id = sub.membership_id and payment_method = 'upi_autopay' and status = 'paid'),
        current_start = coalesce(sub.current_start, v_paid_on),
        current_end = v_next,
        updated_at = now()
    where id = sub.id;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- record_membership_payment ("mark as paid" for a cash / offline cycle) — the next payment date now moves
-- by calendar months too, not by a day count.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function record_membership_payment(p_membership_id uuid, p_method text default 'cash')
returns memberships
language plpgsql
security definer
set search_path = public
as $$
declare
  m memberships;
  mp membership_plans;
  amt integer;
  cyc integer;
  pending payments;
  result memberships;
begin
  select * into m from memberships where id = p_membership_id;
  if m.id is null then
    raise exception 'Membership not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(m.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized to record payments.' using errcode = '42501';
  end if;
  if m.status = 'cancelled' then
    raise exception 'This membership is cancelled.' using errcode = '23514';
  end if;

  if m.plan_id is not null then
    select * into mp from membership_plans where id = m.plan_id;
  end if;
  amt := greatest(coalesce(m.total_amount_inr, m.monthly_price_inr, m.membership_fee_inr, mp.price_inr, 0), 0);
  cyc := coalesce(nullif(m.duration_days, 0), greatest(m.end_date - m.start_date, 30));

  select * into pending from payments
    where membership_id = m.id and (status <> 'paid' or paid_at is null)
    order by created_at desc
    limit 1;

  if pending.id is not null then
    update payments
      set status = 'paid',
          paid_at = now(),
          payment_method = coalesce(nullif(trim(p_method), ''), payment_method)
      where id = pending.id;
  else
    insert into payments (facility_id, member_id, membership_id, amount_inr, status, payment_method, paid_at)
    values (m.facility_id, m.member_id, m.id, amt, 'paid', coalesce(nullif(trim(p_method), ''), 'cash'), now());
  end if;

  if m.end_date < current_date then
    update memberships
      set end_date = add_membership_period(greatest(m.end_date, current_date), cyc),
          status = 'active'
      where id = m.id;
  elsif m.status <> 'active' then
    update memberships set status = 'active' where id = m.id;
  end if;

  select * into result from memberships where id = m.id;
  return result;
end;
$$;

grant execute on function record_membership_payment(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- These three are called only by Edge Functions (service role). 0026 granted them to signed-in and
-- anonymous users, which would let anyone record a fake charge or flip a subscription's status.
-- ─────────────────────────────────────────────────────────────────────────
revoke execute on function record_membership_subscription(uuid, text, text, integer, text, text, integer, integer) from public, anon, authenticated;
grant execute on function record_membership_subscription(uuid, text, text, integer, text, text, integer, integer) to service_role;

revoke execute on function apply_subscription_webhook(text, membership_subscription_status, integer, date, date) from public, anon, authenticated;
grant execute on function apply_subscription_webhook(text, membership_subscription_status, integer, date, date) to service_role;

revoke execute on function record_subscription_charge(text, integer, text, timestamptz) from public, anon, authenticated;
grant execute on function record_subscription_charge(text, integer, text, timestamptz) to service_role;
