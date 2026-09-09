-- ═══════════════════════════════════════════════════════════════════════════
-- Daily Closing — end-of-day cash reconciliation.
--
-- Everything the day produced already lives in payments / expenses /
-- expense_payments. This does not copy any of it. A closing is one row that
-- records three things the ledger cannot know on its own:
--   * the cash float the day started with (opening cash),
--   * the cash actually counted in the drawer at close (actual cash),
--   * why that differs from what the books expect (variance + reason).
--
-- The collection / expense figures are re-derived from the ledger every time
-- the summary is asked for. They are *also* snapshotted onto the row when the
-- day is closed, so a historical closing stays stable if a payment is later
-- backdated — the snapshot is a reconciliation record, not a second ledger.
--
-- One closing per facility per business date. The business date is the
-- facility's own timezone, not the user's device.
-- ═══════════════════════════════════════════════════════════════════════════


create table if not exists daily_closings (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  closing_date date not null,

  opening_cash_minor integer not null default 0 check (opening_cash_minor >= 0),

  -- Snapshot at close. Null while the day is still OPEN.
  cash_collected_minor integer,
  upi_collected_minor integer,
  card_collected_minor integer,
  online_collected_minor integer,
  bank_transfer_collected_minor integer,
  other_collected_minor integer,
  total_collected_minor integer,
  cash_expense_minor integer,
  total_expense_minor integer,
  expected_cash_minor integer,

  actual_cash_minor integer check (actual_cash_minor is null or actual_cash_minor >= 0),
  variance_minor integer,
  variance_reason text,

  status text not null default 'OPEN' check (status in ('OPEN', 'CLOSED', 'REOPENED')),

  opened_by uuid references profiles (id) on delete set null,
  opened_at timestamptz not null default now(),
  closed_by uuid references profiles (id) on delete set null,
  closed_at timestamptz,
  reopened_by uuid references profiles (id) on delete set null,
  reopened_at timestamptz,
  reopen_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint daily_closings_one_per_day unique (facility_id, closing_date)
);

create index if not exists daily_closings_facility_date_idx
  on daily_closings (facility_id, closing_date desc);

alter table daily_closings enable row level security;

drop policy if exists "daily_closings_select_staff" on daily_closings;
create policy "daily_closings_select_staff" on daily_closings for select
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

-- All writes flow through the SECURITY DEFINER RPCs below, which enforce the
-- owner/manager bar themselves. No direct-write policy is granted.

drop trigger if exists daily_closings_set_updated_at on daily_closings;
create trigger daily_closings_set_updated_at
  before update on daily_closings
  for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- Audit trail. Reuses the per-domain events pattern (same as the maintenance
-- module) rather than inventing a global audit table.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists daily_closing_events (
  id uuid primary key default gen_random_uuid(),
  closing_id uuid not null references daily_closings (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  event text not null,
  detail jsonb not null default '{}'::jsonb,
  actor uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists daily_closing_events_closing_idx on daily_closing_events (closing_id, created_at);

alter table daily_closing_events enable row level security;

drop policy if exists "daily_closing_events_select_staff" on daily_closing_events;
create policy "daily_closing_events_select_staff" on daily_closing_events for select
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));


-- ─────────────────────────────────────────────────────────────────────────
-- Bucket a free-text payment method into the reconciliation columns.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function finance_method_bucket(p_method text)
returns text
language sql
immutable
as $$
  select case lower(trim(coalesce(p_method, '')))
    when 'cash' then 'CASH'
    when 'upi' then 'UPI'
    when 'card' then 'CARD'
    when 'credit card' then 'CARD'
    when 'debit card' then 'CARD'
    when 'online' then 'ONLINE'
    when 'razorpay' then 'ONLINE'
    when 'netbanking' then 'ONLINE'
    when 'net banking' then 'ONLINE'
    when 'bank transfer' then 'BANK_TRANSFER'
    when 'neft' then 'BANK_TRANSFER'
    when 'imps' then 'BANK_TRANSFER'
    when 'rtgs' then 'BANK_TRANSFER'
    else 'OTHER'
  end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- The live figures for a business date, plus the closing row if one exists.
