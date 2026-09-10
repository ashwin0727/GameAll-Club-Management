-- ═══════════════════════════════════════════════════════════════════════════
-- Wire has_permission into the sensitive money operations.
--
-- Until now Finance write access was "owner or manager" (the enum). That is
-- exactly the manager role's seeded default, and no non-owner facility_users
-- rows exist yet, so this changes nobody's current access — but it means a
-- custom role (e.g. "Finance Staff") is now gated at the database, not just
-- in the UI (spec §22/§38: "Frontend permissions are NOT security").
--
-- Each function below is recreated verbatim from 0046/0069/0070/0071 with a
-- single line changed: the has_facility_role(...) guard becomes
-- has_permission(facility, '<KEY>').
-- ═══════════════════════════════════════════════════════════════════════════


-- ── refunds: money back ──────────────────────────────────────────────────
-- request_refund / initiate_manual_refund / refund_settlement_exception all
-- run with invoker rights and insert into refunds, so the write policy is the
-- one gate they share.
drop policy if exists "refunds_write_managers" on refunds;
create policy "refunds_write_managers" on refunds for all
  using (has_permission(facility_id, 'FINANCE_REFUND'))
  with check (has_permission(facility_id, 'FINANCE_REFUND'));


-- ── expenses: money out ──────────────────────────────────────────────────
drop policy if exists "expenses_write_managers" on expenses;
create policy "expenses_write_managers" on expenses for all
  using (has_permission(facility_id, 'FINANCE_MANAGE_EXPENSES'))
  with check (has_permission(facility_id, 'FINANCE_MANAGE_EXPENSES'));

drop policy if exists "expenses_select_staff" on expenses;
create policy "expenses_select_staff" on expenses for select
  using (has_permission(facility_id, 'FINANCE_VIEW'));

drop policy if exists "expense_payments_select_staff" on expense_payments;
create policy "expense_payments_select_staff" on expense_payments for select
  using (has_permission(facility_id, 'FINANCE_VIEW'));
drop policy if exists "expense_payments_write_managers" on expense_payments;
create policy "expense_payments_write_managers" on expense_payments for all
  using (has_permission(facility_id, 'FINANCE_MANAGE_EXPENSES'))
  with check (has_permission(facility_id, 'FINANCE_MANAGE_EXPENSES'));

drop policy if exists "expense_categories_write_managers" on expense_categories;
create policy "expense_categories_write_managers" on expense_categories for all
  using (facility_id is not null and has_permission(facility_id, 'FINANCE_MANAGE_EXPENSES'))
  with check (facility_id is not null and has_permission(facility_id, 'FINANCE_MANAGE_EXPENSES'));

