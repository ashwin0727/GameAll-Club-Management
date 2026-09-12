-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching ↔ Finance integration.
--
-- A coaching enrollment carries a fee (coaching_enrollments.price_minor).
-- That is an OBLIGATION, never revenue. Revenue is recognised exactly the
-- way it is for bookings and memberships: a paid `payments` row (spec §26 /
-- §28 / §71). Nothing here is a second ledger.
--
--   * payments gains coaching_enrollment_id — the same shape as booking_id /
--     membership_id.
--   * record_obligation_payment gains a COACHING_ENROLLMENT branch, so
--     "Record Payment" works for coaching with no new payment path.
--   * list_pending_payments / get_finance_summary see coaching outstanding
--     alongside every other source.
--   * finance_transactions_view / list_finance_ledger / get_transaction_details
--     classify a coaching payment as its own 'COACHING' category.
--
-- A MEMBERSHIP_INCLUDED enrollment has price_minor = 0 → no obligation, no
-- revenue from usage (spec §27 / §72).
-- ═══════════════════════════════════════════════════════════════════════════


alter table payments
  add column if not exists coaching_enrollment_id uuid references coaching_enrollments (id) on delete set null;

create index if not exists payments_coaching_enrollment_idx
  on payments (coaching_enrollment_id) where coaching_enrollment_id is not null;


-- ─────────────────────────────────────────────────────────────────────────
-- finance_transactions_view — recreated from 0051 (its current definition)
-- with ONLY expression changes: the source_type CASE gains a COACHING branch
-- and the customer name/phone fall back to the coaching enrollment's member.
-- The column list, order and types are untouched, so `create or replace
-- view` is safe even though list_finance_transactions `returns setof` it.
-- ─────────────────────────────────────────────────────────────────────────
create or replace view finance_transactions_view with (security_invoker = true) as
select
  p.id,
  'TXN-' || upper(substr(p.id::text, 1, 8)) as reference,
  p.facility_id,
  p.created_at,
  p.paid_at,
  coalesce(p.paid_at, p.created_at) as effective_at,
  coalesce(
    po.source_type::text,
    case
      when p.coaching_enrollment_id is not null then 'COACHING'
      when p.membership_id is not null then 'MEMBERSHIP'
      when b.customer_type = 'GUEST' then 'GUEST_BOOKING'
      when p.membership_session_booking_id is not null then 'GUEST_BOOKING'
      else 'MEMBER_BOOKING'
    end
  ) as source_type,
  coalesce(m.full_name, gp.name, b.guest_name, cm.full_name) as customer_name,
  coalesce(m.phone, gp.phone, b.guest_phone, cm.phone) as customer_phone,
  p.booking_id,
  p.membership_id,
  p.payment_order_id,
  (p.amount_inr * 100)::bigint as amount_minor,
  coalesce(po.currency, fac.currency, 'INR') as currency,
  p.payment_method,
  p.status::text as status,
  p.razorpay_order_id,
  p.razorpay_payment_id,
  coalesce(rf.processed, 0)::bigint as refunded_minor,
  coalesce(rf.pending, 0)::bigint as pending_refund_minor,
  ((p.amount_inr * 100) - coalesce(rf.processed, 0))::bigint as net_minor
from payments p
left join payment_orders po on po.id = p.payment_order_id
left join facilities fac on fac.id = p.facility_id
left join bookings b on b.id = p.booking_id
left join members m on m.id = p.member_id
left join guest_players gp on gp.id = p.guest_player_id
left join coaching_enrollments ce on ce.id = p.coaching_enrollment_id
left join members cm on cm.id = ce.member_id
left join lateral (
  select
    sum(r.amount_minor) filter (where r.status = 'PROCESSED') as processed,
    sum(r.amount_minor) filter (where r.status in ('REQUESTED', 'PROCESSING', 'PENDING')) as pending
  from refunds r
  where r.payment_order_id = p.payment_order_id
) rf on true;