-- Collections come from captured payments; cash expenses from settlements
-- (expense_payments) actually paid in cash on that date.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_daily_closing_summary(
  p_facility_id uuid,
  p_date date default null
)
returns table (
  closing_date date,
  opening_cash_minor bigint,
  cash_collected_minor bigint,
  upi_collected_minor bigint,
  card_collected_minor bigint,
  online_collected_minor bigint,
  bank_transfer_collected_minor bigint,
  other_collected_minor bigint,
  total_collected_minor bigint,
  cash_expense_minor bigint,
  other_expense_minor bigint,
  total_expense_minor bigint,
  expected_cash_minor bigint,
  payment_count bigint,
  expense_count bigint,
  pending_payment_count bigint,
  closing_id uuid,
  status text,
  actual_cash_minor bigint,
  variance_minor bigint,
  variance_reason text,
  closed_at timestamptz
)
language plpgsql
stable
as $$
declare
  tz text;
  the_date date;
  day_range tstzrange;
  prior_close integer;
  existing daily_closings;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  the_date := coalesce(p_date, (now() at time zone tz)::date);
  day_range := tstzrange(
    the_date::timestamp at time zone tz,
    (the_date + 1)::timestamp at time zone tz, '[)');

  select * into existing from daily_closings d
    where d.facility_id = p_facility_id and d.closing_date = the_date;

  -- Opening cash: an explicit value on the existing row wins; otherwise the
  -- most recent closed day's counted drawer; otherwise zero.
  select dc.actual_cash_minor into prior_close
    from daily_closings dc
    where dc.facility_id = p_facility_id
      and dc.closing_date < the_date
      and dc.status in ('CLOSED', 'REOPENED')
      and dc.actual_cash_minor is not null
    order by dc.closing_date desc
    limit 1;

  return query
  with pay as (
    select finance_method_bucket(p.payment_method) as bucket, (p.amount_inr * 100)::bigint as amt
    from payments p
    where p.facility_id = p_facility_id and p.status = 'paid'
      and day_range @> coalesce(p.paid_at, p.created_at)
  ),
  pay_agg as (
    select
      coalesce(sum(amt) filter (where bucket = 'CASH'), 0)::bigint as cash,
      coalesce(sum(amt) filter (where bucket = 'UPI'), 0)::bigint as upi,
      coalesce(sum(amt) filter (where bucket = 'CARD'), 0)::bigint as card,
      coalesce(sum(amt) filter (where bucket = 'ONLINE'), 0)::bigint as online,
      coalesce(sum(amt) filter (where bucket = 'BANK_TRANSFER'), 0)::bigint as bank,
      coalesce(sum(amt) filter (where bucket = 'OTHER'), 0)::bigint as other,
      coalesce(sum(amt), 0)::bigint as total,
      count(*)::bigint as cnt
    from pay
  ),
  exp as (
    select
      coalesce(sum(ep.amount_minor) filter (where finance_method_bucket(ep.payment_method) = 'CASH'), 0)::bigint as cash_exp,
      coalesce(sum(ep.amount_minor), 0)::bigint as total_exp,
      count(distinct ep.expense_id)::bigint as cnt
    from expense_payments ep
    join expenses e on e.id = ep.expense_id
    where ep.facility_id = p_facility_id and e.status = 'RECORDED'
      and ep.paid_on = the_date
  ),
  pend as (
    select count(*)::bigint as cnt
    from bookings b
    where b.facility_id = p_facility_id
      and b.status in ('pending', 'confirmed', 'completed')
      and b.payment_status <> 'PAID'
      and day_range @> b.start_time
  )
  select
    the_date,
    coalesce(existing.opening_cash_minor, prior_close, 0)::bigint,
    pay_agg.cash, pay_agg.upi, pay_agg.card, pay_agg.online, pay_agg.bank, pay_agg.other,
    pay_agg.total,
    exp.cash_exp,
    (exp.total_exp - exp.cash_exp)::bigint,
    exp.total_exp,
    (coalesce(existing.opening_cash_minor, prior_close, 0) + pay_agg.cash - exp.cash_exp)::bigint,
    pay_agg.cnt,
    exp.cnt,
    pend.cnt,
    existing.id,
    coalesce(existing.status, 'NOT_STARTED'),
    existing.actual_cash_minor::bigint,
    existing.variance_minor::bigint,
    existing.variance_reason,
    existing.closed_at
  from pay_agg, exp, pend;