create or replace function create_expense(
  p_facility_id uuid, p_category_id uuid, p_amount_minor integer, p_spent_on date,
  p_payment_method text default null, p_vendor text default null, p_reference text default null,
  p_notes text default null, p_payment_status text default 'PAID', p_amount_paid_minor integer default null,
  p_tax_minor integer default null, p_due_on date default null, p_receipt_path text default null
) returns expenses language plpgsql security definer set search_path = public as $$
declare result expenses; v_status text; v_paid integer;
begin
  if not has_permission(p_facility_id, 'FINANCE_MANAGE_EXPENSES') then
    raise exception 'You don''t have permission to manage expenses.' using errcode = '42501';
  end if;
  if coalesce(p_amount_minor, 0) <= 0 then
    raise exception 'Enter an amount greater than zero.' using errcode = '23514';
  end if;
  if not exists (select 1 from expense_categories c where c.id = p_category_id and c.is_active
      and (c.facility_id is null or c.facility_id = p_facility_id)) then
    raise exception 'Choose a valid expense category.' using errcode = '23503';
  end if;
  v_status := coalesce(nullif(trim(p_payment_status), ''), 'PAID');
  if v_status not in ('PAID', 'PARTIAL', 'PENDING') then
    raise exception 'Unknown payment status: %', p_payment_status using errcode = '22023';
  end if;
  v_paid := case
    when p_amount_paid_minor is not null then p_amount_paid_minor
    when v_status = 'PAID' then p_amount_minor
    when v_status = 'PENDING' then 0
    else null end;
  if v_paid is null then
    raise exception 'A partial expense needs the amount already paid.' using errcode = '22023';
  end if;
  if v_paid < 0 or v_paid > p_amount_minor then
    raise exception 'Amount paid must be between zero and the expense total.' using errcode = '23514';
  end if;
  v_status := case when v_paid = 0 then 'PENDING' when v_paid = p_amount_minor then 'PAID' else 'PARTIAL' end;
  insert into expenses (
    facility_id, category_id, amount_minor, spent_on, payment_method, vendor, reference, notes,
    created_by, updated_by, currency, payment_status, amount_paid_minor, tax_minor, due_on, receipt_path
  ) values (
    p_facility_id, p_category_id, p_amount_minor, coalesce(p_spent_on, current_date),
    nullif(trim(p_payment_method), ''), nullif(trim(p_vendor), ''), nullif(trim(p_reference), ''),
    nullif(trim(p_notes), ''), auth.uid(), auth.uid(),
    coalesce((select currency from facilities where id = p_facility_id), 'INR'),
    v_status, v_paid, p_tax_minor, p_due_on, nullif(trim(p_receipt_path), '')
  ) returning * into result;
  if v_paid > 0 then
    insert into expense_payments (expense_id, facility_id, amount_minor, paid_on, payment_method, reference, created_by)
    values (result.id, p_facility_id, v_paid, coalesce(p_spent_on, current_date),
            nullif(trim(p_payment_method), ''), nullif(trim(p_reference), ''), auth.uid());
  end if;
  return result;
end; $$;

create or replace function update_expense(
  p_expense_id uuid, p_category_id uuid default null, p_amount_minor integer default null,
  p_spent_on date default null, p_payment_method text default null, p_vendor text default null,
  p_reference text default null, p_notes text default null, p_tax_minor integer default null,
  p_due_on date default null, p_receipt_path text default null
) returns expenses language plpgsql security definer set search_path = public as $$
declare result expenses; v_amount integer;
begin
  select * into result from expenses where id = p_expense_id;
  if result.id is null then raise exception 'Expense not found' using errcode = 'P0002'; end if;
  if not has_permission(result.facility_id, 'FINANCE_MANAGE_EXPENSES') then
    raise exception 'You don''t have permission to manage expenses.' using errcode = '42501';
  end if;
  if result.status = 'VOID' then raise exception 'A voided expense cannot be edited.' using errcode = '23514'; end if;
  v_amount := coalesce(p_amount_minor, result.amount_minor);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.' using errcode = '23514'; end if;
  if v_amount < result.amount_paid_minor then
    raise exception 'The total cannot be less than the amount already paid (%).', result.amount_paid_minor using errcode = '23514';
  end if;
  if p_category_id is not null and not exists (select 1 from expense_categories c
      where c.id = p_category_id and c.is_active and (c.facility_id is null or c.facility_id = result.facility_id)) then
    raise exception 'Choose a valid expense category.' using errcode = '23503';
  end if;
  update expenses set
    category_id = coalesce(p_category_id, category_id), amount_minor = v_amount,
    spent_on = coalesce(p_spent_on, spent_on),
    payment_method = coalesce(nullif(trim(p_payment_method), ''), payment_method),
    vendor = coalesce(nullif(trim(p_vendor), ''), vendor),
    reference = coalesce(nullif(trim(p_reference), ''), reference),
    notes = coalesce(nullif(trim(p_notes), ''), notes),
    tax_minor = coalesce(p_tax_minor, tax_minor), due_on = coalesce(p_due_on, due_on),
    receipt_path = coalesce(nullif(trim(p_receipt_path), ''), receipt_path),
    payment_status = case when amount_paid_minor = 0 then 'PENDING'
      when amount_paid_minor >= v_amount then 'PAID' else 'PARTIAL' end,
    updated_by = auth.uid()
  where id = p_expense_id returning * into result;
  return result;
end; $$;

