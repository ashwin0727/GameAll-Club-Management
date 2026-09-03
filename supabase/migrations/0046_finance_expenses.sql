-- ═══════════════════════════════════════════════════════════════════════════
-- Finance: the outgoing side.
--
-- Finance already exists as a reporting layer over `payments` (money in) and
-- `refunds` (money back), with get_finance_summary / get_revenue_breakdown /
-- get_revenue_trend / list_finance_transactions aggregating them server-side.
-- None of that is rebuilt here.
--
-- What was missing is money going the other way. With no expenses, "net
-- revenue" could only ever mean gross minus refunds — a facility could spend
-- ₹40,000 on court lighting and Finance would still report it had made
-- ₹1,24,500. This adds the expense side and folds it into the same summary,
-- so net revenue finally means what an owner assumes it means.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- Categories live in a table rather than a CHECK constraint or a string
-- scattered through the client, so a facility can add "Insurance" without a
-- migration. Rows with a null facility_id are the shared defaults every
-- facility sees; a facility's own rows are private to it.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists expense_categories (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid references facilities (id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create unique index if not exists expense_categories_facility_name_idx
  on expense_categories (coalesce(facility_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name));

insert into expense_categories (facility_id, name, sort_order)
values
  (null, 'Maintenance', 10),
  (null, 'Utilities', 20),
  (null, 'Staff', 30),
  (null, 'Rent', 40),
  (null, 'Equipment', 50),
  (null, 'Marketing', 60),
  (null, 'Cleaning', 70),
  (null, 'Software', 80),
  (null, 'Other', 999)
on conflict do nothing;


-- ─────────────────────────────────────────────────────────────────────────
-- Expenses. Money is stored in minor units, as everywhere else in this
-- schema — never a float.
--
-- Voided rather than deleted: a financial record that vanishes leaves the
-- books unexplainable, so a mistake is marked void and stays visible with
-- who did it and when.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists expenses (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  category_id uuid not null references expense_categories (id) on delete restrict,
  amount_minor integer not null check (amount_minor > 0),
  currency text not null default 'INR',
  payment_method text,
  spent_on date not null default current_date,
  vendor text,
  reference text,
  notes text,
  status text not null default 'RECORDED' check (status in ('RECORDED', 'VOID')),
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  voided_by uuid references profiles (id) on delete set null,
  voided_at timestamptz,
  void_reason text
);

create index if not exists expenses_facility_date_idx on expenses (facility_id, spent_on);
create index if not exists expenses_category_idx on expenses (category_id);

alter table expenses enable row level security;
alter table expense_categories enable row level security;

-- Finance is private. Only staff of the facility may read or write it, which
-- is the same bar refunds already set. An anonymous booker has no path here.
create policy "expenses_select_staff" on expenses for select
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));
create policy "expenses_write_managers" on expenses for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

-- Shared defaults are readable by any signed-in facility user; a facility's
-- own categories only by its staff.
create policy "expense_categories_select" on expense_categories for select
  using (facility_id is null or is_facility_member(facility_id));
