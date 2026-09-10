-- ═══════════════════════════════════════════════════════════════════════════
-- Expenses, completed: payment status, part-payments, edit, receipts, detail.
--
-- 0046 gave a facility a way to record what it spent and fold the total into
-- Net Revenue. It assumed every expense was paid in full the moment it was
-- entered — there was no "the electricity bill is due but unpaid", no way to
-- correct a typo without voiding, no receipt, no per-row payment history.
--
-- This adds those without a second ledger:
--   * expenses.payment_status / amount_paid_minor track how much of an
--     expense has actually been settled. The expense still counts in P&L and
--     Net Revenue the moment it is RECORDED (accrual) — payment status only
--     drives cash reconciliation (0070) and the "what do we still owe" view.
--   * expense_payments is the trail of individual settlements against one
--     expense (Mark Paid, or a part payment). It is NOT a general-purpose
--     partial-payment engine — incoming money keeps using payments /
--     payment_orders exactly as before.
--   * update_expense edits a RECORDED expense in place, with updated_by/at.
--   * expense-receipts is a PRIVATE storage bucket, folder-scoped per
--     facility, readable only by that facility's staff.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- New columns on expenses. amount_minor stays the full cost; amount_paid_minor
-- is how much of it has been handed over. payment_status is derived by the
-- RPCs below and constrained to stay consistent with the two amounts.
-- ─────────────────────────────────────────────────────────────────────────
alter table expenses
  add column if not exists amount_paid_minor integer not null default 0 check (amount_paid_minor >= 0),
  add column if not exists payment_status text not null default 'PAID'
    check (payment_status in ('PAID', 'PARTIAL', 'PENDING')),
  add column if not exists tax_minor integer check (tax_minor is null or tax_minor >= 0),
  add column if not exists receipt_path text,
  add column if not exists due_on date;

-- Existing rows predate the concept and were all treated as paid in full —
-- voided ones included (their payment state is moot, but it must still be
-- internally consistent for the constraint below).
update expenses
  set amount_paid_minor = amount_minor, payment_status = 'PAID'
  where amount_paid_minor <> amount_minor or payment_status is distinct from 'PAID';

-- amount_paid never exceeds the cost; status matches the split. A VOID row is
-- exempt from the status/amount pairing — it has been struck off the books.
alter table expenses drop constraint if exists expenses_payment_consistent;
alter table expenses add constraint expenses_payment_consistent check (
  amount_paid_minor <= amount_minor
  and (
    status = 'VOID'
    or (payment_status = 'PENDING' and amount_paid_minor = 0)
    or (payment_status = 'PARTIAL' and amount_paid_minor > 0 and amount_paid_minor < amount_minor)
    or (payment_status = 'PAID' and amount_paid_minor = amount_minor)
  )
);

create index if not exists expenses_payment_status_idx
  on expenses (facility_id, payment_status) where status = 'RECORDED';


-- ─────────────────────────────────────────────────────────────────────────
-- The settlement trail. One row per time money actually left the facility
-- for a given expense.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists expense_payments (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references expenses (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  amount_minor integer not null check (amount_minor > 0),
  paid_on date not null default current_date,
  payment_method text,
  reference text,
  note text,
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists expense_payments_expense_idx on expense_payments (expense_id);
create index if not exists expense_payments_facility_date_idx on expense_payments (facility_id, paid_on);

alter table expense_payments enable row level security;

drop policy if exists "expense_payments_select_staff" on expense_payments;
create policy "expense_payments_select_staff" on expense_payments for select
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

drop policy if exists "expense_payments_write_managers" on expense_payments;
create policy "expense_payments_write_managers" on expense_payments for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));


-- ─────────────────────────────────────────────────────────────────────────
-- create_expense — same as 0046 plus the initial payment position. A caller
-- that passes nothing new gets the old behaviour (paid in full, method on
-- the expense). Existing callers (0068 maintenance posts through it with 8
-- positional args) keep working — every new parameter defaults.
--
-- The 8-arg signature is dropped first: adding parameters makes a new
-- overload rather than replacing, and an 8-arg call would then be ambiguous.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists create_expense(uuid, uuid, integer, date, text, text, text, text);