end;
$$;

grant execute on function get_daily_closing_summary(uuid, date) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Open the day. Idempotent: returns the existing row if the day is already
-- open. A transaction-level advisory lock plus the unique constraint means
-- two managers hitting "Open" at once still get exactly one row.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function open_daily_closing(
  p_facility_id uuid,
  p_date date default null,
  p_opening_cash_minor integer default null
)
returns daily_closings
language plpgsql
security definer
set search_path = public
as $$
declare
  tz text;
  the_date date;
  result daily_closings;
  prior_close integer;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  the_date := coalesce(p_date, (now() at time zone tz)::date);

  perform pg_advisory_xact_lock(hashtextextended(p_facility_id::text || the_date::text, 0));

  select * into result from daily_closings
    where facility_id = p_facility_id and closing_date = the_date;
  if result.id is not null then
    return result;
  end if;

  if p_opening_cash_minor is null then
    select dc.actual_cash_minor into prior_close
      from daily_closings dc
      where dc.facility_id = p_facility_id and dc.closing_date < the_date
        and dc.status in ('CLOSED', 'REOPENED') and dc.actual_cash_minor is not null
      order by dc.closing_date desc limit 1;
  end if;

  insert into daily_closings (facility_id, closing_date, opening_cash_minor, opened_by)
  values (p_facility_id, the_date, greatest(coalesce(p_opening_cash_minor, prior_close, 0), 0), auth.uid())
  returning * into result;

  insert into daily_closing_events (closing_id, facility_id, event, detail, actor)
  values (result.id, p_facility_id, 'OPENED',
          jsonb_build_object('openingCashMinor', result.opening_cash_minor), auth.uid());

  return result;
end;
$$;

