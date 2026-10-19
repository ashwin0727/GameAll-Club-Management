-- ═══════════════════════════════════════════════════════════════════════════
-- Finance follows the top bar's sport selection.
--
-- The Finance pages (dashboard, transactions, pending payments, profit & loss) could only be asked for the whole
-- facility. Each money function below gains an optional list of sports (p_facility_sport_ids): null is All Sports —
-- nothing is filtered, exactly the old behaviour — and a list narrows every figure and row to those sports.
--
-- What "belongs to a sport":
--   booking payment / obligation     the sport of the court it is for
--   membership payment / obligation  a sport the membership's member is enrolled in (membership_batch_members)
--   session-booking payment          the sport of the session
--   coaching payment / obligation    the sport of the program
--   refund                           the sport of the payment it refunds
--
-- Expenses are not tied to a sport, so they are never narrowed: expense totals stay facility-wide, and the
-- transactions ledger leaves expense rows out while a sport is selected (see the Expenses page, which always
-- covers all sports).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function booking_in_sports(p_booking_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null or exists (
    select 1 from bookings b join courts c on c.id = b.court_id
    where b.id = p_booking_id and c.facility_sport_id = any (p_sports)
  )
$$;

create or replace function membership_in_sports(p_membership_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null or exists (
    select 1 from membership_batch_members bm join membership_batches mb on mb.id = bm.batch_id
    where bm.membership_id = p_membership_id and mb.facility_sport_id = any (p_sports)
  )
$$;

create or replace function enrollment_in_sports(p_enrollment_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null or exists (
    select 1 from coaching_enrollments e join coaching_programs x on x.id = e.program_id
    where e.id = p_enrollment_id and x.facility_sport_id = any (p_sports)
  )
$$;

create or replace function session_booking_in_sports(p_session_booking_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null or exists (
    select 1 from membership_session_bookings sb join membership_sessions s on s.id = sb.session_id
    where sb.id = p_session_booking_id and s.facility_sport_id = any (p_sports)
  )
$$;

create or replace function payment_in_sports(p_payment_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null or exists (
    select 1 from payments p
    where p.id = p_payment_id
      and (
        booking_in_sports(p.booking_id, p_sports)
        or membership_in_sports(p.membership_id, p_sports)
        or enrollment_in_sports(p.coaching_enrollment_id, p_sports)
        or session_booking_in_sports(p.membership_session_booking_id, p_sports)
      )
  )
$$;

-- A payment order (and so a refund, which hangs off one): by the payments taken against it, or — for one that never
-- produced a payment, such as a failed attempt — by the booking or session booking it was for.
create or replace function payment_order_in_sports(p_order_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null
    or exists (select 1 from payments p where p.payment_order_id = p_order_id and payment_in_sports(p.id, p_sports))
    or exists (
      select 1 from payment_orders o
      where o.id = p_order_id
        and (booking_in_sports(o.booking_id, p_sports) or session_booking_in_sports(o.membership_session_booking_id, p_sports))
    )
$$;

create or replace function obligation_in_sports(p_source_type text, p_source_id uuid, p_sports uuid[]) returns boolean
language sql stable as $$
  select p_sports is null or case
    when p_source_type in ('BOOKING', 'GUEST_BOOKING') then booking_in_sports(p_source_id, p_sports)
    when p_source_type = 'MEMBERSHIP' then membership_in_sports(p_source_id, p_sports)
    when p_source_type = 'COACHING_ENROLLMENT' then enrollment_in_sports(p_source_id, p_sports)
    else false
  end
$$;

-- ── get_finance_summary (from 0085_coaching_finance.sql) ──
drop function if exists get_finance_summary(uuid, text, date, date);

create or replace function get_finance_summary(
  p_facility_id uuid,
  p_preset text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_ids uuid[] default null
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
    where p.facility_id = p_facility_id and p.status = 'paid' and range_ @> coalesce(p.paid_at, p.created_at)
      and payment_in_sports(p.id, p_facility_sport_ids);

  select coalesce(sum(r.amount_minor), 0)::bigint
    into refunded
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at and payment_order_in_sports(r.payment_order_id, p_facility_sport_ids);

  select coalesce(sum(e.amount_minor), 0)::bigint
    into spent
    from expenses e
    where e.facility_id = p_facility_id and e.status = 'RECORDED'
      and range_ @> (e.spent_on::timestamp at time zone tz);

  select count(*) filter (where po.status = 'FAILED')
    into failed
    from payment_orders po
    where po.facility_id = p_facility_id and range_ @> po.created_at
      and payment_order_in_sports(po.id, p_facility_sport_ids);

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
      and booking_in_sports(b.id, p_facility_sport_ids)

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
      and membership_in_sports(ms.id, p_facility_sport_ids)

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
      and enrollment_in_sports(e.id, p_facility_sport_ids)
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
    (select count(*) from refunds r2 where r2.facility_id = p_facility_id and r2.status in ('REQUESTED', 'PROCESSING', 'PENDING') and payment_order_in_sports(r2.payment_order_id, p_facility_sport_ids))::bigint,
    (select count(*) from settlement_exceptions se where se.facility_id = p_facility_id and se.status = 'OPEN')::bigint;
end;
$$;

grant execute on function get_finance_summary(uuid, text, date, date, uuid[]) to authenticated;

-- ── get_payment_method_breakdown (from 0047_payment_method_breakdown.sql) ──
drop function if exists get_payment_method_breakdown(uuid, text, date, date);

create or replace function get_payment_method_breakdown(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_ids uuid[] default null
)
returns table (
  payment_method text,
  amount_minor bigint,
  payment_count bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  select
    coalesce(nullif(trim(p.payment_method), ''), 'Unknown') as payment_method,
    (coalesce(sum(p.amount_inr), 0) * 100)::bigint as amount_minor,
    count(*)::bigint as payment_count
  from payments p
  where p.facility_id = p_facility_id
    and p.status = 'paid'
    and range_ @> coalesce(p.paid_at, p.created_at)
    and payment_in_sports(p.id, p_facility_sport_ids)
  group by 1
  order by 2 desc;
end;
$$;

grant execute on function get_payment_method_breakdown(uuid, text, date, date, uuid[]) to authenticated;

-- ── list_finance_ledger (from 0085_coaching_finance.sql) ──
drop function if exists list_finance_ledger(uuid, text, date, date, text, text, text, text, text, integer, integer);

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
  p_offset integer default 0,
  p_facility_sport_ids uuid[] default null
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
      and payment_in_sports(v.id, p_facility_sport_ids)

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
      and payment_order_in_sports(r.payment_order_id, p_facility_sport_ids)

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
      -- expenses are not tied to a sport: left out while a sport is selected
      and p_facility_sport_ids is null
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

grant execute on function list_finance_ledger(uuid, text, date, date, text, text, text, text, text, integer, integer, uuid[]) to authenticated;

-- ── list_finance_transactions (from 0024_finance.sql) ──
drop function if exists list_finance_transactions(uuid, text, date, date, text, text, text, integer, integer);

create or replace function list_finance_transactions(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_source_type text default null,
  p_status text default null,
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_facility_sport_ids uuid[] default null
) returns setof finance_transactions_view
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  select v.* from finance_transactions_view v
  where v.facility_id = p_facility_id
    and range_ @> v.effective_at
    and payment_in_sports(v.id, p_facility_sport_ids)
    and (p_source_type is null or v.source_type = p_source_type)
    and (p_status is null or v.status = p_status)
    and (
      p_search is null or trim(p_search) = ''
      or v.reference ilike '%' || p_search || '%'
      or v.id::text ilike '%' || p_search || '%'
      or v.razorpay_payment_id ilike '%' || p_search || '%'
      or v.razorpay_order_id ilike '%' || p_search || '%'
      or (v.booking_id is not null and v.booking_id::text = p_search)
      or (v.membership_id is not null and v.membership_id::text = p_search)
      or v.customer_name ilike '%' || p_search || '%'
    )
  order by v.effective_at desc
  limit greatest(1, least(p_limit, 100))
  offset greatest(0, p_offset);
end;
$$;

grant execute on function list_finance_transactions(uuid, text, date, date, text, text, text, integer, integer, uuid[]) to authenticated;

-- ── count_finance_transactions (from 0024_finance.sql) ──
drop function if exists count_finance_transactions(uuid, text, date, date, text, text, text);

create or replace function count_finance_transactions(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_source_type text default null,
  p_status text default null,
  p_search text default null,
  p_facility_sport_ids uuid[] default null
) returns bigint
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  result bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  select count(*) into result from finance_transactions_view v
  where v.facility_id = p_facility_id
    and range_ @> v.effective_at
    and payment_in_sports(v.id, p_facility_sport_ids)
    and (p_source_type is null or v.source_type = p_source_type)
    and (p_status is null or v.status = p_status)
    and (
      p_search is null or trim(p_search) = ''
      or v.reference ilike '%' || p_search || '%'
      or v.id::text ilike '%' || p_search || '%'
      or v.razorpay_payment_id ilike '%' || p_search || '%'
      or v.razorpay_order_id ilike '%' || p_search || '%'
      or (v.booking_id is not null and v.booking_id::text = p_search)
      or (v.membership_id is not null and v.membership_id::text = p_search)
      or v.customer_name ilike '%' || p_search || '%'
    );

  return result;
end;
$$;

grant execute on function count_finance_transactions(uuid, text, date, date, text, text, text, uuid[]) to authenticated;

-- ── get_revenue_breakdown (from 0087_coaching_revenue_breakdown.sql) ──
drop function if exists get_revenue_breakdown(uuid, text, date, date);

create or replace function get_revenue_breakdown(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  membership_revenue_minor bigint,
  member_booking_revenue_minor bigint,
  guest_booking_revenue_minor bigint,
  refunds_minor bigint,
  net_revenue_minor bigint,
  membership_included_usage_count bigint,
  coaching_revenue_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  refunded bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  select coalesce(sum(r.amount_minor), 0)::bigint into refunded
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at and payment_order_in_sports(r.payment_order_id, p_facility_sport_ids);

  return query
  with classified as (
    select v.source_type, v.amount_minor
    from finance_transactions_view v
    where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
      and payment_in_sports(v.id, p_facility_sport_ids)
  )
  select
    coalesce(sum(amount_minor) filter (where source_type = 'MEMBERSHIP'), 0)::bigint,
    coalesce(sum(amount_minor) filter (where source_type = 'MEMBER_BOOKING'), 0)::bigint,
    coalesce(sum(amount_minor) filter (where source_type = 'GUEST_BOOKING'), 0)::bigint,
    refunded::bigint,
    (coalesce(sum(amount_minor), 0) - refunded)::bigint,
    (
      select count(*) from membership_session_bookings msb
      where msb.facility_id = p_facility_id and msb.participant_type = 'MEMBER'
        and msb.status = 'CONFIRMED' and range_ @> msb.created_at
        and session_booking_in_sports(msb.id, p_facility_sport_ids)
    )::bigint,
    coalesce(sum(amount_minor) filter (where source_type = 'COACHING'), 0)::bigint
  from classified;
end;
$$;

grant execute on function get_revenue_breakdown(uuid, text, date, date, uuid[]) to authenticated;

-- ── get_revenue_trend (from 0048_finance_sum_bigint_casts.sql) ──
drop function if exists get_revenue_trend(uuid, text, date, date, text);

create or replace function get_revenue_trend(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_granularity text default 'daily',
  p_facility_sport_ids uuid[] default null
) returns table (
  bucket_date date,
  gross_minor bigint,
  refund_minor bigint,
  net_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  trunc_unit text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if p_granularity not in ('daily', 'weekly', 'monthly') then
    raise exception 'Unknown granularity: %', p_granularity using errcode = '22023';
  end if;
  trunc_unit := case p_granularity when 'daily' then 'day' when 'weekly' then 'week' else 'month' end;

  select timezone into tz from facilities where id = p_facility_id;
  tz := coalesce(tz, 'Asia/Kolkata');
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with gross as (
    select date_trunc(trunc_unit, v.effective_at at time zone tz)::date as bucket,
           coalesce(sum(v.amount_minor), 0)::bigint as amount
    from finance_transactions_view v
    where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
      and payment_in_sports(v.id, p_facility_sport_ids)
    group by 1
  ),
  refund as (
    select date_trunc(trunc_unit, r.processed_at at time zone tz)::date as bucket,
           coalesce(sum(r.amount_minor), 0)::bigint as amount
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at
      and payment_order_in_sports(r.payment_order_id, p_facility_sport_ids)
    group by 1
  ),
  buckets as (
    select bucket from gross union select bucket from refund
  )
  select
    b.bucket,
    coalesce(g.amount, 0)::bigint,
    coalesce(rf.amount, 0)::bigint,
    (coalesce(g.amount, 0) - coalesce(rf.amount, 0))::bigint
  from buckets b
  left join gross g on g.bucket = b.bucket
  left join refund rf on rf.bucket = b.bucket
  order by b.bucket;
end;
$$;

grant execute on function get_revenue_trend(uuid, text, date, date, text, uuid[]) to authenticated;

-- ── get_pnl (from 0077_rbac_wire_permissions.sql) ──
drop function if exists get_pnl(uuid, text, date, date, uuid);

create or replace function get_pnl(
  p_facility_id uuid, p_preset text default 'THIS_MONTH', p_start_date date default null,
  p_end_date date default null, p_category_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  booking_revenue_minor bigint, membership_revenue_minor bigint, guest_booking_revenue_minor bigint,
  other_revenue_minor bigint, gross_revenue_minor bigint, refunds_minor bigint, total_revenue_minor bigint,
  total_expense_minor bigint, net_profit_minor bigint, profit_margin_pct numeric, expense_by_category jsonb
) language plpgsql stable as $$
declare range_ tstzrange; tz text; refunded bigint; gross bigint; mem bigint; memb_book bigint; guest bigint; spent bigint; by_cat jsonb;
begin
  if not has_permission(p_facility_id, 'FINANCE_VIEW_PNL') then
    raise exception 'You don''t have permission to view Profit & Loss.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, coalesce(p_preset, 'THIS_MONTH'), p_start_date, p_end_date);
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  select
    coalesce(sum(v.amount_minor) filter (where v.source_type = 'MEMBERSHIP'), 0)::bigint,
    coalesce(sum(v.amount_minor) filter (where v.source_type = 'MEMBER_BOOKING'), 0)::bigint,
    coalesce(sum(v.amount_minor) filter (where v.source_type = 'GUEST_BOOKING'), 0)::bigint,
    coalesce(sum(v.amount_minor), 0)::bigint
  into mem, memb_book, guest, gross
  from finance_transactions_view v
  where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
    and payment_in_sports(v.id, p_facility_sport_ids);
  select coalesce(sum(r.amount_minor), 0)::bigint into refunded from refunds r
  where r.facility_id = p_facility_id and r.status = 'PROCESSED' and r.processed_at is not null and range_ @> r.processed_at
    and payment_order_in_sports(r.payment_order_id, p_facility_sport_ids);
  select coalesce(sum(t.amt), 0)::bigint,
    coalesce(jsonb_agg(jsonb_build_object('categoryId', t.category_id, 'category', t.name, 'amountMinor', t.amt) order by t.amt desc), '[]'::jsonb)
  into spent, by_cat
  from (
    select e.category_id, c.name, sum(e.amount_minor)::bigint as amt
    from expenses e join expense_categories c on c.id = e.category_id
    where e.facility_id = p_facility_id and e.status = 'RECORDED'
      and range_ @> (e.spent_on::timestamp at time zone tz)
      and (p_category_id is null or e.category_id = p_category_id)
    group by e.category_id, c.name
  ) t;
  return query select memb_book, mem, guest, (gross - mem - memb_book - guest)::bigint, gross, refunded,
    (gross - refunded)::bigint, spent, (gross - refunded - spent)::bigint,
    case when (gross - refunded) > 0 then round(((gross - refunded - spent)::numeric / (gross - refunded)::numeric) * 100, 1) else 0 end,
    by_cat;
end; $$;

grant execute on function get_pnl(uuid, text, date, date, uuid, uuid[]) to authenticated;

-- ── get_pnl_trend (from 0077_rbac_wire_permissions.sql) ──
drop function if exists get_pnl_trend(uuid, text, date, date, text);

create or replace function get_pnl_trend(
  p_facility_id uuid, p_preset text default 'THIS_MONTH', p_start_date date default null,
  p_end_date date default null, p_granularity text default 'daily',
  p_facility_sport_ids uuid[] default null
) returns table (bucket_date date, revenue_minor bigint, expense_minor bigint, net_minor bigint)
language plpgsql stable as $$
declare range_ tstzrange; tz text; unit text;
begin
  if not has_permission(p_facility_id, 'FINANCE_VIEW_PNL') then
    raise exception 'You don''t have permission to view Profit & Loss.' using errcode = '42501';
  end if;
  if p_granularity not in ('daily', 'weekly', 'monthly') then
    raise exception 'Unknown granularity: %', p_granularity using errcode = '22023';
  end if;
  unit := case p_granularity when 'daily' then 'day' when 'weekly' then 'week' else 'month' end;
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  range_ := resolve_finance_date_range(p_facility_id, coalesce(p_preset, 'THIS_MONTH'), p_start_date, p_end_date);
  return query
  with rev as (
    select date_trunc(unit, v.effective_at at time zone tz)::date as bucket, sum(v.amount_minor) as amt
    from finance_transactions_view v
    where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
      and payment_in_sports(v.id, p_facility_sport_ids) group by 1
  ),
  ref as (
    select date_trunc(unit, r.processed_at at time zone tz)::date as bucket, sum(r.amount_minor) as amt
    from refunds r where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at
      and payment_order_in_sports(r.payment_order_id, p_facility_sport_ids) group by 1
  ),
  exp as (
    select date_trunc(unit, e.spent_on::timestamp at time zone tz)::date as bucket, sum(e.amount_minor) as amt
    from expenses e where e.facility_id = p_facility_id and e.status = 'RECORDED'
      and range_ @> (e.spent_on::timestamp at time zone tz) group by 1
  ),
  buckets as (select bucket from rev union select bucket from ref union select bucket from exp)
  select b.bucket, (coalesce(rev.amt, 0) - coalesce(ref.amt, 0))::bigint, coalesce(exp.amt, 0)::bigint,
    (coalesce(rev.amt, 0) - coalesce(ref.amt, 0) - coalesce(exp.amt, 0))::bigint
  from buckets b
  left join rev on rev.bucket = b.bucket
  left join ref on ref.bucket = b.bucket
  left join exp on exp.bucket = b.bucket
  order by b.bucket;
end; $$;

grant execute on function get_pnl_trend(uuid, text, date, date, text, uuid[]) to authenticated;

-- ── list_pending_payments (from 0135_pending_payments_recurring_due_date.sql) ──
drop function if exists list_pending_payments(uuid, text, text, text, date, date, text, integer, integer, uuid);

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
  p_source_id uuid default null,
  p_facility_sport_ids uuid[] default null
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
      -- A running AutoPay that has already collected a charge is next due on its current period's end, not on the
      -- day the membership started; otherwise the start date, as before.
      coalesce(
        (
          select s.current_end
          from membership_subscriptions s
          where s.membership_id = ms.id
            and s.status::text in ('created', 'authenticated', 'active', 'pending')
            and s.charge_count > 0
            and s.current_end is not null
        ),
        ms.start_date
      )
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
      -- Same rule for a monthly coaching subscription: once the first charge is collected, the next due date is
      -- the subscription's current period end (e.g. paid 18 Oct -> next due 17 Nov), not the enrollment start.
      coalesce(
        (
          select b.current_end
          from coaching_enrollment_billing b
          where b.enrollment_id = e.id
            and b.kind = 'SUBSCRIPTION'
            and b.status in ('CREATED', 'AUTHENTICATED', 'ACTIVE', 'PENDING')
            and b.charge_count > 0
            and b.current_end is not null
        ),
        e.start_date
      )
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
        and obligation_in_sports(s.source_type, s.source_id, p_facility_sport_ids)
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

grant execute on function list_pending_payments(uuid, text, text, text, date, date, text, integer, integer, uuid, uuid[]) to authenticated;

-- ── get_pending_payments_summary (from 0053_pending_payment_lookup.sql) ──
drop function if exists get_pending_payments_summary(uuid, date, date);

create or replace function get_pending_payments_summary(
  p_facility_id uuid,
  p_from date default null,
  p_to date default null,
  p_facility_sport_ids uuid[] default null
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
      p_facility_id, null, null, 'ALL_OUTSTANDING', p_from, p_to, 'DUE_DATE', 100000, 0, null, p_facility_sport_ids
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

grant execute on function get_pending_payments_summary(uuid, date, date, uuid[]) to authenticated;