create or replace function create_expense(
  p_facility_id uuid,
  p_category_id uuid,
  p_amount_minor integer,
  p_spent_on date,
  p_payment_method text default null,
  p_vendor text default null,
  p_reference text default null,
  p_notes text default null,
  p_payment_status text default 'PAID',
  p_amount_paid_minor integer default null,
  p_tax_minor integer default null,
  p_due_on date default null,
  p_receipt_path text default null
) returns expenses
language plpgsql
security definer
set search_path = public
as $$
declare
  result expenses;
  v_status text;
  v_paid integer;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  if coalesce(p_amount_minor, 0) <= 0 then
    raise exception 'Enter an amount greater than zero.' using errcode = '23514';
  end if;

  if not exists (
    select 1 from expense_categories c
    where c.id = p_category_id
      and c.is_active
      and (c.facility_id is null or c.facility_id = p_facility_id)
  ) then
    raise exception 'Choose a valid expense category.' using errcode = '23503';
  end if;

  v_status := coalesce(nullif(trim(p_payment_status), ''), 'PAID');
  if v_status not in ('PAID', 'PARTIAL', 'PENDING') then
    raise exception 'Unknown payment status: %', p_payment_status using errcode = '22023';
  end if;

  -- Resolve the paid amount from the status when the caller does not give one.
  v_paid := case
    when p_amount_paid_minor is not null then p_amount_paid_minor
    when v_status = 'PAID' then p_amount_minor
    when v_status = 'PENDING' then 0
    else null
  end;
  if v_paid is null then
    raise exception 'A partial expense needs the amount already paid.' using errcode = '22023';
  end if;
  if v_paid < 0 or v_paid > p_amount_minor then
    raise exception 'Amount paid must be between zero and the expense total.' using errcode = '23514';
  end if;
  -- Keep status and amount honest with each other.
  v_status := case
    when v_paid = 0 then 'PENDING'
    when v_paid = p_amount_minor then 'PAID'
    else 'PARTIAL'
  end;

  insert into expenses (
    facility_id, category_id, amount_minor, spent_on, payment_method,
    vendor, reference, notes, created_by, updated_by, currency,
    payment_status, amount_paid_minor, tax_minor, due_on, receipt_path
  ) values (
    p_facility_id, p_category_id, p_amount_minor, coalesce(p_spent_on, current_date),
    nullif(trim(p_payment_method), ''), nullif(trim(p_vendor), ''),
    nullif(trim(p_reference), ''), nullif(trim(p_notes), ''), auth.uid(), auth.uid(),
    coalesce((select currency from facilities where id = p_facility_id), 'INR'),
    v_status, v_paid, p_tax_minor, p_due_on, nullif(trim(p_receipt_path), '')
  )
  returning * into result;

  -- An amount already paid at creation is its own settlement row.
  if v_paid > 0 then
    insert into expense_payments (expense_id, facility_id, amount_minor, paid_on, payment_method, reference, created_by)
    values (result.id, p_facility_id, v_paid, coalesce(p_spent_on, current_date),
            nullif(trim(p_payment_method), ''), nullif(trim(p_reference), ''), auth.uid());
  end if;

  return result;
end;
$$;

