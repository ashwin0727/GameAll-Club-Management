-- ═══════════════════════════════════════════════════════════════════════════
-- Pending Payments — one place to see and collect everything still owed.
--
-- No new table. An obligation is not a fact to be stored, it is the gap
-- between what something costs and what has been paid towards it, and both
-- of those already exist:
--
--   bookings.amount_minor        what a court booking costs
--   memberships.total_amount_inr what a membership costs
--   payments (status = 'paid')   what has actually been collected
--
-- Storing outstanding balances alongside those would create a second version
-- of the truth that drifts the first time anything is recorded outside this
-- page. It is derived here instead, in the database, so the browser never
-- computes what is owed.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- Idempotency. A double-click, a retried request or a flaky connection must
-- not take the money twice. The caller sends a key; the second attempt with
-- the same key returns the first payment instead of making another.
-- ─────────────────────────────────────────────────────────────────────────
alter table payments
  add column if not exists idempotency_key text;

create unique index if not exists payments_idempotency_key_idx
  on payments (idempotency_key)
  where idempotency_key is not null;

-- The obligations are looked up by source constantly; these are the joins.
create index if not exists payments_booking_paid_idx
  on payments (booking_id) where status = 'paid';
create index if not exists payments_membership_paid_idx
  on payments (membership_id) where status = 'paid';


-- ─────────────────────────────────────────────────────────────────────────
-- Every outstanding obligation, from every source, in one shape.
--
-- `due_on` is deliberately one thing per source and documented: the date the
-- court is booked for, or the date a membership starts. Mixing created-at,
-- booking date and payment date behind one filter would make the filter
-- meaningless.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_pending_payments(
  p_facility_id uuid,
  p_search text default null,
  p_source_type text default null,
  -- PENDING | PARTIALLY_PAID | OVERDUE | ALL_OUTSTANDING (default) | PAID
  p_status text default 'ALL_OUTSTANDING',
  p_from date default null,
  p_to date default null,
  p_sort text default 'DUE_DATE',
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  source_type text,
  source_id uuid,
  reference text,
  customer_name text,
  customer_phone text,
  description text,
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
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(f.timezone, 'Asia/Kolkata') into tz from facilities f where f.id = p_facility_id;

  return query
  with obligations as (
    -- Court and guest bookings. Cancelled ones are not owed.
    select
      case when b.customer_type = 'GUEST' then 'GUEST_BOOKING' else 'BOOKING' end as source_type,
      b.id as source_id,
      'BOOK-' || upper(substr(replace(b.id::text, '-', ''), 1, 6)) as reference,
      coalesce(b.guest_name, mem.full_name, 'Guest') as customer_name,
      coalesce(b.guest_phone, mem.phone) as customer_phone,
      concat_ws(' • ', c.name, to_char(b.start_time at time zone tz, 'DD Mon • HH12:MI AM')) as description,
      coalesce(b.amount_minor, 0)::bigint as total_minor,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.booking_id = b.id and p.status = 'paid'
      ), 0)::bigint as paid_minor,
      b.payment_method,
      (b.start_time at time zone tz)::date as due_on
    from bookings b
    left join courts c on c.id = b.court_id
    left join members mem on mem.id = b.member_id
    where b.facility_id = p_facility_id
      and b.status in ('pending', 'confirmed', 'completed')

    union all

    -- Memberships. total_amount_inr is whole rupees, like payments.
    select
      'MEMBERSHIP',
      ms.id,
      'MEM-' || upper(substr(replace(ms.id::text, '-', ''), 1, 6)),
      coalesce(mem2.full_name, 'Member'),
      mem2.phone,
      coalesce(ms.name, mp.name, 'Membership'),
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
      -- Overdue is a view of the same debt, not a separate state: still
      -- owed, and the date it was owed by has passed.
      (s.settle_status <> 'PAID' and s.due_on < (now() at time zone tz)::date) as is_overdue
    from scored s
    where
      case coalesce(p_status, 'ALL_OUTSTANDING')
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
  select
    f.source_type,
    f.source_id,
    f.reference,
    f.customer_name,
    f.customer_phone,
    f.description,
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
    -- Default: the oldest debt first, which is the one to chase.
    f.due_on asc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_pending_payments(uuid, text, text, text, date, date, text, integer, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- The headline figures, over the whole filtered set rather than one page.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_pending_payments_summary(
  p_facility_id uuid,
  p_from date default null,
  p_to date default null
)
returns table (
  outstanding_minor bigint,
  pending_minor bigint,
  partially_paid_minor bigint,
  overdue_minor bigint,
  obligation_count bigint
)
language plpgsql
stable
as $$
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  return query
  with rows as (
    select * from list_pending_payments(
      p_facility_id, null, null, 'ALL_OUTSTANDING', p_from, p_to, 'DUE_DATE', 100000, 0
    )
  )
  select
    coalesce(sum(r.outstanding_minor), 0)::bigint,
    coalesce(sum(r.outstanding_minor) filter (where r.status = 'PENDING'), 0)::bigint,
    coalesce(sum(r.outstanding_minor) filter (where r.status = 'PARTIALLY_PAID'), 0)::bigint,
    coalesce(sum(r.outstanding_minor) filter (where r.status = 'OVERDUE'), 0)::bigint,
    count(*)::bigint
  from rows r;
end;
$$;

grant execute on function get_pending_payments_summary(uuid, date, date) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Record a payment against any obligation.
--
-- One entry point for every source, so "Record Payment" stops being a guest
-- booking feature. The outstanding balance is recomputed here, under a lock
-- on the source row: two people collecting the last ₹500 at the same moment
-- means one of them is told the balance moved, not that ₹1,000 was taken.
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
  v_existing payments;
  v_paid_at timestamptz;
begin
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Enter an amount greater than zero.' using errcode = '23514';
  end if;

  -- A repeat of the same request returns the original rather than taking
  -- the money again.
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
  else
    raise exception 'Unknown payment source.' using errcode = '22023';
  end if;

  if v_facility is null then
    raise exception 'That record no longer exists.' using errcode = 'P0002';
  end if;

  if not has_facility_role(v_facility, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  -- Recomputed here, after the lock — never trusted from the caller.
  select coalesce(sum(p.amount_inr) * 100, 0)::bigint into v_paid
    from payments p
   where p.status = 'paid'
     and ((v_booking is not null and p.booking_id = v_booking)
       or (v_membership is not null and p.membership_id = v_membership));

  v_outstanding := v_total - v_paid;

  if v_outstanding <= 0 then
    raise exception 'This has already been paid in full.' using errcode = '23514';
  end if;

  if p_amount_minor > v_outstanding then
    raise exception 'Outstanding amount has changed. Only % remains.', (v_outstanding / 100.0)
      using errcode = '23514';
  end if;

  -- Today keeps the actual clock time; a backdated payment lands at midday
  -- on the date given, which cannot slip either side of a day boundary when
  -- read back in the facility's timezone.
  v_paid_at := case
    when p_paid_on is null or p_paid_on = current_date then now()
    else p_paid_on::timestamp + time '12:00'
  end;

  insert into payments (
    facility_id, member_id, booking_id, membership_id,
    amount_inr, status, payment_method, paid_at, idempotency_key
  ) values (
    v_facility, null, v_booking, v_membership,
    -- payments stores whole rupees, as it has since 0001.
    round(p_amount_minor / 100.0), 'paid'::payment_status,
    nullif(trim(p_method), ''), v_paid_at, p_idempotency_key
  );

  -- Bookings carry their own payment flag; flip it only once fully covered,
  -- so a part payment does not read as settled.
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