grant execute on function open_daily_closing(uuid, date, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Adjust the opening float before the day is closed.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function set_daily_closing_opening_cash(
  p_closing_id uuid,
  p_opening_cash_minor integer
)
returns daily_closings
language plpgsql
security definer
set search_path = public
as $$
declare
  result daily_closings;
begin
  select * into result from daily_closings where id = p_closing_id for update;
  if result.id is null then
    raise exception 'Closing not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(result.facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if result.status = 'CLOSED' then
    raise exception 'This day is closed. Reopen it to make changes.' using errcode = '23514';
  end if;
  if coalesce(p_opening_cash_minor, -1) < 0 then
    raise exception 'Opening cash cannot be negative.' using errcode = '23514';
  end if;

  update daily_closings set opening_cash_minor = p_opening_cash_minor
   where id = p_closing_id returning * into result;
  return result;
end;
$$;

grant execute on function set_daily_closing_opening_cash(uuid, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Close the day. Expected cash is recomputed here from the ledger — the
-- client's number is never trusted. A non-zero variance must carry a reason.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function close_daily_closing(
  p_closing_id uuid,
  p_actual_cash_minor integer,
  p_variance_reason text default null
)
returns daily_closings
language plpgsql
security definer
set search_path = public
as $$
declare
  result daily_closings;
  s record;
  v_variance integer;
begin
  select * into result from daily_closings where id = p_closing_id for update;
  if result.id is null then
    raise exception 'Closing not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(result.facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if result.status = 'CLOSED' then
    raise exception 'This day''s closing has already been completed.' using errcode = '23505';
  end if;
  if coalesce(p_actual_cash_minor, -1) < 0 then
    raise exception 'Enter the cash counted in the drawer.' using errcode = '23514';
  end if;

  select * into s from get_daily_closing_summary(result.facility_id, result.closing_date);
  v_variance := p_actual_cash_minor - s.expected_cash_minor;

  if v_variance <> 0 and nullif(trim(coalesce(p_variance_reason, '')), '') is null then
    raise exception 'A cash variance needs a short reason.' using errcode = '23514';
  end if;

  update daily_closings set
    cash_collected_minor = s.cash_collected_minor,
    upi_collected_minor = s.upi_collected_minor,
    card_collected_minor = s.card_collected_minor,
    online_collected_minor = s.online_collected_minor,
    bank_transfer_collected_minor = s.bank_transfer_collected_minor,
    other_collected_minor = s.other_collected_minor,
    total_collected_minor = s.total_collected_minor,
    cash_expense_minor = s.cash_expense_minor,
    total_expense_minor = s.total_expense_minor,
    expected_cash_minor = s.expected_cash_minor,
    actual_cash_minor = p_actual_cash_minor,
    variance_minor = v_variance,
    variance_reason = nullif(trim(coalesce(p_variance_reason, '')), ''),
    status = 'CLOSED',
    closed_by = auth.uid(),
    closed_at = now()
  where id = p_closing_id
  returning * into result;

  insert into daily_closing_events (closing_id, facility_id, event, detail, actor)
  values (result.id, result.facility_id, 'CLOSED',
          jsonb_build_object(
            'expectedCashMinor', result.expected_cash_minor,
            'actualCashMinor', result.actual_cash_minor,
            'varianceMinor', result.variance_minor,
            'varianceReason', result.variance_reason), auth.uid());

  return result;
end;
$$;

grant execute on function close_daily_closing(uuid, integer, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Reopen a closed day. Owner/manager only, reason required, audited. The
-- snapshot figures are left in place until the day is closed again.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function reopen_daily_closing(
  p_closing_id uuid,
  p_reason text
)
returns daily_closings
language plpgsql
security definer
set search_path = public
as $$
declare
  result daily_closings;
begin
  select * into result from daily_closings where id = p_closing_id for update;
  if result.id is null then
    raise exception 'Closing not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(result.facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'You don''t have permission to reopen this closing.' using errcode = '42501';
  end if;
  if result.status not in ('CLOSED', 'REOPENED') then
    raise exception 'This day is not closed.' using errcode = '23514';
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Reopening a closed day needs a reason.' using errcode = '23514';
  end if;

  update daily_closings set
    status = 'REOPENED',
    reopened_by = auth.uid(),
    reopened_at = now(),
    reopen_reason = trim(p_reason)
  where id = p_closing_id
  returning * into result;

  insert into daily_closing_events (closing_id, facility_id, event, detail, actor)
  values (result.id, result.facility_id, 'REOPENED',
          jsonb_build_object('reason', result.reopen_reason), auth.uid());

  return result;
end;
$$;

grant execute on function reopen_daily_closing(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Closing history for the list view.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_daily_closings(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_limit integer default 60,
  p_offset integer default 0
)
returns table (
  id uuid,
  closing_date date,
  opening_cash_minor integer,
  total_collected_minor integer,
  total_expense_minor integer,
  expected_cash_minor integer,
  actual_cash_minor integer,
  variance_minor integer,
  status text,
  closed_at timestamptz,
  closed_by_name text,
  total_count bigint
)
language plpgsql
stable
as $$
declare
  tz text;
  d0 date;
  d1 date;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  if p_preset = 'CUSTOM' then
    d0 := p_start_date; d1 := p_end_date;
  else
    d0 := lower(resolve_finance_date_range(p_facility_id, coalesce(p_preset, 'THIS_MONTH'), null, null)) at time zone tz;
    d1 := (upper(resolve_finance_date_range(p_facility_id, coalesce(p_preset, 'THIS_MONTH'), null, null)) at time zone tz)::date - 1;
  end if;

  return query
  with rows as (
    select d.id, d.closing_date, d.opening_cash_minor, d.total_collected_minor,
           d.total_expense_minor, d.expected_cash_minor, d.actual_cash_minor,
           d.variance_minor, d.status, d.closed_at, pr.full_name as closed_by_name
    from daily_closings d
    left join profiles pr on pr.id = d.closed_by
    where d.facility_id = p_facility_id
      and (d0 is null or d.closing_date >= d0)
      and (d1 is null or d.closing_date <= d1)
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by r.closing_date desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_daily_closings(uuid, text, date, date, integer, integer) to authenticated;