grant execute on function create_expense(uuid, uuid, integer, date, text, text, text, text, text, integer, integer, date, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- update_expense — edit a RECORDED expense. Cannot change money that has
-- already been settled below the paid amount; cannot touch a VOID row.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function update_expense(
  p_expense_id uuid,
  p_category_id uuid default null,
  p_amount_minor integer default null,
  p_spent_on date default null,
  p_payment_method text default null,
  p_vendor text default null,
  p_reference text default null,
  p_notes text default null,
  p_tax_minor integer default null,
  p_due_on date default null,
  p_receipt_path text default null
) returns expenses
language plpgsql
security definer
set search_path = public
as $$
declare
  result expenses;
  v_amount integer;
begin
  select * into result from expenses where id = p_expense_id;
  if result.id is null then
    raise exception 'Expense not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(result.facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if result.status = 'VOID' then
    raise exception 'A voided expense cannot be edited.' using errcode = '23514';
  end if;

  v_amount := coalesce(p_amount_minor, result.amount_minor);
  if v_amount <= 0 then
    raise exception 'Enter an amount greater than zero.' using errcode = '23514';
  end if;
  if v_amount < result.amount_paid_minor then
    raise exception 'The total cannot be less than the amount already paid (%).', result.amount_paid_minor
      using errcode = '23514';
  end if;

  if p_category_id is not null and not exists (
    select 1 from expense_categories c
    where c.id = p_category_id and c.is_active
      and (c.facility_id is null or c.facility_id = result.facility_id)
  ) then
    raise exception 'Choose a valid expense category.' using errcode = '23503';
  end if;

  update expenses set
    category_id = coalesce(p_category_id, category_id),
    amount_minor = v_amount,
    spent_on = coalesce(p_spent_on, spent_on),
    payment_method = coalesce(nullif(trim(p_payment_method), ''), payment_method),
    vendor = coalesce(nullif(trim(p_vendor), ''), vendor),
    reference = coalesce(nullif(trim(p_reference), ''), reference),
    notes = coalesce(nullif(trim(p_notes), ''), notes),
    tax_minor = coalesce(p_tax_minor, tax_minor),
    due_on = coalesce(p_due_on, due_on),
    receipt_path = coalesce(nullif(trim(p_receipt_path), ''), receipt_path),
    payment_status = case
      when amount_paid_minor = 0 then 'PENDING'
      when amount_paid_minor >= v_amount then 'PAID'
      else 'PARTIAL'
    end,
    updated_by = auth.uid()
  where id = p_expense_id
  returning * into result;

  return result;
end;
$$;

grant execute on function update_expense(uuid, uuid, integer, date, text, text, text, text, integer, date, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- record_expense_payment — settle all or part of a PENDING/PARTIAL expense.
-- Idempotency: pass p_idempotency_key to make a retried "Mark Paid" safe.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function record_expense_payment(
  p_expense_id uuid,
  p_amount_minor integer default null,
  p_paid_on date default null,
  p_payment_method text default null,
  p_reference text default null,
  p_note text default null,
  p_idempotency_key text default null
) returns expenses
language plpgsql
security definer
set search_path = public
as $$
declare
  exp expenses;
  v_amount integer;
  v_remaining integer;
begin
  select * into exp from expenses where id = p_expense_id for update;
  if exp.id is null then
    raise exception 'Expense not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(exp.facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if exp.status = 'VOID' then
    raise exception 'A voided expense cannot be paid.' using errcode = '23514';
  end if;
  if exp.payment_status = 'PAID' then
    raise exception 'This expense is already fully paid.' using errcode = '23514';
  end if;

  if p_idempotency_key is not null and exists (
    select 1 from expense_payments
    where expense_id = p_expense_id and reference = 'IDEMP:' || p_idempotency_key
  ) then
    return exp;
  end if;

  v_remaining := exp.amount_minor - exp.amount_paid_minor;
  v_amount := coalesce(p_amount_minor, v_remaining);
  if v_amount <= 0 or v_amount > v_remaining then
    raise exception 'Enter an amount between 1 and the outstanding balance (%).', v_remaining
      using errcode = '23514';
  end if;

  insert into expense_payments (expense_id, facility_id, amount_minor, paid_on, payment_method, reference, note, created_by)
  values (
    p_expense_id, exp.facility_id, v_amount, coalesce(p_paid_on, current_date),
    coalesce(nullif(trim(p_payment_method), ''), exp.payment_method),
    coalesce('IDEMP:' || p_idempotency_key, nullif(trim(p_reference), '')),
    nullif(trim(p_note), ''), auth.uid()
  );

  update expenses set
    amount_paid_minor = amount_paid_minor + v_amount,
    payment_status = case
      when amount_paid_minor + v_amount >= amount_minor then 'PAID'
      else 'PARTIAL'
    end,
    payment_method = coalesce(payment_method, nullif(trim(p_payment_method), '')),
    updated_by = auth.uid()
  where id = p_expense_id
  returning * into exp;

  return exp;
end;
$$;

grant execute on function record_expense_payment(uuid, integer, date, text, text, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_expense — one expense in full, for the detail screen.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_expense(p_expense_id uuid)
returns table (
  id uuid,
  facility_id uuid,
  category_id uuid,
  category_name text,
  amount_minor integer,
  amount_paid_minor integer,
  tax_minor integer,
  currency text,
  payment_status text,
  payment_method text,
  spent_on date,
  due_on date,
  vendor text,
  reference text,
  notes text,
  receipt_path text,
  status text,
  created_by uuid,
  created_by_name text,
  created_at timestamptz,
  updated_at timestamptz,
  voided_at timestamptz,
  void_reason text,
  source_maintenance_ticket_id uuid,
  payments jsonb
)
language plpgsql
stable
as $$
begin
  return query
  select
    e.id, e.facility_id, e.category_id, c.name, e.amount_minor, e.amount_paid_minor,
    e.tax_minor, e.currency, e.payment_status, e.payment_method, e.spent_on, e.due_on,
    e.vendor, e.reference, e.notes, e.receipt_path, e.status,
    e.created_by, pr.full_name, e.created_at, e.updated_at, e.voided_at, e.void_reason,
    (select mt.id from maintenance_tickets mt where mt.expense_id = e.id limit 1),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ep.id, 'amountMinor', ep.amount_minor, 'paidOn', ep.paid_on,
        'paymentMethod', ep.payment_method, 'reference', ep.reference, 'note', ep.note,
        'createdAt', ep.created_at
      ) order by ep.paid_on, ep.created_at)
      from expense_payments ep where ep.expense_id = e.id
        and coalesce(ep.reference, '') not like 'IDEMP:%'
    ), '[]'::jsonb)
  from expenses e
  join expense_categories c on c.id = e.category_id
  left join profiles pr on pr.id = e.created_by
  where e.id = p_expense_id
    and has_facility_role(e.facility_id, array['owner', 'manager', 'staff']::facility_role[]);