create or replace function void_expense(p_expense_id uuid, p_reason text default null)
returns expenses language plpgsql security definer set search_path = public as $$
declare result expenses;
begin
  select * into result from expenses where id = p_expense_id;
  if result.id is null then raise exception 'Expense not found' using errcode = 'P0002'; end if;
  if not has_permission(result.facility_id, 'FINANCE_MANAGE_EXPENSES') then
    raise exception 'You don''t have permission to manage expenses.' using errcode = '42501';
  end if;
  if result.status = 'VOID' then raise exception 'This expense has already been voided.' using errcode = '23514'; end if;
  update expenses set status = 'VOID', voided_by = auth.uid(), voided_at = now(),
    void_reason = nullif(trim(p_reason), ''), updated_by = auth.uid()
  where id = p_expense_id returning * into result;
  return result;
end; $$;

create or replace function record_expense_payment(
  p_expense_id uuid, p_amount_minor integer default null, p_paid_on date default null,
  p_payment_method text default null, p_reference text default null, p_note text default null,
  p_idempotency_key text default null
) returns expenses language plpgsql security definer set search_path = public as $$
declare exp expenses; v_amount integer; v_remaining integer;
begin
  select * into exp from expenses where id = p_expense_id for update;
  if exp.id is null then raise exception 'Expense not found' using errcode = 'P0002'; end if;
  if not has_permission(exp.facility_id, 'FINANCE_MANAGE_EXPENSES') then
    raise exception 'You don''t have permission to manage expenses.' using errcode = '42501';
  end if;
  if exp.status = 'VOID' then raise exception 'A voided expense cannot be paid.' using errcode = '23514'; end if;
  if exp.payment_status = 'PAID' then raise exception 'This expense is already fully paid.' using errcode = '23514'; end if;
  if p_idempotency_key is not null and exists (select 1 from expense_payments
      where expense_id = p_expense_id and reference = 'IDEMP:' || p_idempotency_key) then
    return exp;
  end if;
  v_remaining := exp.amount_minor - exp.amount_paid_minor;
  v_amount := coalesce(p_amount_minor, v_remaining);
  if v_amount <= 0 or v_amount > v_remaining then
    raise exception 'Enter an amount between 1 and the outstanding balance (%).', v_remaining using errcode = '23514';
  end if;
  insert into expense_payments (expense_id, facility_id, amount_minor, paid_on, payment_method, reference, note, created_by)
  values (p_expense_id, exp.facility_id, v_amount, coalesce(p_paid_on, current_date),
    coalesce(nullif(trim(p_payment_method), ''), exp.payment_method),
    coalesce('IDEMP:' || p_idempotency_key, nullif(trim(p_reference), '')),
    nullif(trim(p_note), ''), auth.uid());
  update expenses set amount_paid_minor = amount_paid_minor + v_amount,
    payment_status = case when amount_paid_minor + v_amount >= amount_minor then 'PAID' else 'PARTIAL' end,
    payment_method = coalesce(payment_method, nullif(trim(p_payment_method), '')), updated_by = auth.uid()
  where id = p_expense_id returning * into exp;
  return exp;
end; $$;

