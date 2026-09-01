-- ═══════════════════════════════════════════════════════════════════════════
-- Payment-incomplete status — Phase 8.
--
-- "Active" now requires a SETTLED payment (a gateway charge, or an explicit
-- owner "record payment" confirmation — a `paid` payments row with `paid_at`
-- set) inside the current billing cycle. Picking "Paid" on the create form
-- no longer counts on its own. Anything short of that (and not cancelled)
-- reads as `payment_incomplete` — renamed from `payment_not_initiated`.
--
--   billing cycle length = the membership's own duration_days (the Duration
--   chosen at creation). end_date is the next payment date and already
--   rolls forward per cycle. cycle_start = end_date - duration.
--
--   • membership_cycle_start / membership_is_settled / membership_display_status
--       — shared status helpers, so list / summary / detail agree.
--   • list_memberships          — display_status via the helper.
--   • get_membership_page_summary — active vs payment_incomplete counts;
--       revenue counts only settled (paid_at) payments. Return column
--       inactive_members → payment_incomplete_members.
--   • get_membership_detail     — displayStatus via the helper; timeline
--       "Payment received" only for settled payments.
--   • record_membership_payment — the explicit "cash received" step: settle
--       the current cycle's payment (create it if missing) and, when the
--       paid-through date has lapsed, start the next cycle.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- Shared status helpers
-- ─────────────────────────────────────────────────────────────────────────
create or replace function membership_cycle_start(p_start date, p_end date, p_duration integer)
returns date
language sql
immutable
as $$
  select p_end - coalesce(nullif(p_duration, 0), greatest(p_end - p_start, 1));
$$;

create or replace function membership_is_settled(p_membership_id uuid, p_cycle_start date)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from payments
    where membership_id = p_membership_id
      and status = 'paid'
      and paid_at is not null
      and paid_at::date >= p_cycle_start
  );
$$;

create or replace function membership_display_status(
  p_id uuid,
  p_raw_status text,
  p_start date,
  p_end date,
  p_duration integer,
  p_fee integer
) returns text
language sql
stable
as $$
  select case
    when p_raw_status = 'cancelled' then 'inactive'
    when coalesce(p_fee, 0) = 0 then 'active'
    when p_end < current_date then 'payment_incomplete'
    when not membership_is_settled(p_id, membership_cycle_start(p_start, p_end, p_duration))
      then 'payment_incomplete'
    else 'active'
  end;
$$;

grant execute on function membership_cycle_start(date, date, integer) to authenticated;
grant execute on function membership_is_settled(uuid, date) to authenticated;
grant execute on function membership_display_status(uuid, text, date, date, integer, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_memberships — display_status via the shared helper.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists list_memberships(uuid, text, text, uuid, text, integer, integer);

create function list_memberships(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,
  p_plan_id uuid default null,
  p_sort text default 'oldest',
  p_limit integer default 10,
  p_offset integer default 0
) returns table (
  membership_id uuid,
  member_id uuid,
  member_name text,
  member_phone text,
  member_email text,
  plan_id uuid,
  plan_name text,
  monthly_price_inr integer,
  display_status text,
  start_date date,
  end_date date,
  days_left integer,
  created_by uuid,
  created_by_name text,
  batch_name text,
  batch_days integer[],
  batch_start time,
  batch_end time,
  batch_court text,
  total_count bigint
)
language sql
stable
as $$
  with base as (
    select
      m.id as membership_id,
      m.member_id,
      mem.full_name as member_name,
      mem.phone as member_phone,
      mem.email as member_email,
      m.plan_id,
      coalesce(m.name, mp.name, 'Membership') as plan_name,
      coalesce(m.monthly_price_inr, m.membership_fee_inr, mp.price_inr, 0) as monthly_price_inr,
      membership_display_status(
        m.id, m.status::text, m.start_date, m.end_date, m.duration_days,
        coalesce(m.total_amount_inr, m.membership_fee_inr, mp.price_inr, 0)::integer
      ) as display_status,
      m.start_date,
      m.end_date,
      (m.end_date - current_date) as days_left,
      m.created_by,
      p.full_name as created_by_name,
      coalesce(b.name, case when m.time_slot_start is not null then 'Time slot' end) as batch_name,
      b.days_of_week as batch_days,
      coalesce(b.start_time, m.time_slot_start) as batch_start,
      coalesce(b.end_time, m.time_slot_end) as batch_end,
      bc.name as batch_court,
      m.created_at
    from memberships m
    join members mem on mem.id = m.member_id
    left join membership_plans mp on mp.id = m.plan_id
    left join profiles p on p.id = m.created_by
    left join lateral (
      select bm.batch_id
      from membership_batch_members bm
      where bm.membership_id = m.id
      order by bm.created_at
      limit 1
    ) bml on true
    left join membership_batches b on b.id = bml.batch_id
    left join courts bc on bc.id = b.court_id
    where m.facility_id = p_facility_id
      and (
        p_search is null
        or mem.full_name ilike '%' || p_search || '%'
        or mem.phone ilike '%' || p_search || '%'
        or coalesce(mem.email, '') ilike '%' || p_search || '%'
      )
      and (p_plan_id is null or m.plan_id = p_plan_id)
  ),
  filtered as (
    select * from base where p_status is null or display_status = p_status
  )
  select
    membership_id, member_id, member_name, member_phone, member_email,
    plan_id, plan_name, monthly_price_inr, display_status,
    start_date, end_date, days_left, created_by, created_by_name,
    batch_name, batch_days, batch_start, batch_end, batch_court,
    count(*) over () as total_count
  from filtered
  order by
    case when p_sort = 'next_payment' then end_date end asc nulls last,
    case when p_sort = 'name' then member_name end asc nulls last,
    created_at asc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0);
