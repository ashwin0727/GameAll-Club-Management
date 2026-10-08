-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching enrollment — Razorpay online billing.
--
--   ONE_TIME program → a Razorpay Payment Link for the enrollment fee.
--   MONTHLY  program → a Razorpay Subscription (UPI AutoPay) charging the
--                      per-month fee until the program's end date.
--
-- Money is recorded exactly like an offline payment: a paid `payments` row
-- carrying coaching_enrollment_id (0085). Pending Payments, Finance and
-- receipts therefore need no changes — the enrollment's price_minor remains
-- the total OBLIGATION and each gateway charge just settles part of it.
--
-- Design: docs/superpowers/specs/2026-10-07-coaching-online-payments-design.md
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- Fee type. Programs default to ONE_TIME so every existing program behaves
-- as before. For MONTHLY, default_price_minor is the PER-MONTH fee.
-- ─────────────────────────────────────────────────────────────────────────
alter table coaching_programs
  add column if not exists fee_type text not null default 'ONE_TIME'
    check (fee_type in ('ONE_TIME', 'MONTHLY'));

-- The enrollment snapshots the program's fee model so a later program edit
-- never changes what an existing student owes or how they are billed.
alter table coaching_enrollments
  add column if not exists fee_type text not null default 'ONE_TIME'
    check (fee_type in ('ONE_TIME', 'MONTHLY')),
  add column if not exists billing_cycles integer not null default 1
    check (billing_cycles >= 1);


-- Number of monthly charges from the enrollment start to the program end:
-- one on the start date plus one per full month elapsed (min 1).
--   2026-01-15 → 2026-03-14  =>  2   (Jan 15, Feb 15)
--   2026-01-15 → 2026-03-15  =>  3   (Jan 15, Feb 15, Mar 15)
--   2026-01-31 → 2026-02-28  =>  1
-- Web and Flutter call this through RPC (never re-implement the month maths
-- client-side) so the total they show always equals what the trigger stores.
create or replace function coaching_billing_cycles(p_start date, p_end date)
returns integer
language sql
immutable
as $$
  select case
    when p_start is null or p_end is null or p_end < p_start then 1
    else greatest(1,
      (extract(year from age(p_end::timestamp, p_start::timestamp)) * 12
        + extract(month from age(p_end::timestamp, p_start::timestamp)))::integer + 1)
  end;
$$;

grant execute on function coaching_billing_cycles(date, date) to authenticated;

create or replace function coaching_enrollment_snapshot_fee_type()
returns trigger
language plpgsql
as $$
declare
  v_fee_type text;
  v_end date;
begin
  select fee_type, end_date into v_fee_type, v_end
    from coaching_programs where id = new.program_id;
  if v_fee_type = 'MONTHLY' then
    new.fee_type := 'MONTHLY';
    new.billing_cycles := coaching_billing_cycles(new.start_date, v_end);
  end if;
  return new;
end;
$$;

drop trigger if exists coaching_enrollments_snapshot_fee_type on coaching_enrollments;
create trigger coaching_enrollments_snapshot_fee_type
  before insert on coaching_enrollments
  for each row execute function coaching_enrollment_snapshot_fee_type();