grant select on finance_transactions_view to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- record_obligation_payment — recreated from 0055 with a COACHING_ENROLLMENT
-- branch. Same lock-then-recompute discipline; the coaching total is
-- coaching_enrollments.price_minor.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function record_obligation_payment(
  p_source_type text,
  p_source_id uuid,
  p_amount_minor integer,
  p_method text,
  p_paid_on date default null,
  p_reference text default null,
  p_notes text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_facility uuid;
  v_total bigint;
  v_paid bigint;
  v_outstanding bigint;
  v_membership uuid;
  v_booking uuid;
  v_enrollment uuid;
  v_existing payments;
  v_paid_at timestamptz;
begin
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Enter an amount greater than zero.' using errcode = '23514';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from payments where idempotency_key = p_idempotency_key;
    if v_existing.id is not null then
      return jsonb_build_object('paymentId', v_existing.id, 'duplicate', true);
    end if;
  end if;

  if p_source_type in ('BOOKING', 'GUEST_BOOKING') then
    select b.facility_id, coalesce(b.amount_minor, 0)::bigint
      into v_facility, v_total
      from bookings b where b.id = p_source_id
      for update;
    v_booking := p_source_id;
  elsif p_source_type = 'MEMBERSHIP' then
    select ms.facility_id, (coalesce(ms.total_amount_inr, 0) * 100)::bigint
      into v_facility, v_total
      from memberships ms where ms.id = p_source_id
      for update;
    v_membership := p_source_id;
  elsif p_source_type = 'COACHING_ENROLLMENT' then
    select e.facility_id, coalesce(e.price_minor, 0)::bigint
      into v_facility, v_total
      from coaching_enrollments e where e.id = p_source_id
      for update;
    v_enrollment := p_source_id;
  else
    raise exception 'Unknown payment source.' using errcode = '22023';
  end if;

  if v_facility is null then
    raise exception 'That record no longer exists.' using errcode = 'P0002';
  end if;

  if not has_facility_role(v_facility, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  select coalesce(sum(p.amount_inr) * 100, 0)::bigint into v_paid
    from payments p
   where p.status = 'paid'
     and ((v_booking is not null and p.booking_id = v_booking)
       or (v_membership is not null and p.membership_id = v_membership)
       or (v_enrollment is not null and p.coaching_enrollment_id = v_enrollment));

  v_outstanding := v_total - v_paid;

  if v_total <= 0 then
    raise exception 'There is nothing to collect for this.' using errcode = '23514';
  end if;
  if v_outstanding <= 0 then
    raise exception 'This has already been paid in full.' using errcode = '23514';
  end if;

  if p_amount_minor > v_outstanding then
    raise exception 'Outstanding amount has changed. Only % remains.', (v_outstanding / 100.0)
      using errcode = '23514';
  end if;

  v_paid_at := case
    when p_paid_on is null or p_paid_on = current_date then now()
    else p_paid_on::timestamp + time '12:00'
  end;

  insert into payments (
    facility_id, member_id, booking_id, membership_id, coaching_enrollment_id,
    amount_inr, status, payment_method, paid_at, idempotency_key,
    reference, notes, recorded_by
  ) values (
    v_facility, null, v_booking, v_membership, v_enrollment,
    round(p_amount_minor / 100.0), 'paid'::payment_status,
    nullif(trim(p_method), ''), v_paid_at, p_idempotency_key,
    nullif(trim(p_reference), ''), nullif(trim(p_notes), ''), auth.uid()
  );

  if v_booking is not null and (v_paid + p_amount_minor) >= v_total then
    update bookings
       set payment_status = 'PAID',
           payment_method = coalesce(nullif(trim(p_method), ''), payment_method),
           updated_at = now()
     where id = v_booking;
  end if;

  return jsonb_build_object(
    'duplicate', false,
    'totalMinor', v_total,
    'paidMinor', v_paid + p_amount_minor,
    'outstandingMinor', v_total - (v_paid + p_amount_minor)
  );
end;
$$;

grant execute on function record_obligation_payment(text, uuid, integer, text, date, text, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- list_pending_payments — recreated from 0053 (its current 10-arg
-- definition, with p_source_id and the wider return table) plus a
-- COACHING_ENROLLMENT obligation in the union. Signature unchanged, so the
-- Record Payment page and get_pending_payments_summary keep working.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_pending_payments(
  p_facility_id uuid,
  p_search text default null,
  p_source_type text default null,
  p_status text default 'ALL_OUTSTANDING',
  p_from date default null,
  p_to date default null,
  p_sort text default 'DUE_DATE',
  p_limit integer default 20,
  p_offset integer default 0,
  p_source_id uuid default null
)
returns table (
  source_type text,
  source_id uuid,
  reference text,
  customer_name text,
  customer_phone text,
  description text,
  facility_name text,
  court_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  total_minor bigint,
  paid_minor bigint,
  outstanding_minor bigint,
  status text,
  payment_method text,
  due_on date,
  total_count bigint
)
language plpgsql
stable
as $$
declare
  tz text;
  fac_name text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(f.timezone, 'Asia/Kolkata'), f.name
    into tz, fac_name
    from facilities f where f.id = p_facility_id;

  return query
  with obligations as (
    select
      case when b.customer_type = 'GUEST' then 'GUEST_BOOKING' else 'BOOKING' end as source_type,
      b.id as source_id,
      'BOOK-' || upper(substr(replace(b.id::text, '-', ''), 1, 6)) as reference,
      coalesce(b.guest_name, mem.full_name, 'Guest') as customer_name,
      coalesce(b.guest_phone, mem.phone) as customer_phone,
      concat_ws(' • ', c.name, to_char(b.start_time at time zone tz, 'DD Mon • HH12:MI AM')) as description,
      fac_name as facility_name,
      c.name as court_name,
      b.start_time as starts_at,
      b.end_time as ends_at,
      coalesce(b.amount_minor, 0)::bigint as total_minor,
      greatest(
        coalesce((
          select sum(p.amount_inr) * 100 from payments p
          where p.booking_id = b.id and p.status = 'paid'
        ), 0),
        case when b.payment_status = 'PAID' then coalesce(b.amount_minor, 0) else 0 end
      )::bigint as paid_minor,
      b.payment_method,
      (b.start_time at time zone tz)::date as due_on
    from bookings b
    left join courts c on c.id = b.court_id
    left join members mem on mem.id = b.member_id
    where b.facility_id = p_facility_id
      and b.status in ('pending', 'confirmed', 'completed')

    union all

    select
      'MEMBERSHIP',
      ms.id,
      'MEM-' || upper(substr(replace(ms.id::text, '-', ''), 1, 6)),
      coalesce(mem2.full_name, 'Member'),
      mem2.phone,
      coalesce(ms.name, mp.name, 'Membership'),
      fac_name,
      null::text,
      null::timestamptz,
      null::timestamptz,
      (coalesce(ms.total_amount_inr, 0) * 100)::bigint,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.membership_id = ms.id and p.status = 'paid'
      ), 0)::bigint,
      null::text,
      ms.start_date
    from memberships ms
    left join members mem2 on mem2.id = ms.member_id
    left join membership_plans mp on mp.id = ms.plan_id
    where ms.facility_id = p_facility_id
      and ms.status <> 'cancelled'

    union all

    -- Coaching enrollments. Cancelled ones are not owed; a zero-priced
    -- (membership-included) enrollment falls out at `total_minor > 0`.
    select
      'COACHING_ENROLLMENT',
      e.id,
      'COACH-' || upper(substr(replace(e.id::text, '-', ''), 1, 6)),
      coalesce(mem3.full_name, 'Member'),
      mem3.phone,
      concat_ws(' • ', cp.name, 'from ' || to_char(e.start_date, 'DD Mon')),
      fac_name,
      null::text,
      null::timestamptz,
      null::timestamptz,
      coalesce(e.price_minor, 0)::bigint,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.coaching_enrollment_id = e.id and p.status = 'paid'
      ), 0)::bigint,
      null::text,
      e.start_date
    from coaching_enrollments e
    left join members mem3 on mem3.id = e.member_id
    left join coaching_programs cp on cp.id = e.program_id
    where e.facility_id = p_facility_id
      and e.status <> 'CANCELLED'
  ),
  scored as (
    select
      o.*,
      (o.total_minor - o.paid_minor) as outstanding_minor,
      case
        when o.paid_minor >= o.total_minor then 'PAID'
        when o.paid_minor > 0 then 'PARTIALLY_PAID'
        else 'PENDING'
      end as settle_status
    from obligations o
    where o.total_minor > 0
  ),
  filtered as (
    select
      s.*,
      (s.settle_status <> 'PAID' and s.due_on < (now() at time zone tz)::date) as is_overdue
    from scored s
    where
      (p_source_id is not null and s.source_id = p_source_id)
      or (
        p_source_id is null
        and case coalesce(p_status, 'ALL_OUTSTANDING')
          when 'PAID' then s.settle_status = 'PAID'
          when 'PENDING' then s.settle_status = 'PENDING'
          when 'PARTIALLY_PAID' then s.settle_status = 'PARTIALLY_PAID'
          when 'OVERDUE' then s.settle_status <> 'PAID' and s.due_on < (now() at time zone tz)::date
          else s.settle_status <> 'PAID'
        end
        and (p_source_type is null or s.source_type = p_source_type)
        and (p_from is null or s.due_on >= p_from)
        and (p_to is null or s.due_on <= p_to)
        and (
          p_search is null or trim(p_search) = ''
          or s.customer_name ilike '%' || trim(p_search) || '%'
          or s.customer_phone ilike '%' || trim(p_search) || '%'
          or s.reference ilike '%' || trim(p_search) || '%'
          or s.description ilike '%' || trim(p_search) || '%'
        )
      )
  )
  select
    f.source_type,
    f.source_id,
    f.reference,
    f.customer_name,
    f.customer_phone,
    f.description,
    f.facility_name,
    f.court_name,
    f.starts_at,
    f.ends_at,
    f.total_minor,
    f.paid_minor,
    f.outstanding_minor,
    case when f.is_overdue then 'OVERDUE' else f.settle_status end,
    f.payment_method,
    f.due_on,
    count(*) over () as total_count
  from filtered f
  order by
    case when p_sort = 'AMOUNT' then f.outstanding_minor end desc nulls last,
    case when p_sort = 'CUSTOMER' then f.customer_name end asc nulls last,
    case when p_sort = 'NEWEST' then f.due_on end desc nulls last,
    f.due_on asc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_pending_payments(uuid, text, text, text, date, date, text, integer, integer, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_finance_summary — recreated from 0060 with the coaching obligation
-- added to the outstanding CTE. `gross` already sums every paid `payments`
-- row, so coaching revenue is counted without any change there.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_finance_summary(
  p_facility_id uuid,
  p_preset text default null,
  p_start_date date default null,
  p_end_date date default null
)
returns table (
  gross_revenue_minor bigint,
  refunds_minor bigint,
  expenses_minor bigint,
  net_revenue_minor bigint,
  outstanding_minor bigint,
  transaction_count bigint,
  successful_payment_count bigint,
  failed_payment_count bigint,
  pending_payment_count bigint,
  pending_refund_count bigint,
  settlement_exception_count bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  gross bigint;
  refunded bigint;
  spent bigint;
  outstanding bigint;
  pending bigint;
  succ bigint;
  failed bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');

  select (coalesce(sum(p.amount_inr), 0) * 100)::bigint, count(*)::bigint
    into gross, succ
    from payments p
    where p.facility_id = p_facility_id and p.status = 'paid' and range_ @> coalesce(p.paid_at, p.created_at);

  select coalesce(sum(r.amount_minor), 0)::bigint
    into refunded
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at;

  select coalesce(sum(e.amount_minor), 0)::bigint
    into spent
    from expenses e
    where e.facility_id = p_facility_id and e.status = 'RECORDED'
      and range_ @> (e.spent_on::timestamp at time zone tz);

  select count(*) filter (where po.status = 'FAILED')
    into failed
    from payment_orders po
    where po.facility_id = p_facility_id and range_ @> po.created_at;

  with obligations as (
    select
      coalesce(b.amount_minor, 0)::bigint as total_minor,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.booking_id = b.id and p.status = 'paid'
      ), 0)::bigint as paid_minor
    from bookings b
    where b.facility_id = p_facility_id
      and b.status in ('pending', 'confirmed', 'completed')

    union all

    select
      (coalesce(ms.total_amount_inr, 0) * 100)::bigint,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.membership_id = ms.id and p.status = 'paid'
      ), 0)::bigint
    from memberships ms
    where ms.facility_id = p_facility_id
      and ms.status <> 'cancelled'

    union all

    select
      coalesce(e.price_minor, 0)::bigint,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.coaching_enrollment_id = e.id and p.status = 'paid'
      ), 0)::bigint
    from coaching_enrollments e
    where e.facility_id = p_facility_id
      and e.status <> 'CANCELLED'
  ),
  owed as (
    select (o.total_minor - o.paid_minor) as amount
    from obligations o
    where o.total_minor > 0 and o.paid_minor < o.total_minor
  )
  select coalesce(sum(amount), 0)::bigint, count(*)::bigint
    into outstanding, pending
    from owed;

  return query select
    gross::bigint,
    refunded::bigint,
    spent::bigint,
    (gross - refunded - spent)::bigint,
    outstanding::bigint,
    (succ + failed + pending)::bigint,
    succ::bigint,
    failed::bigint,
    pending::bigint,
    (select count(*) from refunds r2 where r2.facility_id = p_facility_id and r2.status in ('REQUESTED', 'PROCESSING', 'PENDING'))::bigint,
    (select count(*) from settlement_exceptions se where se.facility_id = p_facility_id and se.status = 'OPEN')::bigint;
