-- ═══════════════════════════════════════════════════════════════════════════
-- Profit & Loss.
--
-- No new data. P&L is a composition of what already exists:
--   * recognised revenue  → finance_transactions_view (captured payments),
--     classified exactly as get_revenue_breakdown already does it,
--   * refunds             → refunds, PROCESSED, same as everywhere else,
--   * expenses            → expenses, RECORDED, by category, on an accrual
--     basis (counted by spent_on regardless of payment status).
--
-- Net operating profit = recognised revenue − refunds − recorded expenses.
--
-- Reports & Analytics is expected to call get_pnl / get_pnl_trend rather than
-- re-deriving these numbers.
-- ═══════════════════════════════════════════════════════════════════════════


create or replace function get_pnl(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_category_id uuid default null
)
returns table (
  booking_revenue_minor bigint,
  membership_revenue_minor bigint,
  guest_booking_revenue_minor bigint,
  other_revenue_minor bigint,
  gross_revenue_minor bigint,
  refunds_minor bigint,
  total_revenue_minor bigint,
  total_expense_minor bigint,
  net_profit_minor bigint,
  profit_margin_pct numeric,
  expense_by_category jsonb
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  refunded bigint;
  gross bigint;
  mem bigint;
  memb_book bigint;
  guest bigint;
  spent bigint;
  by_cat jsonb;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
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
  where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at;

  select coalesce(sum(r.amount_minor), 0)::bigint
  into refunded
  from refunds r
  where r.facility_id = p_facility_id and r.status = 'PROCESSED'
    and r.processed_at is not null and range_ @> r.processed_at;

  select
    coalesce(sum(t.amt), 0)::bigint,
    coalesce(jsonb_agg(jsonb_build_object('categoryId', t.category_id, 'category', t.name, 'amountMinor', t.amt) order by t.amt desc), '[]'::jsonb)
  into spent, by_cat
  from (
    select e.category_id, c.name, sum(e.amount_minor)::bigint as amt
    from expenses e
    join expense_categories c on c.id = e.category_id
    where e.facility_id = p_facility_id and e.status = 'RECORDED'
      and range_ @> (e.spent_on::timestamp at time zone tz)
      and (p_category_id is null or e.category_id = p_category_id)
    group by e.category_id, c.name
  ) t;

  return query select
    memb_book,
    mem,
    guest,
    (gross - mem - memb_book - guest)::bigint,
    gross,
    refunded,
    (gross - refunded)::bigint,
    spent,
    (gross - refunded - spent)::bigint,
    case when (gross - refunded) > 0
      then round(((gross - refunded - spent)::numeric / (gross - refunded)::numeric) * 100, 1)
      else 0 end,
    by_cat;
end;
$$;

grant execute on function get_pnl(uuid, text, date, date, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Revenue vs expense over time, one row per bucket. Revenue is net of
-- refunds in that bucket; expense is recorded expense dated in that bucket.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_pnl_trend(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_granularity text default 'daily'
)
returns table (
  bucket_date date,
  revenue_minor bigint,
  expense_minor bigint,
  net_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  unit text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
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
    group by 1
  ),
  ref as (
    select date_trunc(unit, r.processed_at at time zone tz)::date as bucket, sum(r.amount_minor) as amt
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at
    group by 1
  ),
  exp as (
    select date_trunc(unit, e.spent_on::timestamp at time zone tz)::date as bucket, sum(e.amount_minor) as amt
    from expenses e
    where e.facility_id = p_facility_id and e.status = 'RECORDED'
      and range_ @> (e.spent_on::timestamp at time zone tz)
    group by 1
  ),
  buckets as (
    select bucket from rev union select bucket from ref union select bucket from exp
  )
  select
    b.bucket,
    (coalesce(rev.amt, 0) - coalesce(ref.amt, 0))::bigint,
    coalesce(exp.amt, 0)::bigint,
    (coalesce(rev.amt, 0) - coalesce(ref.amt, 0) - coalesce(exp.amt, 0))::bigint
  from buckets b
  left join rev on rev.bucket = b.bucket
  left join ref on ref.bucket = b.bucket
  left join exp on exp.bucket = b.bucket
  order by b.bucket;
end;
$$;

grant execute on function get_pnl_trend(uuid, text, date, date, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- list_finance_ledger (0049): the expense line now carries its real payment
-- status instead of a hardcoded 'paid', so the Transactions page can show a
-- bill that is still outstanding. Signature unchanged.
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
      v.id, v.reference, v.effective_at as occurred_at,
      trim(initcap(replace(v.source_type, '_', ' ')) || coalesce(' — ' || v.customer_name, '')) as description,
      case v.source_type
        when 'GUEST_BOOKING' then 'Guest Booking Revenue'
        when 'MEMBERSHIP' then 'Membership Revenue'
        when 'MEMBER_BOOKING' then 'Court Booking Revenue'
        else 'Other Revenue'
      end as category,
      'INCOME'::text as txn_type,
      v.payment_method, v.amount_minor::bigint, v.currency, v.status, v.source_type,
      v.booking_id, v.membership_id, null::uuid as expense_id
    from finance_transactions_view v
    where v.facility_id = p_facility_id

    union all

    select
      r.id, 'RFD-' || upper(substr(r.id::text, 1, 8)), r.processed_at,
      'Refund'::text, 'Booking Refund'::text, 'REFUND'::text, null::text,
      r.amount_minor::bigint, cur, lower(r.status::text), 'REFUND'::text,
      null::uuid, null::uuid, null::uuid
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED' and r.processed_at is not null

    union all

    select
      e.id, 'EXP-' || upper(substr(e.id::text, 1, 8)),
      (e.spent_on::timestamp at time zone tz),
      trim(coalesce(e.vendor, c.name) || coalesce(' — ' || e.notes, '')),
      c.name, 'EXPENSE'::text, e.payment_method, e.amount_minor::bigint, e.currency,
      case e.payment_status when 'PAID' then 'paid' when 'PARTIAL' then 'partial' else 'pending' end,
      'EXPENSE'::text, null::uuid, null::uuid, e.id
    from expenses e
    join expense_categories c on c.id = e.category_id
    where e.facility_id = p_facility_id and e.status = 'RECORDED'
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