$$;

grant execute on function list_memberships(uuid, text, text, uuid, text, integer, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_membership_page_summary — active vs payment_incomplete; settled revenue.
-- Return shape changes (inactive_members → payment_incomplete_members).
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists get_membership_page_summary(uuid);

create function get_membership_page_summary(p_facility_id uuid)
returns table (
  total_members bigint,
  total_members_prev bigint,
  active_members bigint,
  payment_incomplete_members bigint,
  revenue_inr bigint,
  revenue_prev_inr bigint
)
language sql
stable
as $$
  with months as (
    select
      date_trunc('month', current_date)::date as cur_start,
      (date_trunc('month', current_date) - interval '1 month')::date as prev_start
  ),
  m as (
    select
      mm.member_id,
      mm.created_at,
      membership_display_status(
        mm.id, mm.status::text, mm.start_date, mm.end_date, mm.duration_days,
        coalesce(mm.total_amount_inr, mm.membership_fee_inr, mp.price_inr, 0)::integer
      ) as ds
    from memberships mm
    left join membership_plans mp on mp.id = mm.plan_id
    where mm.facility_id = p_facility_id
  )
  select
    (select count(distinct member_id) from m),
    (select count(distinct member_id) from m, months where m.created_at < months.cur_start),
    (select count(*) from m where ds = 'active'),
    (select count(*) from m where ds = 'payment_incomplete'),
    coalesce((
      select sum(amount_inr) from payments, months
      where facility_id = p_facility_id and membership_id is not null
        and status = 'paid' and paid_at is not null
        and paid_at >= months.cur_start
    ), 0),
    coalesce((
      select sum(amount_inr) from payments, months
      where facility_id = p_facility_id and membership_id is not null
        and status = 'paid' and paid_at is not null
        and paid_at >= months.prev_start and paid_at < months.cur_start
    ), 0);
$$;

grant execute on function get_membership_page_summary(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_membership_detail — displayStatus via the helper; settled-only
-- "Payment received" timeline entry.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_membership_detail(p_membership_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  m memberships;
  mem members;
  mp membership_plans;
  pay payments;
  ref_name text;
  creator_name text;
  slot_batch membership_batches;
  slot_court text;
  fee integer;
  settled boolean;
  v_status text;
  timeline jsonb := '[]'::jsonb;
begin
  select * into m from memberships where id = p_membership_id;
  if m.id is null then
    raise exception 'Membership not found' using errcode = 'P0002';
  end if;

  select * into mem from members where id = m.member_id;
  if m.plan_id is not null then
    select * into mp from membership_plans where id = m.plan_id;
  end if;

  select * into pay from payments
    where membership_id = m.id
    order by coalesce(paid_at, created_at) desc
    limit 1;

  fee := coalesce(m.total_amount_inr, m.membership_fee_inr, mp.price_inr, 0);
  v_status := membership_display_status(m.id, m.status::text, m.start_date, m.end_date, m.duration_days, fee);
  settled := fee = 0 or membership_is_settled(m.id, membership_cycle_start(m.start_date, m.end_date, m.duration_days));

  if m.referral_member_id is not null then
    select full_name into ref_name from members where id = m.referral_member_id;
  end if;
  if m.created_by is not null then
    select full_name into creator_name from profiles where id = m.created_by;
  end if;

  select b.* into slot_batch
  from membership_batch_members bm
  join membership_batches b on b.id = bm.batch_id
  where bm.membership_id = m.id
  order by bm.created_at
  limit 1;
  if slot_batch.id is not null then
    select name into slot_court from courts where id = slot_batch.court_id;
  end if;

  timeline := timeline || jsonb_build_object(
    'label', 'Membership created',
    'actor', coalesce(creator_name, 'Self registered'),
    'at', m.created_at
  );
  if pay.id is not null and pay.paid_at is not null then
    timeline := timeline || jsonb_build_object(
      'label', 'Payment received',
      'actor', coalesce(pay.payment_method, 'Payment'),
      'at', pay.paid_at
    );
  end if;
  if v_status = 'active' and fee > 0 then
    timeline := timeline || jsonb_build_object(
      'label', 'Membership activated',
      'actor', 'System',
      'at', coalesce(pay.paid_at, m.created_at)
    );
  end if;

  return jsonb_build_object(
    'membershipId', m.id,
    'facilityId', m.facility_id,
    'displayStatus', v_status,
    'member', jsonb_build_object(
      'id', mem.id,
      'fullName', mem.full_name,
      'phone', mem.phone,
      'email', mem.email,
      'dateOfBirth', mem.date_of_birth,
      'gender', mem.gender,
      'address', mem.address,
      'status', mem.status,
      'memberSince', mem.created_at
    ),
    'membership', jsonb_build_object(
      'name', coalesce(m.name, mp.name, 'Membership'),
      'membershipType', m.membership_type,
      'rawStatus', m.status,
      'startDate', m.start_date,
      'endDate', m.end_date,
      'durationDays', m.duration_days,
      'maxFamilyMembers', m.max_family_members,
      'description', m.description,
      'membershipFeeInr', coalesce(m.membership_fee_inr, mp.price_inr, 0),
      'registrationFeeInr', coalesce(m.registration_fee_inr, 0),
      'gstPercent', coalesce(m.gst_percent, 0),
      'totalAmountInr', coalesce(m.total_amount_inr, m.membership_fee_inr, mp.price_inr, 0),
      'monthlyPriceInr', coalesce(m.monthly_price_inr, m.membership_fee_inr, mp.price_inr, 0),
      'autoRenew', m.auto_renew,
      'createdAt', m.created_at
    ),
    'payment', case when pay.id is null then null else jsonb_build_object(
      'amountInr', pay.amount_inr,
      'status', pay.status,
      'settled', pay.paid_at is not null,
      'method', pay.payment_method,
      'paidAt', pay.paid_at,
      'createdAt', pay.created_at,
      'transactionId', pay.razorpay_payment_id
    ) end,
    'referralName', ref_name,
    'createdByName', creator_name,
    'discoverySource', m.discovery_source,
    'paymentReference', m.payment_reference,
    'notes', m.notes,
    'slot', case when slot_batch.id is null then null else jsonb_build_object(
      'courtName', slot_court,
      'daysOfWeek', slot_batch.days_of_week,
      'startTime', slot_batch.start_time,
      'endTime', slot_batch.end_time
    ) end,
    'timeline', timeline
  );
end;
$$;

grant execute on function get_membership_detail(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- record_membership_payment — the explicit "cash received" confirmation.
-- Settles the current cycle's payment (creating one if none is pending) and,
-- if the paid-through date has already lapsed, advances end_date by one
-- billing cycle so the next payment date moves forward.
-- ─────────────────────────────────────────────────────────────────────────
create function record_membership_payment(p_membership_id uuid, p_method text default 'cash')
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
      set end_date = greatest(m.end_date, current_date) + cyc,
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