-- GameAll's own plans (Basic / Advanced) and what each one includes.
--
-- A plan is a set of PAGES (the same page list the role editor uses — migration 0155), a few feature switches and a
-- couple of limits. A club's effective access is what its plan includes AND what the person's role allows: if Coaching
-- isn't in the plan, nobody at that club can use it, owner included.
--
--   plans / plan_pages        the catalogue (prices, limits, which pages each plan includes)
--   facility_subscriptions    already holds a club's plan; gains plan_code + the trial bookkeeping
--   has_permission()          now also requires the permission's page to be in the club's plan
--   limits                    courts / staff counted by triggers
--
-- Clubs with no plan row (every club that exists today, and any club still in onboarding) are NOT restricted. The
-- restriction starts when the owner picks a plan. After a trial ends without payment the club falls back to Basic; online
-- payment for plans is a separate step.

-- ── 1. Catalogue ──────────────────────────────────────────────────────────────
create table if not exists plans (
  code           text primary key,
  name           text not null,
  description    text,
  monthly_minor  integer not null check (monthly_minor >= 0),   -- paise
  yearly_minor   integer not null check (yearly_minor >= 0),
  currency       text not null default 'INR',
  max_courts     integer,                                       -- null = unlimited
  max_staff      integer,                                       -- non-owner staff; null = unlimited
  feature_flags  text[] not null default '{}',                  -- e.g. AUTOPAY
  features       text[] not null default '{}',                  -- the bullet list shown on the plan card
  is_popular     boolean not null default false,
  trial_days     integer not null default 90,                   -- shown on the plan card
  trial_months   integer not null default 3,                    -- how the first charge is scheduled (calendar months)
  sort_order     integer not null default 0
);

create table if not exists plan_pages (
  plan_code  text not null references plans (code) on delete cascade,
  page_key   text not null references access_pages (page_key) on delete cascade,
  primary key (plan_code, page_key)
);

alter table plans enable row level security;
alter table plan_pages enable row level security;
drop policy if exists plans_select on plans;
create policy plans_select on plans for select using (auth.uid() is not null);
drop policy if exists plan_pages_select on plan_pages;
create policy plan_pages_select on plan_pages for select using (auth.uid() is not null);

insert into plans (code, name, description, monthly_minor, yearly_minor, max_courts, max_staff, feature_flags, features, is_popular, sort_order) values
  ('basic', 'Basic', 'Everything you need to take bookings, run memberships and coaching, and track payments yourself.', 12900, 129900, null, null, '{}',
    array['Today / Home and Calendar', 'Tournaments management', 'Guest booking', 'Memberships: manual payment tracking (plan and schedule)', 'Coaching: manual payment tracking (programs and students)', 'Reports and analytics', 'Next-day (T+1) payouts'],
    false, 1),
  ('advanced', 'Advanced', 'The full system: automatic payment collection, finance, staff, maintenance and the fastest payouts.', 19900, 199900, null, null, array['AUTOPAY'],
    array['Everything in Basic', 'Guest player lists', 'Memberships: automatic payment tracking', 'Coaching: automatic payment tracking, with schedule', 'Maintenance management', 'Staff management', 'Finance management', 'Payouts within 5 minutes'],
    true, 2)
on conflict (code) do update set
  name = excluded.name, description = excluded.description, monthly_minor = excluded.monthly_minor,
  yearly_minor = excluded.yearly_minor, max_courts = excluded.max_courts, max_staff = excluded.max_staff,
  feature_flags = excluded.feature_flags, features = excluded.features, is_popular = excluded.is_popular,
  sort_order = excluded.sort_order, trial_days = excluded.trial_days, trial_months = excluded.trial_months;

delete from plan_pages;
insert into plan_pages (plan_code, page_key)
select 'basic', page_key from access_pages where page_key in (
  'HOME', 'CALENDAR', 'TOURNAMENTS', 'GUEST_BOOKINGS', 'REFUNDS',
  'MEMBERSHIP_DASHBOARD', 'MEMBERSHIP_SCHEDULE', 'MEMBERSHIP_PLANS', 'MEMBERSHIP_SESSIONS',
  'COACHING_OVERVIEW', 'COACHING_PROGRAMS', 'COACHING_STUDENTS',
  'REPORT_OVERVIEW', 'REPORT_COURT_UTILIZATION', 'REPORT_REVENUE', 'REPORT_MEMBERSHIPS', 'REPORT_GUEST_BOOKINGS',
  'FACILITY_SETTINGS'
);
insert into plan_pages (plan_code, page_key) select 'advanced', page_key from access_pages;