end;
$$;

grant execute on function get_finance_summary(uuid, text, date, date) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- list_finance_ledger — recreated from 0071 (its current definition) with
-- one line added: a 'Coaching Revenue' category for source_type 'COACHING'.
-- Everything else — the expense payment-status label, the refund/expense
-- unions, the filters — is verbatim.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_finance_ledger(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_txn_type text default null,
  p_category text default null,
  p_payment_method text default null,
  p_status text default null,
  p_search text default null,
  p_limit integer default 10,
  p_offset integer default 0
)
returns table (
  id uuid,
  reference text,
  occurred_at timestamptz,
  description text,
  category text,
  txn_type text,
  payment_method text,
  amount_minor bigint,
  currency text,
  status text,
  source_type text,
  booking_id uuid,
  membership_id uuid,
  expense_id uuid,
  total_count bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  cur text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  select coalesce(f.timezone, 'Asia/Kolkata'), coalesce(f.currency, 'INR')
    into tz, cur
    from facilities f where f.id = p_facility_id;

  return query
  with ledger as (
    select
      v.id,
      v.reference,
      v.effective_at as occurred_at,
      trim(
        initcap(replace(v.source_type, '_', ' '))
        || coalesce(' — ' || v.customer_name, '')
      ) as description,
      case v.source_type
        when 'GUEST_BOOKING' then 'Guest Booking Revenue'
        when 'MEMBERSHIP' then 'Membership Revenue'
        when 'MEMBER_BOOKING' then 'Court Booking Revenue'
        when 'COACHING' then 'Coaching Revenue'
        else 'Other Revenue'
      end as category,
      'INCOME'::text as txn_type,
      v.payment_method,
      v.amount_minor::bigint,
      v.currency,
      v.status,
      v.source_type,
      v.booking_id,
      v.membership_id,
      null::uuid as expense_id
    from finance_transactions_view v
    where v.facility_id = p_facility_id

    union all

    select
      r.id,
      'RFD-' || upper(substr(r.id::text, 1, 8)),
      r.processed_at,
      'Refund'::text,
      'Booking Refund'::text,
      'REFUND'::text,
      null::text,
      r.amount_minor::bigint,
      cur,
      lower(r.status::text),
      'REFUND'::text,
      null::uuid,
      null::uuid,
      null::uuid
    from refunds r
    where r.facility_id = p_facility_id
      and r.status = 'PROCESSED'
      and r.processed_at is not null

    union all

    select
      e.id,
      'EXP-' || upper(substr(e.id::text, 1, 8)),
      (e.spent_on::timestamp at time zone tz),
      trim(coalesce(e.vendor, c.name) || coalesce(' — ' || e.notes, '')),
      c.name,
      'EXPENSE'::text,
      e.payment_method,
      e.amount_minor::bigint,
      e.currency,
      case e.payment_status when 'PAID' then 'paid' when 'PARTIAL' then 'partial' else 'pending' end,
      'EXPENSE'::text,
      null::uuid,
      null::uuid,
      e.id
    from expenses e
    join expense_categories c on c.id = e.category_id
    where e.facility_id = p_facility_id
      and e.status = 'RECORDED'
  ),
  filtered as (
    select * from ledger l
    where range_ @> l.occurred_at
      and (p_txn_type is null or l.txn_type = p_txn_type)
      and (p_category is null or l.category = p_category)
      and (p_payment_method is null or l.payment_method = p_payment_method)
      and (p_status is null or l.status = p_status)
      and (
        p_search is null or trim(p_search) = ''
        or l.reference ilike '%' || trim(p_search) || '%'
        or l.description ilike '%' || trim(p_search) || '%'
        or l.category ilike '%' || trim(p_search) || '%'
      )
  )
  select f.*, count(*) over () as total_count
  from filtered f
  order by f.occurred_at desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_finance_ledger(uuid, text, date, date, text, text, text, text, text, integer, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_transaction_details — recreated from 0055 with a COACHING source
-- reference / category and the coaching payment-history join.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_transaction_details(p_transaction_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v finance_transactions_view;
  fac facilities;
  v_recorded_by text;
  v_booking_code text;
  v_description text;
  v_enrollment uuid;
begin
  select * into v from finance_transactions_view where id = p_transaction_id;
  if v.id is null then
    raise exception 'Transaction not found.' using errcode = 'P0002';
  end if;
  if not has_facility_role(v.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  select * into fac from facilities where id = v.facility_id;

  select pr.full_name, p.coaching_enrollment_id into v_recorded_by, v_enrollment
    from payments p left join profiles pr on pr.id = p.recorded_by
   where p.id = v.id;

  if v.booking_id is not null then
    select
      'BOOK-' || upper(substr(replace(b.id::text, '-', ''), 1, 6)),
      concat_ws(' ',
        case when b.customer_type = 'GUEST' then 'Guest booking' else 'Court booking' end,
        'payment for', c.name)
      into v_booking_code, v_description
      from bookings b
      left join courts c on c.id = b.court_id
     where b.id = v.booking_id;
  elsif v.membership_id is not null then
    select 'MEM-' || upper(substr(replace(ms.id::text, '-', ''), 1, 6)),
           concat_ws(' ', 'Membership payment —', coalesce(ms.name, mp.name, 'Membership'))
      into v_booking_code, v_description
      from memberships ms
      left join membership_plans mp on mp.id = ms.plan_id
     where ms.id = v.membership_id;
  elsif v_enrollment is not null then
    select 'COACH-' || upper(substr(replace(e.id::text, '-', ''), 1, 6)),
           concat_ws(' ', 'Coaching payment —', cp.name)
      into v_booking_code, v_description
      from coaching_enrollments e
      left join coaching_programs cp on cp.id = e.program_id
     where e.id = v_enrollment;
  end if;

  return jsonb_build_object(
    'id', v.id,
    'reference', v.reference,
    'sourceType', v.source_type,
    'category', case v.source_type
      when 'GUEST_BOOKING' then 'Guest Booking Revenue'
      when 'MEMBERSHIP' then 'Membership Revenue'
      when 'MEMBER_BOOKING' then 'Court Booking Revenue'
      when 'COACHING' then 'Coaching Revenue'
      else 'Other Revenue' end,
    'type', 'INCOME',
    'amountMinor', v.amount_minor,
    'currency', v.currency,
    'status', v.status,
    'paymentMethod', v.payment_method,
    'occurredAt', v.effective_at,
    'createdAt', v.created_at,
    'recordedBy', v_recorded_by,
    'description', coalesce(v_description, 'Payment'),
    'sourceReference', v_booking_code,
    'customerName', v.customer_name,
    'customerPhone', v.customer_phone,
    'facilityName', fac.name,
    'facilityId', v.facility_id,
    'bookingId', v.booking_id,
    'membershipId', v.membership_id,
    'coachingEnrollmentId', v_enrollment,
    'refundedMinor', v.refunded_minor,
    'netMinor', v.net_minor,
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'paidAt', coalesce(p.paid_at, p.created_at),
        'amountMinor', (p.amount_inr * 100),
        'paymentMethod', p.payment_method,
        'reference', p.reference,
        'status', p.status::text,
        'isThisOne', p.id = v.id
      ) order by coalesce(p.paid_at, p.created_at))
      from payments p
      where p.status = 'paid'
        and ((v.booking_id is not null and p.booking_id = v.booking_id)
          or (v.membership_id is not null and p.membership_id = v.membership_id)
          or (v_enrollment is not null and p.coaching_enrollment_id = v_enrollment)
          or (v.booking_id is null and v.membership_id is null and v_enrollment is null and p.id = v.id))
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function get_transaction_details(uuid) to authenticated;
