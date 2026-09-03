-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: 42702 "column reference "id" is ambiguous".
--
-- Both functions below RETURN TABLE with a column named id, which plpgsql
-- treats as an OUT variable inside the body. Each then looked up the
-- facility timezone with a bare "where id = p_facility_id", and that id
-- could mean either the OUT variable or facilities.id.
-- PostgreSQL refuses to guess.
--
-- Aliasing the table settles it. Nothing else about either function changes.
--
-- Only these two were affected: the other functions doing the same lookup
-- return jsonb, a scalar, or a row type, so they have no OUT variable named
-- id to collide with.
-- ═══════════════════════════════════════════════════════════════════════════

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
        (select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata'))
      and (p_category_id is null or e.category_id = p_category_id)
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by r.spent_on desc, r.created_at desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_expenses(uuid, text, date, date, uuid, integer, integer) to authenticated;


create or replace function list_finance_ledger(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  -- INCOME | EXPENSE | REFUND
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
    -- Money in.
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

    -- Money back. Shown as its own line rather than folded into the payment,
    -- so the audit trail reads as what happened, in order.
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

    -- Money out. Voided expenses are excluded, as they are from the totals.
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
      'paid'::text,
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