-- Expense reads -> FINANCE_VIEW.
create or replace function get_expense_summary(
  p_facility_id uuid, p_preset text default 'THIS_MONTH', p_start_date date default null, p_end_date date default null
) returns table (
  total_minor bigint, this_month_minor bigint, this_week_minor bigint, pending_minor bigint,
  pending_count bigint, maintenance_minor bigint, other_minor bigint
) language plpgsql stable as $$
declare range_ tstzrange; month_ tstzrange; week_ tstzrange; tz text;
begin
  if not has_permission(p_facility_id, 'FINANCE_VIEW') then
    raise exception 'You don''t have permission to view finance.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  month_ := resolve_finance_date_range(p_facility_id, 'THIS_MONTH', null, null);
  week_ := resolve_finance_date_range(p_facility_id, 'THIS_WEEK', null, null);
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  return query
  with ex as (
    select e.amount_minor as amt, e.amount_paid_minor as paid, e.payment_status as pstatus,
           lower(c.name) as cat, (e.spent_on::timestamp at time zone tz) as spent_at
    from expenses e join expense_categories c on c.id = e.category_id
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
end; $$;

-- get_expense: swap the inline WHERE guard to FINANCE_VIEW.
create or replace function get_expense(p_expense_id uuid)
returns table (
  id uuid, facility_id uuid, category_id uuid, category_name text, amount_minor integer,
  amount_paid_minor integer, tax_minor integer, currency text, payment_status text, payment_method text,
  spent_on date, due_on date, vendor text, reference text, notes text, receipt_path text, status text,
  created_by uuid, created_by_name text, created_at timestamptz, updated_at timestamptz,
  voided_at timestamptz, void_reason text, source_maintenance_ticket_id uuid, payments jsonb
) language plpgsql stable as $$
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
    and has_permission(e.facility_id, 'FINANCE_VIEW');
end; $$;


-- ── daily closing: cash reconciliation ───────────────────────────────────
drop policy if exists "daily_closings_select_staff" on daily_closings;
create policy "daily_closings_select_staff" on daily_closings for select
  using (has_permission(facility_id, 'FINANCE_VIEW'));
drop policy if exists "daily_closing_events_select_staff" on daily_closing_events;
create policy "daily_closing_events_select_staff" on daily_closing_events for select
  using (has_permission(facility_id, 'FINANCE_VIEW'));

create or replace function open_daily_closing(
  p_facility_id uuid, p_date date default null, p_opening_cash_minor integer default null
) returns daily_closings language plpgsql security definer set search_path = public as $$
declare tz text; the_date date; result daily_closings; prior_close integer;
begin
  if not has_permission(p_facility_id, 'FINANCE_DAILY_CLOSING') then
    raise exception 'You don''t have permission to run the daily closing.' using errcode = '42501';
  end if;
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  the_date := coalesce(p_date, (now() at time zone tz)::date);
  perform pg_advisory_xact_lock(hashtextextended(p_facility_id::text || the_date::text, 0));
  select * into result from daily_closings where facility_id = p_facility_id and closing_date = the_date;
  if result.id is not null then return result; end if;
  if p_opening_cash_minor is null then
    select dc.actual_cash_minor into prior_close from daily_closings dc
      where dc.facility_id = p_facility_id and dc.closing_date < the_date
        and dc.status in ('CLOSED', 'REOPENED') and dc.actual_cash_minor is not null
      order by dc.closing_date desc limit 1;
  end if;
  insert into daily_closings (facility_id, closing_date, opening_cash_minor, opened_by)
  values (p_facility_id, the_date, greatest(coalesce(p_opening_cash_minor, prior_close, 0), 0), auth.uid())
  returning * into result;
  insert into daily_closing_events (closing_id, facility_id, event, detail, actor)
  values (result.id, p_facility_id, 'OPENED', jsonb_build_object('openingCashMinor', result.opening_cash_minor), auth.uid());
  return result;
end; $$;

create or replace function set_daily_closing_opening_cash(p_closing_id uuid, p_opening_cash_minor integer)
returns daily_closings language plpgsql security definer set search_path = public as $$
declare result daily_closings;
begin
  select * into result from daily_closings where id = p_closing_id for update;
  if result.id is null then raise exception 'Closing not found' using errcode = 'P0002'; end if;
  if not has_permission(result.facility_id, 'FINANCE_DAILY_CLOSING') then
    raise exception 'You don''t have permission to run the daily closing.' using errcode = '42501';
  end if;
  if result.status = 'CLOSED' then raise exception 'This day is closed. Reopen it to make changes.' using errcode = '23514'; end if;
  if coalesce(p_opening_cash_minor, -1) < 0 then raise exception 'Opening cash cannot be negative.' using errcode = '23514'; end if;
  update daily_closings set opening_cash_minor = p_opening_cash_minor where id = p_closing_id returning * into result;
  return result;
end; $$;

create or replace function close_daily_closing(
  p_closing_id uuid, p_actual_cash_minor integer, p_variance_reason text default null
) returns daily_closings language plpgsql security definer set search_path = public as $$
declare result daily_closings; s record; v_variance integer;
begin
  select * into result from daily_closings where id = p_closing_id for update;
  if result.id is null then raise exception 'Closing not found' using errcode = 'P0002'; end if;
  if not has_permission(result.facility_id, 'FINANCE_DAILY_CLOSING') then
    raise exception 'You don''t have permission to run the daily closing.' using errcode = '42501';
  end if;
  if result.status = 'CLOSED' then raise exception 'This day''s closing has already been completed.' using errcode = '23505'; end if;
  if coalesce(p_actual_cash_minor, -1) < 0 then raise exception 'Enter the cash counted in the drawer.' using errcode = '23514'; end if;
  select * into s from get_daily_closing_summary(result.facility_id, result.closing_date);
  v_variance := p_actual_cash_minor - s.expected_cash_minor;
  if v_variance <> 0 and nullif(trim(coalesce(p_variance_reason, '')), '') is null then
    raise exception 'A cash variance needs a short reason.' using errcode = '23514';
  end if;
  update daily_closings set
    cash_collected_minor = s.cash_collected_minor, upi_collected_minor = s.upi_collected_minor,
    card_collected_minor = s.card_collected_minor, online_collected_minor = s.online_collected_minor,
    bank_transfer_collected_minor = s.bank_transfer_collected_minor, other_collected_minor = s.other_collected_minor,
    total_collected_minor = s.total_collected_minor, cash_expense_minor = s.cash_expense_minor,
    total_expense_minor = s.total_expense_minor, expected_cash_minor = s.expected_cash_minor,
    actual_cash_minor = p_actual_cash_minor, variance_minor = v_variance,
    variance_reason = nullif(trim(coalesce(p_variance_reason, '')), ''),
    status = 'CLOSED', closed_by = auth.uid(), closed_at = now()
  where id = p_closing_id returning * into result;
  insert into daily_closing_events (closing_id, facility_id, event, detail, actor)
  values (result.id, result.facility_id, 'CLOSED', jsonb_build_object(
    'expectedCashMinor', result.expected_cash_minor, 'actualCashMinor', result.actual_cash_minor,
    'varianceMinor', result.variance_minor, 'varianceReason', result.variance_reason), auth.uid());
  return result;
end; $$;

create or replace function reopen_daily_closing(p_closing_id uuid, p_reason text)
returns daily_closings language plpgsql security definer set search_path = public as $$
declare result daily_closings;
begin
  select * into result from daily_closings where id = p_closing_id for update;
  if result.id is null then raise exception 'Closing not found' using errcode = 'P0002'; end if;
  if not has_permission(result.facility_id, 'FINANCE_REOPEN_CLOSING') then
    raise exception 'You don''t have permission to reopen a closed day.' using errcode = '42501';
  end if;
  if result.status not in ('CLOSED', 'REOPENED') then raise exception 'This day is not closed.' using errcode = '23514'; end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'Reopening a closed day needs a reason.' using errcode = '23514'; end if;
  update daily_closings set status = 'REOPENED', reopened_by = auth.uid(), reopened_at = now(), reopen_reason = trim(p_reason)
  where id = p_closing_id returning * into result;
  insert into daily_closing_events (closing_id, facility_id, event, detail, actor)
  values (result.id, result.facility_id, 'REOPENED', jsonb_build_object('reason', result.reopen_reason), auth.uid());
  return result;
end; $$;


-- ── P&L ─────────────────────────────────────────────────────────────────
create or replace function get_pnl(
  p_facility_id uuid, p_preset text default 'THIS_MONTH', p_start_date date default null,
  p_end_date date default null, p_category_id uuid default null
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
  where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at;
  select coalesce(sum(r.amount_minor), 0)::bigint into refunded from refunds r
  where r.facility_id = p_facility_id and r.status = 'PROCESSED' and r.processed_at is not null and range_ @> r.processed_at;
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

create or replace function get_pnl_trend(
  p_facility_id uuid, p_preset text default 'THIS_MONTH', p_start_date date default null,
  p_end_date date default null, p_granularity text default 'daily'
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
    where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at group by 1
  ),
  ref as (
    select date_trunc(unit, r.processed_at at time zone tz)::date as bucket, sum(r.amount_minor) as amt
    from refunds r where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at group by 1
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


-- ── bookings: cancellation ──────────────────────────────────────────────
-- cancel_booking (0023) keeps its has_facility_role check for now; a
-- follow-up recreates it to gate on BOOKINGS_CANCEL. The refund it may
-- trigger already routes through the FINANCE_REFUND-gated refunds policy.

