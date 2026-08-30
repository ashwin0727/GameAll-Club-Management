-- ═══════════════════════════════════════════════════════════════════════════
-- Membership Subscriptions — Phase 2 (recurring UPI AutoPay).
--
-- A membership can be backed by a Razorpay Subscription: the player
-- authorises a UPI AutoPay mandate once (via the subscription's short_url),
-- and Razorpay then charges the monthly amount automatically. Each
-- successful cycle arrives as a `subscription.charged` webhook and is
-- recorded here as a normal `payments` row (so Finance / the dashboard /
-- the Memberships page already see it) AND extends the membership's
-- end_date by the plan's duration so "days left" stays honest.
--
-- Assumptions (single-merchant): money settles to the facility's own
-- Razorpay account through Razorpay's normal settlement — this integration
-- does not build payouts/Route. Cash memberships stay entirely manual
-- (recorded via create_membership with paymentStatus, no subscription).
--
-- Also adds the two anon-callable RPCs behind the public self sign-up page
-- (/join/<facilityId>): one read (facility + plans), one write
-- (get-or-create member + pending membership). Both SECURITY DEFINER so the
-- anon surface is exactly these two functions and nothing else.
-- ═══════════════════════════════════════════════════════════════════════════

create type membership_subscription_status as enum (
  'created',        -- our row exists, Razorpay subscription created, mandate not yet authorised
  'authenticated',  -- mandate authorised, first charge not yet done
  'active',         -- charging normally
  'pending',        -- a charge failed, Razorpay is retrying
  'halted',         -- retries exhausted — needs the player to re-authorise / pay
  'cancelled',      -- stopped (by owner or player)
  'completed'       -- ran its full course (total_count reached)
);

create table membership_subscriptions (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null unique references memberships (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  member_id uuid not null references members (id) on delete cascade,
  razorpay_plan_id text not null,
  razorpay_subscription_id text not null unique,
  razorpay_customer_id text,
  status membership_subscription_status not null default 'created',
  amount_inr integer not null check (amount_inr > 0),
  short_url text,
  charge_count integer not null default 0,
  current_start date,
  current_end date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index membership_subscriptions_facility_id_idx on membership_subscriptions (facility_id);
create index membership_subscriptions_status_idx on membership_subscriptions (status);

alter table membership_subscriptions enable row level security;

-- Read: facility managers/staff (same check the memberships policies use).
create policy "membership_subscriptions_select_staff" on membership_subscriptions
  for select using (
    exists (
      select 1 from facilities f
      where f.id = membership_subscriptions.facility_id and f.owner_id = auth.uid()
    )
    or exists (
      select 1 from profiles p where p.id = auth.uid() and p.role in ('admin', 'staff')
    )
  );
-- All writes go through the SECURITY DEFINER RPCs / the webhook's service
-- role — no direct client INSERT/UPDATE policy on purpose.

-- ─────────────────────────────────────────────────────────────────────────
-- record_membership_subscription — called by the create-membership-
-- subscription Edge Function right after it creates the Razorpay plan +
-- subscription. Idempotent on razorpay_subscription_id.
-- ─────────────────────────────────────────────────────────────────────────
create function record_membership_subscription(
  p_membership_id uuid,
  p_razorpay_plan_id text,
  p_razorpay_subscription_id text,
  p_amount_inr integer,
  p_short_url text default null,
  p_razorpay_customer_id text default null
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
    razorpay_subscription_id, razorpay_customer_id, amount_inr, short_url
  )
  values (
    p_membership_id, mship.facility_id, mship.member_id, p_razorpay_plan_id,
    p_razorpay_subscription_id, p_razorpay_customer_id, p_amount_inr, p_short_url
  )
  on conflict (razorpay_subscription_id) do update
    set short_url = excluded.short_url, updated_at = now()
  returning * into result;

  return result;
end;
$$;

grant execute on function record_membership_subscription(uuid, text, text, integer, text, text) to authenticated, anon;

-- ─────────────────────────────────────────────────────────────────────────
-- apply_subscription_webhook — forward-only status update from the
-- razorpay-webhook function's subscription.* events.
-- ─────────────────────────────────────────────────────────────────────────
create function apply_subscription_webhook(
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
    where id = sub.id;
end;
$$;

grant execute on function apply_subscription_webhook(text, membership_subscription_status, integer, date, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- record_subscription_charge — one successful monthly cycle. Records the
-- money in `payments` (idempotent on razorpay_payment_id) and rolls the
-- membership's end_date forward by the plan's duration so the member stays
-- "active" as long as auto-pay keeps succeeding.
-- ─────────────────────────────────────────────────────────────────────────
create function record_subscription_charge(
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
  select * into plan from membership_plans where id = mship.plan_id;

  insert into payments (facility_id, member_id, membership_id, amount_inr, status, razorpay_payment_id, paid_at, payment_method)
  values (sub.facility_id, sub.member_id, sub.membership_id, p_amount_inr, 'paid', p_razorpay_payment_id, p_paid_at, 'upi_autopay');

  update memberships
    set end_date = greatest(end_date, current_date) + coalesce(plan.duration_days, 30),
        status = 'active'
    where id = sub.membership_id;

  update membership_subscriptions
    set status = 'active', charge_count = charge_count + 1, updated_at = now()
    where id = sub.id;
end;
$$;

grant execute on function record_subscription_charge(text, integer, text, timestamptz) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_membership_revenue_timeseries — "the amount received on that date /
-- month / year": paid membership payments bucketed by day / month / year.
-- ─────────────────────────────────────────────────────────────────────────
create function get_membership_revenue_timeseries(
  p_facility_id uuid,
  p_granularity text default 'month',
  p_from date default null,
  p_to date default null
) returns table (bucket date, amount_inr bigint, payment_count bigint)
language sql
stable
as $$
  with bounds as (
    select
      coalesce(p_from, (current_date - interval '11 months')::date) as from_d,
      coalesce(p_to, current_date) as to_d,
      case when p_granularity in ('day', 'month', 'year') then p_granularity else 'month' end as grain
  )
  select
    date_trunc((select grain from bounds), p.created_at)::date as bucket,
    sum(p.amount_inr)::bigint as amount_inr,
    count(*)::bigint as payment_count
  from payments p, bounds
  where p.facility_id = p_facility_id
    and p.membership_id is not null
    and p.status = 'paid'
    and p.created_at >= bounds.from_d
    and p.created_at < (bounds.to_d + 1)
  group by 1
  order by 1;
$$;

grant execute on function get_membership_revenue_timeseries(uuid, text, date, date) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- Public self sign-up (/join/<facilityId>) — exactly two anon-callable
-- SECURITY DEFINER functions.
-- ═══════════════════════════════════════════════════════════════════════════

create function get_public_membership_signup_info(p_facility_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'facilityId', f.id,
    'facilityName', f.name,
    'city', coalesce(f.city, ''),
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', mp.id, 'name', mp.name, 'priceInr', mp.price_inr,
        'durationDays', mp.duration_days, 'features', mp.features
      ) order by mp.price_inr)
      from membership_plans mp
      where mp.facility_id = f.id and mp.is_active
    ), '[]'::jsonb)
  )
  from facilities f
  where f.id = p_facility_id;
$$;

grant execute on function get_public_membership_signup_info(uuid) to anon, authenticated;

-- Get-or-create the member by (facility, phone), then create a membership
-- marked self-registered (created_by NULL) with a pending payment. Returns
-- the ids the client needs to kick off the subscription mandate.
create function public_start_membership_signup(
  p_facility_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_plan_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  plan membership_plans;
  v_member_id uuid;
  computed_end date;
  v_membership_id uuid;
begin
  if coalesce(trim(p_full_name), '') = '' or coalesce(trim(p_phone), '') = '' then
    raise exception 'Name and phone are required.' using errcode = '22023';
  end if;

  select * into plan from membership_plans
    where id = p_plan_id and facility_id = p_facility_id and is_active;
  if plan.id is null then
    raise exception 'Membership plan not available.' using errcode = '23503';
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
          case when computed_end >= current_date then 'active' else 'expired' end,
          current_date, computed_end, null, plan.price_inr)
  returning id into v_membership_id;

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

grant execute on function public_start_membership_signup(uuid, text, text, text, uuid) to anon, authenticated;