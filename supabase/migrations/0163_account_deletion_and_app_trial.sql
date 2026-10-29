-- ═══════════════════════════════════════════════════════════════════════════
-- Account deletion (Google Play requirement) and the free trial for clubs created in the mobile app.
--
-- ACCOUNT DELETION
--   Deleting an account removes everything: the facility and all its data, the staff who only worked there, and the person's
--   sign-in. The one exception is money still waiting to be settled: while any online payment of the club has not been marked
--   Settled, the account is CLOSED straight away (sign-in blocked, bookings stopped, Auto Pay cancelled) but the payment records
--   are kept; the deletion then completes by itself once everything is settled. The work is done by the delete-account edge
--   function (and the notification-worker, which finishes the waiting ones) using the functions below.
--
-- MOBILE FREE TRIAL
--   The Android app does not sell plans (Google Play billing rules). A club created in the app is given the free trial
--   directly, with no payment step. The plan is paid for on the web, where the trial period carries over.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Bookkeeping ────────────────────────────────────────────────────────────────
create table if not exists platform_settings (
  key   text primary key,
  value text not null
);
alter table platform_settings enable row level security;   -- no policies: service role only

-- A closed account waiting for its payments to be settled. No FK to the user on purpose: the user is deleted at the end.
create table if not exists account_deletions (
  user_id      uuid primary key,
  email        text,
  requested_at timestamptz not null default now(),
  status       text not null default 'pending_settlement' check (status in ('pending_settlement', 'completed')),
  completed_at timestamptz
);
alter table account_deletions enable row level security;   -- no policies: service role only

-- ── What deleting this person would involve ───────────────────────────────────────
-- Money still waiting to be settled for the facilities this person owns.
create or replace function account_deletion_blockers(p_user uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'unsettledCount', count(*),
    'unsettledInr', coalesce(sum(p.amount_inr), 0)
  )
  from payments p
  join facilities f on f.id = p.facility_id
  where f.owner_id = p_user
    and _is_online_payment(p) and p.status::text = 'paid'
    and not exists (select 1 from payment_settlements s where s.payment_id = p.id);
$$;

-- The facilities, recurring payments and other people tied to this account.
create or replace function account_deletion_plan(p_user uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_facilities uuid[];
  v_subs text[];
  v_orphans uuid[];
begin
  select coalesce(array_agg(id), '{}') into v_facilities from facilities where owner_id = p_user;

  select coalesce(array_agg(distinct s), '{}') into v_subs from (
    select razorpay_subscription_id as s from facility_subscriptions where facility_id = any (v_facilities)
    union all select razorpay_subscription_id from membership_subscriptions where facility_id = any (v_facilities)
    union all select razorpay_subscription_id from coaching_enrollment_billing where facility_id = any (v_facilities)
    union all select razorpay_subscription_id from plan_checkouts where facility_id = any (v_facilities)
  ) q where s is not null;

  -- Staff who belong only to the facilities being deleted would be left with an account and nothing to open.
  select coalesce(array_agg(distinct fu.user_id), '{}') into v_orphans
  from facility_users fu
  where fu.facility_id = any (v_facilities) and fu.user_id <> p_user
    and not exists (select 1 from facility_users o where o.user_id = fu.user_id and o.facility_id <> all (v_facilities))
    and not exists (select 1 from facilities f where f.owner_id = fu.user_id and f.id <> all (v_facilities));

  return jsonb_build_object('facilities', to_jsonb(v_facilities), 'razorpaySubscriptions', to_jsonb(v_subs), 'orphanStaff', to_jsonb(v_orphans));
end;
$$;

-- ── Doing it ───────────────────────────────────────────────────────────────────────
-- Close the club without deleting records: used while money is still waiting to be settled.
create or replace function close_owned_facilities(p_user uuid)
returns void
language sql security definer set search_path = public
as $$
  update facilities set status = 'INACTIVE' where owner_id = p_user;
$$;

-- Records written by this person in other people's facilities (created_by, reported_by, ...) point at their profile with a
-- foreign key that would block deleting it. Re-point every such column at the "Deleted user" placeholder first.
create or replace function reassign_user_references(p_user uuid, p_placeholder uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r record;
begin
  for r in
    select c.conrelid::regclass as tbl, a.attname as col
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f' and array_length(c.conkey, 1) = 1
      and c.confdeltype in ('a', 'r')                      -- NO ACTION / RESTRICT: these would block the delete
      and c.confrelid in ('public.profiles'::regclass, 'auth.users'::regclass)
  loop
    execute format('update %s set %I = $1 where %I = $2', r.tbl, r.col, r.col) using p_placeholder, p_user;
  end loop;
end;
$$;

-- Delete the facilities this person owns, and everything under them (ON DELETE CASCADE).
create or replace function delete_owned_facilities(p_user uuid)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  n integer;
begin
  delete from facilities where owner_id = p_user;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Service role only.
revoke all on function account_deletion_blockers(uuid) from public, anon, authenticated;
revoke all on function account_deletion_plan(uuid) from public, anon, authenticated;
revoke all on function close_owned_facilities(uuid) from public, anon, authenticated;
revoke all on function reassign_user_references(uuid, uuid) from public, anon, authenticated;
revoke all on function delete_owned_facilities(uuid) from public, anon, authenticated;
grant execute on function account_deletion_blockers(uuid) to service_role;
grant execute on function account_deletion_plan(uuid) to service_role;
grant execute on function close_owned_facilities(uuid) to service_role;
grant execute on function reassign_user_references(uuid, uuid) to service_role;
grant execute on function delete_owned_facilities(uuid) to service_role;

-- ── Mobile: the free trial without a payment step ───────────────────────────────────
-- Only the owner, only once, only for a club that has no plan row yet. The club gets the Advanced plan for the trial period;
-- when it ends without a plan being paid for on the web it falls back to Basic (effective_plan_code).
create or replace function start_free_trial(p_facility_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  pl plans;
begin
  if not exists (select 1 from facilities f where f.id = p_facility_id and f.owner_id = auth.uid()) then
    raise exception 'Only the facility owner can start the trial.' using errcode = '42501';
  end if;
  if exists (select 1 from facility_subscriptions where facility_id = p_facility_id) then
    return my_facility_plan(p_facility_id);                  -- already has a plan or a trial: nothing to do
  end if;

  select * into pl from plans where code = 'advanced';
  if pl.code is null then
    return null;                                              -- plans not set up: leave the club unrestricted
  end if;

  insert into facility_subscriptions (facility_id, plan_name, price_minor, currency, billing_interval, status, valid_till, features, plan_code, selected_at, trial_used)
  values (p_facility_id, pl.name, pl.monthly_minor, pl.currency, 'month', 'trialing', (current_date + make_interval(months => pl.trial_months))::date, pl.features, pl.code, now(), true);

  return my_facility_plan(p_facility_id);
end;
$$;
grant execute on function start_free_trial(uuid) to authenticated;