end;
$$;

grant execute on function get_expense(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_expense_summary — the KPI row on the Expenses page. All figures are
-- RECORDED expenses only, in the facility's timezone.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_expense_summary(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null
)
returns table (
  total_minor bigint,
  this_month_minor bigint,
  this_week_minor bigint,
  pending_minor bigint,
  pending_count bigint,
  maintenance_minor bigint,
  other_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  month_ tstzrange;
  week_ tstzrange;
  tz text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  month_ := resolve_finance_date_range(p_facility_id, 'THIS_MONTH', null, null);
  week_ := resolve_finance_date_range(p_facility_id, 'THIS_WEEK', null, null);
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');

  return query
  with ex as (
    select e.amount_minor as amt, e.amount_paid_minor as paid, e.payment_status as pstatus,
           lower(c.name) as cat,
           (e.spent_on::timestamp at time zone tz) as spent_at
    from expenses e
    join expense_categories c on c.id = e.category_id
    where e.facility_id = p_facility_id and e.status = 'RECORDED'
  )
  select
    coalesce(sum(amt) filter (where range_ @> spent_at), 0)::bigint,
    coalesce(sum(amt) filter (where month_ @> spent_at), 0)::bigint,
    coalesce(sum(amt) filter (where week_ @> spent_at), 0)::bigint,
    coalesce(sum(amt - paid) filter (where pstatus <> 'PAID'), 0)::bigint,
    coalesce(count(*) filter (where pstatus <> 'PAID'), 0)::bigint,
    coalesce(sum(amt) filter (where range_ @> spent_at and cat = 'maintenance'), 0)::bigint,
    coalesce(sum(amt) filter (where range_ @> spent_at and cat <> 'maintenance'), 0)::bigint
  from ex;
end;
$$;

grant execute on function get_expense_summary(uuid, text, date, date) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- list_expenses — 0046's signature plus the filters the list page needs.
-- Old callers (Flutter/web passing the first few named args) are unaffected:
-- every new parameter defaults to "no filter". Dropped-and-recreated because
-- the return shape gains columns.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists list_expenses(uuid, text, date, date, uuid, integer, integer);

create function list_expenses(
  p_facility_id uuid,
  p_preset text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_category_id uuid default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_search text default null,
  p_payment_status text default null,
  p_payment_method text default null,
  p_vendor text default null,
  p_min_minor integer default null,
  p_max_minor integer default null,
  p_include_void boolean default true
)
returns table (
  id uuid,
  category_id uuid,
  category_name text,
  amount_minor integer,
  amount_paid_minor integer,
  currency text,
  payment_method text,
  payment_status text,
  spent_on date,
  due_on date,
  vendor text,
  reference text,
  notes text,
  receipt_path text,
  status text,
  created_by_name text,
  created_at timestamptz,
  total_count bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, coalesce(p_preset, 'THIS_MONTH'), p_start_date, p_end_date);
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');

  return query
  with rows as (
    select e.id, e.category_id, c.name as category_name, e.amount_minor, e.amount_paid_minor,
           e.currency, e.payment_method, e.payment_status, e.spent_on, e.due_on, e.vendor,
           e.reference, e.notes, e.receipt_path, e.status, pr.full_name as created_by_name, e.created_at
    from expenses e
    join expense_categories c on c.id = e.category_id
    left join profiles pr on pr.id = e.created_by
    where e.facility_id = p_facility_id
      and range_ @> (e.spent_on::timestamp at time zone tz)
      and (p_category_id is null or e.category_id = p_category_id)
      and (p_include_void or e.status = 'RECORDED')
      and (p_payment_status is null or e.payment_status = p_payment_status)
      and (p_payment_method is null or e.payment_method = p_payment_method)
      and (p_vendor is null or e.vendor ilike '%' || trim(p_vendor) || '%')
      and (p_min_minor is null or e.amount_minor >= p_min_minor)
      and (p_max_minor is null or e.amount_minor <= p_max_minor)
      and (
        p_search is null or trim(p_search) = ''
        or e.vendor ilike '%' || trim(p_search) || '%'
        or e.reference ilike '%' || trim(p_search) || '%'
        or e.notes ilike '%' || trim(p_search) || '%'
        or c.name ilike '%' || trim(p_search) || '%'
      )
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by r.spent_on desc, r.created_at desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_expenses(uuid, text, date, date, uuid, integer, integer, text, text, text, text, integer, integer, boolean) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Receipts / attachments. Private bucket — a financial document is never
-- world-readable. Path convention: <facility_id>/<expense_id>/<filename>.
-- ─────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'expense-receipts', 'expense-receipts', false, 10485760,
  array['image/jpeg', 'image/png', 'application/pdf']
)
on conflict (id) do nothing;

drop policy if exists "expense receipts readable by facility staff" on storage.objects;
create policy "expense receipts readable by facility staff"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'expense-receipts'
    and has_facility_role(
      ((storage.foldername(name))[1])::uuid,
      array['owner', 'manager', 'staff']::facility_role[]
    )
  );

drop policy if exists "expense receipts written by facility managers" on storage.objects;
create policy "expense receipts written by facility managers"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'expense-receipts'
    and has_facility_role(
      ((storage.foldername(name))[1])::uuid,
      array['owner', 'manager']::facility_role[]
    )
  );

drop policy if exists "expense receipts replaced by facility managers" on storage.objects;
create policy "expense receipts replaced by facility managers"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'expense-receipts'
    and has_facility_role(
      ((storage.foldername(name))[1])::uuid,
      array['owner', 'manager']::facility_role[]
    )
  );

drop policy if exists "expense receipts removed by facility managers" on storage.objects;
create policy "expense receipts removed by facility managers"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'expense-receipts'
    and has_facility_role(
      ((storage.foldername(name))[1])::uuid,
      array['owner', 'manager']::facility_role[]
    )
  );
