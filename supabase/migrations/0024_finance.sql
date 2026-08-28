-- ═══════════════════════════════════════════════════════════════════════════
-- Finance & Revenue Management — Phase 7.
--
-- NOT a new ledger. `payments` (0001/0016/0019 — authoritative "money was
-- actually captured" record) and `refunds` (0023 — authoritative "money was
-- actually given back" record) already exist and are never duplicated here.
-- This migration is purely a reporting/aggregation layer over them:
--
--   payments + refunds (source of truth)
--         │
--         ▼
--   finance_transactions_view — one enriched row per payment, joined to its
--   source (booking/membership/guest), classified by revenue category, with
--   refunded/pending-refund/net computed live — never a maintained column.
--         │
--         ▼
--   get_finance_summary / get_revenue_breakdown / get_revenue_trend /
--   list_finance_transactions / count_finance_transactions — backend
--   aggregation. The frontend only ever asks "give me Finance for this
--   range" — it never sums payments/refunds itself (spec §"Core Finance
--   Principle" / §"Critical Final Rule").
--
-- Gross revenue = SUM(payments.amount_inr) where status = 'paid' — this is
-- exactly "successfully captured" (apply_payment_verification only ever
-- inserts a payments row on a genuine CAPTURED transition, 0019/0021), so a
-- pending/failed/cancelled payment attempt was NEVER a payments row in the
-- first place and needs no extra filtering to exclude. A SETTLEMENT_EXCEPTION
-- order (money captured, business confirmation failed) still counts as gross
-- revenue — the money is genuinely in the account; it becomes a refund (and
-- only THEN reduces net revenue) if/when the owner resolves it that way
-- (spec §16/§59 — captured-but-unconfirmed is refund/recovery territory, not
-- "never happened").
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- resolve_finance_date_range: every Finance RPC below funnels its date
-- filtering through this one function so "Today"/"This Week"/"This Month"
-- are computed against the FACILITY's configured timezone (spec §"Date/
-- Time" — never assume UTC), not the caller's browser/device clock. Weeks
-- start Monday (ISO 8601, date_trunc's default).
-- ─────────────────────────────────────────────────────────────────────────
create function resolve_finance_date_range(
  p_facility_id uuid,
  p_preset text,
  p_start_date date default null,
  p_end_date date default null
) returns tstzrange
language plpgsql
stable
as $$
declare
  tz text;
  today date;
  range_start date;
  range_end_exclusive date;
begin
  select timezone into tz from facilities where id = p_facility_id;
  tz := coalesce(tz, 'Asia/Kolkata');
  today := (now() at time zone tz)::date;

  if p_preset = 'TODAY' then
    range_start := today; range_end_exclusive := today + 1;
  elsif p_preset = 'YESTERDAY' then
    range_start := today - 1; range_end_exclusive := today;
  elsif p_preset = 'THIS_WEEK' then
    range_start := date_trunc('week', today)::date; range_end_exclusive := range_start + 7;
  elsif p_preset = 'LAST_WEEK' then
    range_start := date_trunc('week', today)::date - 7; range_end_exclusive := range_start + 7;
  elsif p_preset = 'THIS_MONTH' then
    range_start := date_trunc('month', today)::date; range_end_exclusive := (date_trunc('month', today) + interval '1 month')::date;
  elsif p_preset = 'LAST_MONTH' then
    range_start := (date_trunc('month', today) - interval '1 month')::date; range_end_exclusive := date_trunc('month', today)::date;
  elsif p_preset = 'CUSTOM' then
    if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
      raise exception 'A custom date range requires a valid start and end date.' using errcode = '22023';
    end if;
    range_start := p_start_date; range_end_exclusive := p_end_date + 1;
  else
    raise exception 'Unknown date range preset: %', p_preset using errcode = '22023';
  end if;

  return tstzrange(range_start::timestamp at time zone tz, range_end_exclusive::timestamp at time zone tz, '[)');
end;
$$;

grant execute on function resolve_finance_date_range(uuid, text, date, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- finance_transactions_view — the single enriched shape every transaction-
-- level Finance read (list/count/detail) selects from. security_invoker so
-- the existing `payments_select_own_or_staff` RLS policy (facility staff
-- only — members have no Supabase Auth session in this app at all) still
-- governs every row, exactly as if the caller had queried `payments`
-- directly.
-- ─────────────────────────────────────────────────────────────────────────
create view finance_transactions_view with (security_invoker = true) as
select
  p.id,
  'TXN-' || upper(substr(p.id::text, 1, 8)) as reference,
  p.facility_id,
  p.created_at,
  p.paid_at,
  coalesce(p.paid_at, p.created_at) as effective_at,
  -- Revenue category (spec §"Revenue Categories"): payment_orders.source_type
  -- when this payment went through the Razorpay flow (always true since
  -- Phase 3); a manual/cash membership assignment (create_membership,
  -- 0012/0021) never gets a payment_order at all, so it's classified
  -- directly from payments.membership_id instead.
  coalesce(po.source_type::text, case when p.membership_id is not null then 'MEMBERSHIP' else 'MEMBER_BOOKING' end) as source_type,
  coalesce(m.full_name, gp.name, b.guest_name) as customer_name,
  coalesce(m.phone, gp.phone, b.guest_phone) as customer_phone,
  p.booking_id,
  p.membership_id,
  p.payment_order_id,
  -- payments.amount_inr is stored in whole rupees (0001_init.sql); every
  -- other money value in this app (payment_orders/refunds) is minor units
  -- (paise) — normalized to minor units here so Finance is internally
  -- consistent and reuses the same formatCurrency(amountMinor, ...) the
  -- rest of the app already uses.
  (p.amount_inr * 100)::bigint as amount_minor,
  -- payments itself carries no currency column — payment_orders.currency is
  -- authoritative when this went through the Razorpay flow; a manual/cash
  -- membership (no payment_order) falls back to the facility's own
  -- configured currency (spec §"Currency": "use the existing currency
  -- configuration", never a hard-coded literal).
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
-- payments.member_id is always populated for MEMBERSHIP and MEMBER_BOOKING
-- (apply_payment_verification copies it from payment_orders.member_id,
-- which create_payment_order sets for both source types; create_membership's
-- manual path sets it directly) — never for GUEST_BOOKING, which has no
-- member at all.
left join members m on m.id = p.member_id
left join guest_players gp on gp.id = p.guest_player_id
left join lateral (
  select
    sum(r.amount_minor) filter (where r.status = 'PROCESSED') as processed,
    sum(r.amount_minor) filter (where r.status in ('REQUESTED', 'PROCESSING', 'PENDING')) as pending
  from refunds r
  where r.payment_order_id = p.payment_order_id
) rf on true;

grant select on finance_transactions_view to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_finance_transactions / count_finance_transactions: server-side
-- filtered, searched, and paginated (spec §"Transaction Pagination" —
-- never "load everything then paginate locally"). Both share identical
-- filter logic by construction (count is list's WHERE clause without the
-- SELECT/ORDER/LIMIT) so a page count can never silently disagree with what
-- the page itself would return.
-- ─────────────────────────────────────────────────────────────────────────
create function list_finance_transactions(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_source_type text default null,
  p_status text default null,
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0
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

grant execute on function list_finance_transactions(uuid, text, date, date, text, text, text, integer, integer) to authenticated;

create function count_finance_transactions(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_source_type text default null,
  p_status text default null,
  p_search text default null
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

grant execute on function count_finance_transactions(uuid, text, date, date, text, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_finance_transaction: the Transaction Details screen's single read.
-- Explicitly denies (rather than silently 404-ing) a cross-facility lookup
-- attempt, matching this phase's explicit facility-isolation requirement —
-- RLS on the underlying `payments` table already makes this unreachable in
-- practice, this is defense in depth with a clearer failure mode.
-- ─────────────────────────────────────────────────────────────────────────
create function get_finance_transaction(p_transaction_id uuid) returns finance_transactions_view
language plpgsql
stable
as $$
declare
  result finance_transactions_view;
begin
  select * into result from finance_transactions_view where id = p_transaction_id;
  if result.id is null then
    raise exception 'Transaction not found.' using errcode = 'P0002';
  end if;
  if not has_facility_role(result.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  return result;
end;
$$;

grant execute on function get_finance_transaction(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_finance_summary — the dashboard's headline numbers. Explicitly
-- authorization-checked (not just RLS-filtered) so an unauthorized caller
-- gets a clear denial rather than a facility's real gross revenue silently
-- reading as ₹0 (spec §"Critical Facility Isolation Test": "Expected:
-- DENIED", not "expected: zero").
--
-- pending_refund_count / settlement_exception_count are deliberately NOT
-- date-filtered — they're a current, actionable queue ("what needs my
-- attention right now"), not a historical figure for the selected range.
-- ─────────────────────────────────────────────────────────────────────────
create function get_finance_summary(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null
) returns table (
  gross_revenue_minor bigint,
  refunds_minor bigint,
  net_revenue_minor bigint,
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
  gross bigint;
  refunded bigint;
  succ bigint;
  failed bigint;
  pending bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  select coalesce(sum(p.amount_inr), 0) * 100, count(*)
    into gross, succ
    from payments p
    where p.facility_id = p_facility_id and p.status = 'paid' and range_ @> coalesce(p.paid_at, p.created_at);

  select coalesce(sum(r.amount_minor), 0)
    into refunded
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED' and r.processed_at is not null and range_ @> r.processed_at;

  -- A payment_order never reaching CAPTURED never gets a `payments` row at
  -- all (0019/0021) — failed/pending payment *attempts* only exist here,
  -- on payment_orders itself, keyed off when the attempt was made.
  select
    count(*) filter (where po.status = 'FAILED'),
    count(*) filter (where po.status in ('CREATED', 'ORDER_CREATED', 'PAYMENT_ATTEMPTED', 'PAYMENT_VERIFICATION_PENDING', 'PAYMENT_VERIFIED', 'AUTHORIZED'))
    into failed, pending
    from payment_orders po
    where po.facility_id = p_facility_id and range_ @> po.created_at;

  return query select
    gross,
    refunded,
    gross - refunded,
    succ + failed + pending,
    succ,
    failed,
    pending,
    (select count(*) from refunds r2 where r2.facility_id = p_facility_id and r2.status in ('REQUESTED', 'PROCESSING', 'PENDING'))::bigint,
    (select count(*) from settlement_exceptions se where se.facility_id = p_facility_id and se.status = 'OPEN')::bigint;
end;
$$;

grant execute on function get_finance_summary(uuid, text, date, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_revenue_breakdown — Revenue by Source (spec §"Revenue By Source" /
-- §"Membership Included Usage"). membership_included_usage_count is a
-- volume/operational figure, never revenue — a member's included session
-- never has a `payments` row at all (book_membership_slot, 0014), it's
-- counted straight off membership_session_bookings.
-- ─────────────────────────────────────────────────────────────────────────
create function get_revenue_breakdown(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null
) returns table (
  membership_revenue_minor bigint,
  member_booking_revenue_minor bigint,
  guest_booking_revenue_minor bigint,
  refunds_minor bigint,
  net_revenue_minor bigint,
  membership_included_usage_count bigint
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

  select coalesce(sum(r.amount_minor), 0) into refunded
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED' and r.processed_at is not null and range_ @> r.processed_at;

  return query
  with classified as (
    select v.source_type, v.amount_minor
    from finance_transactions_view v
    where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
  )
  select
    coalesce(sum(amount_minor) filter (where source_type = 'MEMBERSHIP'), 0),
    coalesce(sum(amount_minor) filter (where source_type = 'MEMBER_BOOKING'), 0),
    coalesce(sum(amount_minor) filter (where source_type = 'GUEST_BOOKING'), 0),
    refunded,
    coalesce(sum(amount_minor), 0) - refunded,
    (
      select count(*) from membership_session_bookings msb
      where msb.facility_id = p_facility_id and msb.participant_type = 'MEMBER' and msb.status = 'CONFIRMED'
        and range_ @> msb.created_at
    )::bigint
  from classified;
end;
$$;

grant execute on function get_revenue_breakdown(uuid, text, date, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_revenue_trend — the chart's single data source (spec §"Revenue
-- Chart": "must use backend data", never hard-coded). Buckets are computed
-- in the facility's own timezone so a payment just after local midnight
-- lands in the correct day/week/month, not UTC's.
-- ─────────────────────────────────────────────────────────────────────────
create function get_revenue_trend(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_granularity text default 'daily'
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
    select date_trunc(trunc_unit, v.effective_at at time zone tz)::date as bucket, sum(v.amount_minor) as amount
    from finance_transactions_view v
    where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
    group by 1
  ),
  refund as (
    select date_trunc(trunc_unit, r.processed_at at time zone tz)::date as bucket, sum(r.amount_minor) as amount
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED' and r.processed_at is not null and range_ @> r.processed_at
    group by 1
  ),
  buckets as (
    select bucket from gross union select bucket from refund
  )
  select b.bucket, coalesce(g.amount, 0), coalesce(rf.amount, 0), coalesce(g.amount, 0) - coalesce(rf.amount, 0)
  from buckets b
  left join gross g on g.bucket = b.bucket
  left join refund rf on rf.bucket = b.bucket
  order by b.bucket;
end;
$$;

grant execute on function get_revenue_trend(uuid, text, date, date, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_refunds / list_settlement_exceptions (0023_cancellation_refunds.sql)
-- — extended with the filters/date-range Finance → Refunds and Finance →
-- Settlement Exceptions need (spec §"Refund Filters" / §"Exception
-- Filters"). Signatures changed (new params), so the old ones are dropped
-- explicitly first — same reasoning as 0014's create_booking rebuild.
-- Every existing caller (Phase 6's RefundsPanel / mobile RefundsScreen,
-- which pass only `{p_facility_id}` or `{p_facility_id, p_status}` as named
-- RPC arguments) keeps working unchanged: the new parameters all default to
-- "no extra filter", reproducing the old behavior exactly.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists list_refunds(uuid);

create function list_refunds(
  p_facility_id uuid,
  p_status text default null,
  p_source_type text default null,
  p_preset text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_limit integer default 100,
  p_offset integer default 0
) returns setof refunds
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if p_preset is not null then
    range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  end if;

  return query
  select * from refunds
  where facility_id = p_facility_id
    and (p_status is null or status::text = p_status)
    and (p_source_type is null or source_type::text = p_source_type)
    and (range_ is null or range_ @> created_at)
  order by created_at desc
  limit greatest(1, least(p_limit, 200))
  offset greatest(0, p_offset);
end;
$$;

grant execute on function list_refunds(uuid, text, text, text, date, date, integer, integer) to authenticated;

drop function if exists list_settlement_exceptions(uuid, text);

create function list_settlement_exceptions(
  p_facility_id uuid,
  p_status text default 'OPEN',
  p_source_type text default null,
  p_preset text default null,
  p_start_date date default null,
  p_end_date date default null
) returns setof settlement_exceptions
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if p_preset is not null then
    range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  end if;

  return query
  select * from settlement_exceptions
  where facility_id = p_facility_id
    and (p_status is null or status = p_status)
    and (p_source_type is null or source_type::text = p_source_type)
    and (range_ is null or range_ @> created_at)
  order by created_at desc;
end;
$$;

grant execute on function list_settlement_exceptions(uuid, text, text, text, date, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- Indexes — added only where the new range-filtered queries above genuinely
-- need them (spec §"Database Performance": "only where genuinely
-- required"). payments/payment_orders/refunds already have facility_id and
-- created_at coverage (0001/0016/0023); the two new range predicates this
-- phase introduces are paid_at (revenue bucketing) and processed_at
-- (refund bucketing), neither previously indexed.
-- ─────────────────────────────────────────────────────────────────────────
create index payments_facility_paid_at_idx on payments (facility_id, paid_at) where paid_at is not null;
create index refunds_facility_processed_at_idx on refunds (facility_id, processed_at) where processed_at is not null;