create policy "expense_categories_write_managers" on expense_categories for all
  using (facility_id is not null and has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (facility_id is not null and has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

drop trigger if exists expenses_set_updated_at on expenses;
create trigger expenses_set_updated_at
  before update on expenses
  for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- Record an expense.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function create_expense(
  p_facility_id uuid,
  p_category_id uuid,
  p_amount_minor integer,
  p_spent_on date,
  p_payment_method text default null,
  p_vendor text default null,
  p_reference text default null,
  p_notes text default null
) returns expenses
language plpgsql
security definer
set search_path = public
as $$
declare
  result expenses;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  if coalesce(p_amount_minor, 0) <= 0 then
    raise exception 'Enter an amount greater than zero.' using errcode = '23514';
  end if;

  -- A category must be one of the shared defaults or this facility's own —
  -- never another facility's private category.
  if not exists (
    select 1 from expense_categories c
    where c.id = p_category_id
      and c.is_active
      and (c.facility_id is null or c.facility_id = p_facility_id)
  ) then
    raise exception 'Choose a valid expense category.' using errcode = '23503';
  end if;

  insert into expenses (
    facility_id, category_id, amount_minor, spent_on, payment_method,
    vendor, reference, notes, created_by, updated_by,
    currency
  ) values (
    p_facility_id, p_category_id, p_amount_minor, coalesce(p_spent_on, current_date),
    nullif(trim(p_payment_method), ''), nullif(trim(p_vendor), ''),
    nullif(trim(p_reference), ''), nullif(trim(p_notes), ''), auth.uid(), auth.uid(),
    coalesce((select currency from facilities where id = p_facility_id), 'INR')
  )
  returning * into result;

  return result;
end;
$$;

grant execute on function create_expense(uuid, uuid, integer, date, text, text, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Void an expense. Never a delete: the row stays, marked, with a reason.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function void_expense(p_expense_id uuid, p_reason text default null)
returns expenses
language plpgsql
security definer
set search_path = public
as $$
declare
  result expenses;
begin
  select * into result from expenses where id = p_expense_id;
  if result.id is null then
    raise exception 'Expense not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(result.facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if result.status = 'VOID' then
    raise exception 'This expense has already been voided.' using errcode = '23514';
  end if;

  update expenses
  set status = 'VOID',
      voided_by = auth.uid(),
      voided_at = now(),
      void_reason = nullif(trim(p_reason), ''),
      updated_by = auth.uid()
  where id = p_expense_id
  returning * into result;

  return result;
end;
$$;

grant execute on function void_expense(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- List expenses for a range, newest first.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_expenses(
  p_facility_id uuid,
  p_preset text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_category_id uuid default null,
  p_limit integer default 25,
  p_offset integer default 0
)
returns table (
  id uuid,
  category_id uuid,
  category_name text,
  amount_minor integer,
  currency text,
  payment_method text,
  spent_on date,
  vendor text,
  reference text,
  notes text,
  status text,
  created_at timestamptz,
  total_count bigint
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
  with rows as (
    select e.id, e.category_id, c.name as category_name, e.amount_minor, e.currency,
           e.payment_method, e.spent_on, e.vendor, e.reference, e.notes, e.status, e.created_at
    from expenses e
    join expense_categories c on c.id = e.category_id
    where e.facility_id = p_facility_id
      and range_ @> (e.spent_on::timestamp at time zone coalesce(
        (select timezone from facilities where id = p_facility_id), 'Asia/Kolkata'))
      and (p_category_id is null or e.category_id = p_category_id)
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by r.spent_on desc, r.created_at desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_expenses(uuid, text, date, date, uuid, integer, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_finance_summary — same contract, plus the outgoing side.
--
-- net_revenue_minor previously meant gross minus refunds. It now also takes
-- expenses off, which is what "net" means to the person reading it. The two
-- components are returned separately so a caller can still show the split.
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
  succ bigint;
  failed bigint;
  pending bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  tz := coalesce((select timezone from facilities where id = p_facility_id), 'Asia/Kolkata');

  select coalesce(sum(p.amount_inr), 0) * 100, count(*)
    into gross, succ
    from payments p
    where p.facility_id = p_facility_id and p.status = 'paid' and range_ @> coalesce(p.paid_at, p.created_at);

  select coalesce(sum(r.amount_minor), 0)
    into refunded
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at;

  -- Voided expenses are excluded from the arithmetic but remain on the books.
  select coalesce(sum(e.amount_minor), 0)
    into spent
    from expenses e
    where e.facility_id = p_facility_id and e.status = 'RECORDED'
      and range_ @> (e.spent_on::timestamp at time zone tz);

  -- Unchanged from 0024: failed and pending are payment *attempts*, which
  -- only ever exist on payment_orders — a non-captured attempt never gets a
  -- payments row at all.
  select
    count(*) filter (where po.status = 'FAILED'),
    count(*) filter (where po.status in ('CREATED', 'ORDER_CREATED', 'PAYMENT_ATTEMPTED', 'PAYMENT_VERIFICATION_PENDING', 'PAYMENT_VERIFIED', 'AUTHORIZED'))
    into failed, pending
    from payment_orders po
    where po.facility_id = p_facility_id and range_ @> po.created_at;

  -- Money owed rather than money attempted: bookings that happened and have
  -- not been paid for. Pay-at-venue means this is the normal state until
  -- someone hands over cash, so it is a figure the owner chases.
  select coalesce(sum(b.amount_minor), 0)
    into outstanding
    from bookings b
    where b.facility_id = p_facility_id
      and b.status in ('pending', 'confirmed', 'completed')
      and b.payment_status <> 'PAID'
      and range_ @> b.start_time;

  return query select
    gross,
    refunded,
    spent,
    gross - refunded - spent,
    outstanding,
    succ + failed + pending,
    succ,
    failed,
    pending,
    (select count(*) from refunds r2 where r2.facility_id = p_facility_id and r2.status in ('REQUESTED', 'PROCESSING', 'PENDING'))::bigint,
    (select count(*) from settlement_exceptions se where se.facility_id = p_facility_id and se.status = 'OPEN')::bigint;
end;
$$;

grant execute on function get_finance_summary(uuid, text, date, date) to authenticated;