-- ─────────────────────────────────────────────────────────────────────────
-- set_coaching_program_fee_type — separate from create/update_coaching_program
-- so those (many-parameter) signatures stay untouched.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function set_coaching_program_fee_type(p_program_id uuid, p_fee_type text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  p coaching_programs;
begin
  select * into p from coaching_programs where id = p_program_id;
  if p.id is null then
    raise exception 'Program not found.' using errcode = 'P0002';
  end if;
  if not has_permission(p.facility_id, 'COACHING_MANAGE_PROGRAMS') then
    raise exception 'You don''t have permission to manage programs.' using errcode = '42501';
  end if;
  if p_fee_type not in ('ONE_TIME', 'MONTHLY') then
    raise exception 'Unknown fee type.' using errcode = '22023';
  end if;
  if p_fee_type = 'MONTHLY' and (p.start_date is null or p.end_date is null) then
    raise exception 'A monthly program needs a start and end date.' using errcode = '23514';
  end if;
  update coaching_programs set fee_type = p_fee_type where id = p_program_id;
end;
$$;

grant execute on function set_coaching_program_fee_type(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- coaching_enrollment_billing — the Razorpay link / subscription behind an
-- enrollment. One row per enrollment. Writes go through the RPCs below.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists coaching_enrollment_billing (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null unique references coaching_enrollments (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  kind text not null check (kind in ('PAYMENT_LINK', 'SUBSCRIPTION')),
  status text not null default 'CREATED'
    check (status in ('CREATED', 'AUTHENTICATED', 'ACTIVE', 'PENDING', 'HALTED', 'PAID', 'CANCELLED', 'COMPLETED', 'EXPIRED')),
  -- Amount of ONE charge (the whole fee for a link, the monthly fee for a subscription).
  amount_minor integer not null check (amount_minor > 0),
  total_cycles integer not null default 1 check (total_cycles >= 1),
  charge_count integer not null default 0,
  razorpay_payment_link_id text unique,
  razorpay_plan_id text,
  razorpay_subscription_id text unique,
  short_url text,
  current_start date,
  current_end date,
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists coaching_enrollment_billing_facility_idx on coaching_enrollment_billing (facility_id, status);

alter table coaching_enrollment_billing enable row level security;
drop policy if exists "coaching_enrollment_billing_select" on coaching_enrollment_billing;
create policy "coaching_enrollment_billing_select" on coaching_enrollment_billing for select
  using (has_permission(facility_id, 'COACHING_VIEW'));

drop trigger if exists coaching_enrollment_billing_set_updated_at on coaching_enrollment_billing;
create trigger coaching_enrollment_billing_set_updated_at
  before update on coaching_enrollment_billing
  for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- get_coaching_billing_context — everything the create/cancel edge functions
-- need, resolved server-side under the CALLER's session so the permission
-- check is real and no client-supplied amount is ever trusted.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_coaching_billing_context(p_enrollment_id uuid)
returns jsonb
language plpgsql
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
  select * into e from coaching_enrollments where id = p_enrollment_id;
  if e.id is null then
    raise exception 'Enrollment not found.' using errcode = 'P0002';
  end if;
  if not has_permission(e.facility_id, 'COACHING_MANAGE_ENROLLMENTS') then
    raise exception 'You don''t have permission to manage enrollments.' using errcode = '42501';
  end if;

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

grant execute on function get_coaching_billing_context(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- record_coaching_enrollment_billing — saves the Razorpay objects the create
-- function just made. A previous CANCELLED / EXPIRED row is replaced (so a
-- dead link can be regenerated); any live row is returned untouched.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function record_coaching_enrollment_billing(
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
  select * into e from coaching_enrollments where id = p_enrollment_id;
  if e.id is null then
    raise exception 'Enrollment not found.' using errcode = 'P0002';
  end if;
  if not has_permission(e.facility_id, 'COACHING_MANAGE_ENROLLMENTS') then
    raise exception 'You don''t have permission to manage enrollments.' using errcode = '42501';
  end if;
  if p_kind not in ('PAYMENT_LINK', 'SUBSCRIPTION') then
    raise exception 'Unknown billing kind.' using errcode = '22023';
  end if;

  insert into coaching_enrollment_billing (
    enrollment_id, facility_id, kind, amount_minor, total_cycles,
    razorpay_payment_link_id, razorpay_plan_id, razorpay_subscription_id, short_url, created_by
  ) values (
    e.id, e.facility_id, p_kind, p_amount_minor, greatest(p_total_cycles, 1),
    p_payment_link_id, p_plan_id, p_subscription_id, p_short_url, auth.uid()
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
    current_end = null,
    created_by = excluded.created_by
  where coaching_enrollment_billing.status in ('CANCELLED', 'EXPIRED')
  returning * into result;

  if result.id is null then
    select * into result from coaching_enrollment_billing where enrollment_id = e.id;
  end if;
  return result;
end;
$$;

grant execute on function record_coaching_enrollment_billing(uuid, text, integer, integer, text, text, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- mark_coaching_billing_cancelled — called by cancel-coaching-enrollment-
-- billing AFTER Razorpay confirmed the cancellation. Terminal states stay.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function mark_coaching_billing_cancelled(p_enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  e coaching_enrollments;
begin
  select * into e from coaching_enrollments where id = p_enrollment_id;
  if e.id is null then
    raise exception 'Enrollment not found.' using errcode = 'P0002';
  end if;
  if not has_permission(e.facility_id, 'COACHING_MANAGE_ENROLLMENTS') then
    raise exception 'You don''t have permission to manage enrollments.' using errcode = '42501';
  end if;
  update coaching_enrollment_billing
     set status = 'CANCELLED'
   where enrollment_id = p_enrollment_id
     and status not in ('PAID', 'CANCELLED', 'COMPLETED', 'EXPIRED');
end;
$$;

grant execute on function mark_coaching_billing_cancelled(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- apply_coaching_billing_webhook — forward-only status update from the
-- razorpay-webhook function. Returns whether the id belongs to a coaching
-- enrollment, so the webhook can fall back to the membership path when not.
-- Service role only.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function apply_coaching_billing_webhook(
  p_razorpay_subscription_id text default null,
  p_razorpay_payment_link_id text default null,
  p_status text default null,
  p_charge_count integer default null,
  p_current_start date default null,
  p_current_end date default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  b coaching_enrollment_billing;
  rank_map jsonb := '{"CREATED":0,"AUTHENTICATED":1,"ACTIVE":2,"PENDING":2,"HALTED":3,"PAID":4,"CANCELLED":4,"COMPLETED":4,"EXPIRED":4}';
begin
  select * into b from coaching_enrollment_billing
   where (p_razorpay_subscription_id is not null and razorpay_subscription_id = p_razorpay_subscription_id)
      or (p_razorpay_payment_link_id is not null and razorpay_payment_link_id = p_razorpay_payment_link_id)
   limit 1;
  if b.id is null then
    return false;
  end if;

  update coaching_enrollment_billing
     set status = case
           when p_status is null then status
           -- never leave a terminal state; ACTIVE <-> PENDING may move both ways
           when (rank_map ->> status)::int = 4 then status
           -- a halted subscription recovers once the student fixes the mandate and a charge lands
           when status = 'HALTED' and p_status in ('ACTIVE', 'PENDING') then p_status
           when (rank_map ->> status)::int > (rank_map ->> p_status)::int
                and status not in ('ACTIVE', 'PENDING') then status
           else p_status
         end,
         charge_count = coalesce(p_charge_count, charge_count),
         current_start = coalesce(p_current_start, current_start),
         current_end = coalesce(p_current_end, current_end)
   where id = b.id;
  return true;
end;
$$;

revoke execute on function apply_coaching_billing_webhook(text, text, text, integer, date, date) from public, anon, authenticated;
grant execute on function apply_coaching_billing_webhook(text, text, text, integer, date, date) to service_role;


-- ─────────────────────────────────────────────────────────────────────────
-- record_coaching_gateway_payment — one successful Razorpay charge. Inserts
-- the paid `payments` row (idempotent on razorpay_payment_id) so Pending
-- Payments / Finance see it like any other payment. A paid link also flips
-- the billing row to PAID. A charge that actually happened is always
-- recorded, even if the enrollment was cancelled in the meantime.
-- Returns whether the id belongs to a coaching enrollment. Service role only.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function record_coaching_gateway_payment(
  p_razorpay_subscription_id text default null,
  p_razorpay_payment_link_id text default null,
  p_amount_minor bigint default 0,
  p_razorpay_payment_id text default null,
  p_paid_at timestamptz default now()
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  b coaching_enrollment_billing;
begin
  select * into b from coaching_enrollment_billing
   where (p_razorpay_subscription_id is not null and razorpay_subscription_id = p_razorpay_subscription_id)
      or (p_razorpay_payment_link_id is not null and razorpay_payment_link_id = p_razorpay_payment_link_id)
   limit 1;
  if b.id is null then
    return false;
  end if;
  if p_razorpay_payment_id is null or p_amount_minor <= 0 then
    raise exception 'A gateway payment needs an id and an amount.' using errcode = '22023';
  end if;

  if not exists (select 1 from payments where razorpay_payment_id = p_razorpay_payment_id) then
    insert into payments (
      facility_id, member_id, coaching_enrollment_id, amount_inr, status,
      payment_method, paid_at, razorpay_payment_id
    ) values (
      b.facility_id, null, b.enrollment_id, round(p_amount_minor / 100.0), 'paid'::payment_status,
      case when b.kind = 'SUBSCRIPTION' then 'UPI AutoPay' else 'Razorpay' end,
      coalesce(p_paid_at, now()), p_razorpay_payment_id
    );
  end if;

  if b.kind = 'PAYMENT_LINK' then
    update coaching_enrollment_billing set status = 'PAID', charge_count = 1 where id = b.id;
  end if;
  return true;
end;
$$;

revoke execute on function record_coaching_gateway_payment(text, text, bigint, text, timestamptz) from public, anon, authenticated;
grant execute on function record_coaching_gateway_payment(text, text, bigint, text, timestamptz) to service_role;