-- ── 2. A club's subscription ────────────────────────────────────────────────────
alter table facility_subscriptions
  add column if not exists plan_code text references plans (code),
  add column if not exists selected_at timestamptz,
  add column if not exists trial_used boolean not null default false,
  add column if not exists razorpay_subscription_id text;

alter table facility_subscriptions drop constraint if exists facility_subscriptions_status_check;
alter table facility_subscriptions
  add constraint facility_subscriptions_status_check check (status in ('active', 'trialing', 'cancelled'));

-- ── 3. What a club's plan currently grants ───────────────────────────────────────
-- The plan whose rules apply today: the chosen plan while it is active or in trial, Basic once it has lapsed, and null for
-- a club with no plan (unrestricted).
create or replace function effective_plan_code(p_facility uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select case
    when s.plan_code is null then null
    when s.status in ('active', 'trialing') and s.valid_till >= current_date then s.plan_code
    else 'basic'
  end
  from facility_subscriptions s
  where s.facility_id = p_facility;
$$;

create or replace function plan_includes_page(p_facility uuid, p_page_key text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case
    when effective_plan_code(p_facility) is null then true
    else exists (select 1 from plan_pages pp where pp.plan_code = effective_plan_code(p_facility) and pp.page_key = p_page_key)
  end;
$$;

create or replace function plan_has_feature(p_facility uuid, p_feature text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case
    when effective_plan_code(p_facility) is null then true
    else coalesce((select p_feature = any (p.feature_flags) from plans p where p.code = effective_plan_code(p_facility)), false)
  end;
$$;

-- A permission key is in the plan when the page it belongs to is. Keys that no page owns are never restricted.
create or replace function permission_in_plan(p_facility uuid, p_permission text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case
    when effective_plan_code(p_facility) is null then true
    when not exists (
      select 1 from access_pages ap
      where p_permission = any (ap.view_keys) or p_permission = any (ap.edit_keys) or p_permission = any (ap.extra_keys)
    ) then true
    else exists (
      select 1 from access_pages ap
      join plan_pages pp on pp.page_key = ap.page_key and pp.plan_code = effective_plan_code(p_facility)
      where p_permission = any (ap.view_keys) or p_permission = any (ap.edit_keys) or p_permission = any (ap.extra_keys)
    )
  end;
$$;

grant execute on function effective_plan_code(uuid) to authenticated;
grant execute on function plan_includes_page(uuid, text) to authenticated;
grant execute on function plan_has_feature(uuid, text) to authenticated, service_role;
grant execute on function permission_in_plan(uuid, text) to authenticated;

-- has_permission (from 0118) plus the plan: the permission must belong to a page the club's plan includes.
create or replace function has_permission(p_facility uuid, p_permission text) returns boolean
language sql security definer stable
set search_path = public
as $$
  select
    (
      exists (
        select 1 from facilities f
        where f.id = p_facility and f.owner_id = auth.uid()
      )
      or exists (
        select 1 from facility_users fu
        where fu.facility_id = p_facility
          and fu.user_id = auth.uid()
          and fu.status = 'ACTIVE'
          and (
            fu.role = 'owner'
            or exists (
              select 1 from role_permissions rp
              where rp.role_id = effective_role_id(p_facility, auth.uid())
                and rp.permission_key = p_permission
            )
          )
      )
    )
    and permission_in_plan(p_facility, p_permission);
$$;
grant execute on function has_permission(uuid, text) to authenticated;

-- ── 4. Reading and choosing a plan ────────────────────────────────────────────────
create or replace function list_plans()
returns table (
  code text, name text, description text, monthly_minor integer, yearly_minor integer, currency text,
  max_courts integer, max_staff integer, feature_flags text[], features text[], is_popular boolean,
  trial_days integer, sort_order integer, page_keys text[]
)
language sql stable security definer set search_path = public
as $$
  select p.code, p.name, p.description, p.monthly_minor, p.yearly_minor, p.currency, p.max_courts, p.max_staff,
         p.feature_flags, p.features, p.is_popular, p.trial_days, p.sort_order,
         coalesce((select array_agg(pp.page_key order by pp.page_key) from plan_pages pp where pp.plan_code = p.code), '{}')
  from plans p
  where auth.uid() is not null
  order by p.sort_order;
$$;
grant execute on function list_plans() to authenticated;

-- The signed-in member's view of their club's plan; null when the club has none (unrestricted).
create or replace function my_facility_plan(p_facility_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  s facility_subscriptions;
  eff text;
  pl plans;
begin
  if not is_facility_member(p_facility_id) and not exists (select 1 from facilities f where f.id = p_facility_id and f.owner_id = auth.uid()) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select * into s from facility_subscriptions where facility_id = p_facility_id;
  if s.id is null or s.plan_code is null then
    return null;
  end if;
  eff := effective_plan_code(p_facility_id);
  select * into pl from plans where code = eff;
  return jsonb_build_object(
    'planCode', s.plan_code,
    'effectiveCode', eff,
    'name', (select name from plans where code = s.plan_code),
    'status', s.status,
    'interval', s.billing_interval,
    'priceMinor', s.price_minor,
    'validTill', s.valid_till,
    'onTrial', s.status = 'trialing' and s.valid_till >= current_date,
    'lapsed', not (s.status in ('active', 'trialing') and s.valid_till >= current_date),
    'daysLeft', (s.valid_till - current_date),
    'maxCourts', pl.max_courts,
    'maxStaff', pl.max_staff,
    'features', to_jsonb(coalesce(pl.feature_flags, '{}')),
    'pageKeys', coalesce((select to_jsonb(array_agg(pp.page_key order by pp.page_key)) from plan_pages pp where pp.plan_code = eff), '[]'::jsonb)
  );
end;
$$;
grant execute on function my_facility_plan(uuid) to authenticated;

-- Choosing a plan is a payment-mandate flow, not a plain write. The owner picks a plan; this validates the choice and says
-- when the first charge falls (3 months after the first selection, with the free trial in between). The create-plan-subscription
-- edge function then opens the Razorpay mandate for that amount, and the plan only becomes active once the mandate is confirmed
-- (activate_plan_checkout).
create table if not exists plan_checkouts (
  id                       uuid primary key default gen_random_uuid(),
  facility_id              uuid not null references facilities (id) on delete cascade,
  plan_code                text not null references plans (code),
  billing_interval         text not null check (billing_interval in ('month', 'year')),
  razorpay_subscription_id text unique,
  first_charge_on          date,                       -- null = charged as soon as the mandate is confirmed
  is_trial                 boolean not null default false,
  status                   text not null default 'created' check (status in ('created', 'confirmed', 'abandoned')),
  created_by               uuid references auth.users (id),
  created_at               timestamptz not null default now()
);
alter table plan_checkouts enable row level security;   -- service role only; no policies

drop function if exists select_facility_plan(uuid, text, text);

create or replace function begin_plan_change(p_facility_id uuid, p_plan_code text, p_interval text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  pl plans;
  s facility_subscriptions;
  v_courts integer;
  v_staff integer;
  v_first date;
  v_trial boolean := false;
begin
  if not exists (select 1 from facilities f where f.id = p_facility_id and f.owner_id = auth.uid())
     and not exists (select 1 from facility_users fu where fu.facility_id = p_facility_id and fu.user_id = auth.uid() and fu.status = 'ACTIVE' and fu.role = 'owner') then
    raise exception 'Only the facility owner can choose the plan.' using errcode = '42501';
  end if;
  if p_interval not in ('month', 'year') then
    raise exception 'Choose monthly or yearly billing.' using errcode = '22023';
  end if;
  select * into pl from plans where code = p_plan_code;
  if pl.code is null then
    raise exception 'That plan does not exist.' using errcode = 'P0002';
  end if;

  -- A plan with limits can't be chosen by a club that already exceeds them.
  select count(*) into v_courts from courts where facility_id = p_facility_id and not archived;
  select count(*) into v_staff from facility_users
    where facility_id = p_facility_id and role <> 'owner' and status in ('ACTIVE', 'INVITED');
  if pl.max_courts is not null and v_courts > pl.max_courts then
    raise exception '% allows up to % courts and you have %. Choose Advanced, or remove some courts first.', pl.name, pl.max_courts, v_courts using errcode = '23514';
  end if;
  if pl.max_staff is not null and v_staff > pl.max_staff then
    raise exception '% allows up to % staff and you have %. Choose Advanced, or remove some staff first.', pl.name, pl.max_staff, v_staff using errcode = '23514';
  end if;

  select * into s from facility_subscriptions where facility_id = p_facility_id;
  if s.id is null or not coalesce(s.trial_used, false) then
    v_trial := true;                                              -- first plan: free for the trial, first charge after it
    v_first := (current_date + make_interval(months => pl.trial_months))::date;
  elsif s.status in ('active', 'trialing') and s.valid_till >= current_date then
    v_first := s.valid_till + 1;                                  -- changing plan: the new price starts after the paid / trial period
  else
    v_first := null;                                              -- lapsed: charged when the mandate is confirmed
  end if;

  return jsonb_build_object(
    'planCode', pl.code,
    'planName', pl.name,
    'interval', p_interval,
    'amountMinor', case when p_interval = 'year' then pl.yearly_minor else pl.monthly_minor end,
    'currency', pl.currency,
    'trial', v_trial,
    'trialDays', pl.trial_days,
    'firstChargeOn', v_first
  );
end;
$$;
grant execute on function begin_plan_change(uuid, text, text) to authenticated;

-- Service role only (the edge function): remember which Razorpay subscription belongs to which choice.
create or replace function record_plan_checkout(
  p_facility_id uuid, p_plan_code text, p_interval text, p_razorpay_subscription_id text,
  p_first_charge_on date, p_is_trial boolean, p_user uuid
) returns void
language sql security definer set search_path = public
as $$
  insert into plan_checkouts (facility_id, plan_code, billing_interval, razorpay_subscription_id, first_charge_on, is_trial, created_by)
  values (p_facility_id, p_plan_code, p_interval, p_razorpay_subscription_id, p_first_charge_on, p_is_trial, p_user);
$$;
revoke all on function record_plan_checkout(uuid, text, text, text, date, boolean, uuid) from public, anon, authenticated;
grant execute on function record_plan_checkout(uuid, text, text, text, date, boolean, uuid) to service_role;

-- Service role only: the owner authorised the mandate (signature verified by the edge function). The plan switches on now;
-- a first plan starts its free trial and is paid for on first_charge_on. Returns the Razorpay subscription it replaces, if any,
-- so the caller can cancel that one.
create or replace function activate_plan_checkout(p_razorpay_subscription_id text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  c plan_checkouts;
  pl plans;
  s facility_subscriptions;
  v_price integer;
  v_status text;
  v_valid date;
  v_old text;
begin
  select * into c from plan_checkouts where razorpay_subscription_id = p_razorpay_subscription_id;
  if c.id is null then
    raise exception 'Unknown plan checkout.' using errcode = 'P0002';
  end if;
  select * into pl from plans where code = c.plan_code;
  select * into s from facility_subscriptions where facility_id = c.facility_id;
  v_old := s.razorpay_subscription_id;
  v_price := case when c.billing_interval = 'year' then pl.yearly_minor else pl.monthly_minor end;

  if c.first_charge_on is not null then
    v_status := case when c.is_trial then 'trialing' else coalesce(s.status, 'trialing') end;
    v_valid := c.first_charge_on;                                  -- access runs to the day the first charge is due
  else
    v_status := 'active';
    v_valid := current_date + case when c.billing_interval = 'year' then 365 else 30 end;
  end if;

  insert into facility_subscriptions (facility_id, plan_name, price_minor, currency, billing_interval, status, valid_till, features, plan_code, selected_at, trial_used, razorpay_subscription_id)
  values (c.facility_id, pl.name, v_price, pl.currency, c.billing_interval, v_status, v_valid, pl.features, pl.code, now(), c.is_trial or coalesce(s.trial_used, false), p_razorpay_subscription_id)
  on conflict (facility_id) do update set
    plan_name = excluded.plan_name,
    price_minor = excluded.price_minor,
    billing_interval = excluded.billing_interval,
    status = excluded.status,
    valid_till = excluded.valid_till,
    features = excluded.features,
    plan_code = excluded.plan_code,
    selected_at = excluded.selected_at,
    trial_used = excluded.trial_used,
    razorpay_subscription_id = excluded.razorpay_subscription_id,
    updated_at = now();

  update plan_checkouts set status = 'confirmed' where id = c.id;
  update plan_checkouts set status = 'abandoned' where facility_id = c.facility_id and status = 'created' and id <> c.id;

  return jsonb_build_object('facilityId', c.facility_id, 'replacedSubscriptionId', v_old);
end;
$$;
revoke all on function activate_plan_checkout(text) from public, anon, authenticated;
grant execute on function activate_plan_checkout(text) to service_role;

-- Service role only (razorpay-webhook): a subscription.* event for a plan subscription. Returns false when the id is not a
-- plan subscription so the webhook carries on to the membership / coaching handlers.
create or replace function apply_plan_subscription_webhook(p_razorpay_subscription_id text, p_event text, p_current_end date)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  s facility_subscriptions;
begin
  select * into s from facility_subscriptions where razorpay_subscription_id = p_razorpay_subscription_id;
  if s.id is null then
    return false;
  end if;
  if p_event in ('subscription.charged', 'subscription.activated', 'subscription.resumed') then
    update facility_subscriptions
       set status = 'active', valid_till = greatest(valid_till, coalesce(p_current_end, valid_till)), updated_at = now()
     where id = s.id;
  elsif p_event in ('subscription.halted', 'subscription.cancelled', 'subscription.completed') then
    update facility_subscriptions set status = 'cancelled', updated_at = now() where id = s.id;   -- falls back to Basic
  end if;
  return true;
end;
$$;
revoke all on function apply_plan_subscription_webhook(text, text, date) from public, anon, authenticated;
grant execute on function apply_plan_subscription_webhook(text, text, date) to service_role;

-- ── 5. Limits ───────────────────────────────────────────────────────────────────
create or replace function plan_limit(p_facility uuid, p_what text)
returns integer
language sql stable security definer set search_path = public
as $$
  select case p_what when 'courts' then p.max_courts when 'staff' then p.max_staff end
  from plans p
  where p.code = effective_plan_code(p_facility);
$$;
grant execute on function plan_limit(uuid, text) to authenticated;

create or replace function enforce_plan_court_limit()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_max integer;
  v_count integer;
begin
  if new.archived or (tg_op = 'UPDATE' and not old.archived) then
    return new; -- only adding a court, or un-archiving one, can push a club over its limit
  end if;
  v_max := plan_limit(new.facility_id, 'courts');
  if v_max is null then
    return new;
  end if;
  select count(*) into v_count from courts where facility_id = new.facility_id and not archived and id is distinct from new.id;
  if v_count >= v_max then
    raise exception 'Your plan allows up to % courts. Upgrade to Advanced to add more.', v_max using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists courts_plan_limit on courts;
create trigger courts_plan_limit
  before insert or update of archived on courts
  for each row execute function enforce_plan_court_limit();

create or replace function enforce_plan_staff_limit()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_max integer;
  v_count integer;
begin
  if new.role = 'owner' or new.status not in ('ACTIVE', 'INVITED') then
    return new;
  end if;
  v_max := plan_limit(new.facility_id, 'staff');
  if v_max is null then
    return new;
  end if;
  select count(*) into v_count from facility_users
    where facility_id = new.facility_id and role <> 'owner' and status in ('ACTIVE', 'INVITED') and id is distinct from new.id;
  if v_count >= v_max then
    raise exception 'Your plan allows up to % staff. Upgrade to Advanced to add more.', v_max using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists facility_users_plan_limit on facility_users;
create trigger facility_users_plan_limit
  before insert or update of status, role on facility_users
  for each row execute function enforce_plan_staff_limit();
