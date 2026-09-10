-- ═══════════════════════════════════════════════════════════════════════════
-- Purchase Orders — vendor ↔ inventory ↔ finance.
--
--   Vendor → Purchase Order (DRAFT)
--          → placed (ORDERED)      → ONE expense created (the obligation)
--          → goods received        → stock moves, PO status advances
--          → payment recorded      → expense settled (FINANCE_RECORD_PAYMENT)
--
-- Stock only ever moves on receipt (spec §14/§15). The money lives in the
-- ONE `expenses` table (0069) — never a second vendor-payment ledger
-- (spec §16/§51). Purchase status and payment status are independent (§17).
-- Totals are recomputed server-side; the client's numbers are never trusted
-- (§13/§60).
-- ═══════════════════════════════════════════════════════════════════════════


-- A shared default expense category for inventory purchases.
insert into expense_categories (facility_id, name, sort_order)
values (null, 'Inventory Purchase', 55)
on conflict do nothing;


create table if not exists purchase_orders (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  vendor_id uuid not null references vendors (id) on delete restrict,
  po_number text not null,
  order_date date not null default current_date,
  expected_delivery date,
  status text not null default 'DRAFT'
    check (status in ('DRAFT', 'ORDERED', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED')),
  subtotal_minor integer not null default 0 check (subtotal_minor >= 0),
  tax_minor integer not null default 0 check (tax_minor >= 0),
  discount_minor integer not null default 0 check (discount_minor >= 0),
  total_minor integer not null default 0 check (total_minor >= 0),
  reference text,
  notes text,
  invoice_path text,
  -- The financial obligation this PO represents. Null until the PO is placed.
  expense_id uuid references expenses (id) on delete set null,
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancel_reason text,
  constraint purchase_orders_number_unique unique (facility_id, po_number)
);

create index if not exists purchase_orders_facility_status_idx on purchase_orders (facility_id, status);
create index if not exists purchase_orders_vendor_idx on purchase_orders (vendor_id);

alter table purchase_orders enable row level security;

drop policy if exists "purchase_orders_select" on purchase_orders;
create policy "purchase_orders_select" on purchase_orders for select
  using (has_permission(facility_id, 'PURCHASE_VIEW'));

drop trigger if exists purchase_orders_set_updated_at on purchase_orders;
create trigger purchase_orders_set_updated_at
  before update on purchase_orders
  for each row execute function set_updated_at();


create table if not exists purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references purchase_orders (id) on delete cascade,
  item_id uuid not null references inventory_items (id) on delete restrict,
  quantity_ordered integer not null check (quantity_ordered > 0),
  quantity_received integer not null default 0 check (quantity_received >= 0),
  unit_cost_minor integer not null check (unit_cost_minor >= 0),
  tax_minor integer not null default 0 check (tax_minor >= 0),
  discount_minor integer not null default 0 check (discount_minor >= 0),
  line_total_minor integer not null check (line_total_minor >= 0),
  constraint poi_received_lte_ordered check (quantity_received <= quantity_ordered),
  constraint poi_one_row_per_item unique (purchase_order_id, item_id)
);

create index if not exists purchase_order_items_po_idx on purchase_order_items (purchase_order_id);

alter table purchase_order_items enable row level security;

drop policy if exists "purchase_order_items_select" on purchase_order_items;
create policy "purchase_order_items_select" on purchase_order_items for select
  using (exists (
    select 1 from purchase_orders po
    where po.id = purchase_order_items.purchase_order_id
      and has_permission(po.facility_id, 'PURCHASE_VIEW')
  ));


-- ─────────────────────────────────────────────────────────────────────────
-- next_po_number — PO-YYYY-NNNN, sequential per facility per year. The
-- advisory lock serialises concurrent creates so two POs never collide.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function next_po_number(p_facility_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  yr text := to_char(now(), 'YYYY');
  n integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_facility_id::text || 'po' || yr, 0));
  select count(*) + 1 into n from purchase_orders
    where facility_id = p_facility_id and po_number like 'PO-' || yr || '-%';
  return 'PO-' || yr || '-' || lpad(n::text, 4, '0');
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- upsert_po_lines — replace a PO's lines from a jsonb array and recompute
-- the header totals. Shared by create and edit.
--   p_lines : [{ "itemId": uuid, "quantity": int, "unitCostMinor": int,
--                "taxMinor": int?, "discountMinor": int? }, ...]
-- ─────────────────────────────────────────────────────────────────────────
create or replace function upsert_po_lines(p_po_id uuid, p_facility_id uuid, p_lines jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  ln jsonb;
  v_item uuid;
  v_qty integer;
  v_cost integer;
  v_tax integer;
  v_disc integer;
  v_line_total integer;
  sub integer := 0;
  tax_total integer := 0;
  disc_total integer := 0;
begin
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'A purchase order needs at least one line item.' using errcode = '23514';
  end if;

  delete from purchase_order_items where purchase_order_id = p_po_id;

  for ln in select * from jsonb_array_elements(p_lines) loop
    v_item := (ln ->> 'itemId')::uuid;
    v_qty := coalesce((ln ->> 'quantity')::integer, 0);
    v_cost := coalesce((ln ->> 'unitCostMinor')::integer, 0);
    v_tax := coalesce((ln ->> 'taxMinor')::integer, 0);
    v_disc := coalesce((ln ->> 'discountMinor')::integer, 0);

    if v_qty <= 0 then raise exception 'Line quantity must be positive.' using errcode = '23514'; end if;
    if v_cost < 0 or v_tax < 0 or v_disc < 0 then raise exception 'Line amounts cannot be negative.' using errcode = '23514'; end if;
    if not exists (select 1 from inventory_items i where i.id = v_item and i.facility_id = p_facility_id) then
      raise exception 'A line item does not belong to this facility.' using errcode = '23503';
    end if;

    v_line_total := (v_qty * v_cost) + v_tax - v_disc;
    if v_line_total < 0 then v_line_total := 0; end if;

    insert into purchase_order_items (purchase_order_id, item_id, quantity_ordered, unit_cost_minor, tax_minor, discount_minor, line_total_minor)
    values (p_po_id, v_item, v_qty, v_cost, v_tax, v_disc, v_line_total)
    on conflict (purchase_order_id, item_id) do update
      set quantity_ordered = excluded.quantity_ordered,
          unit_cost_minor = excluded.unit_cost_minor,
          tax_minor = excluded.tax_minor,
          discount_minor = excluded.discount_minor,
          line_total_minor = excluded.line_total_minor;

    sub := sub + (v_qty * v_cost);
    tax_total := tax_total + v_tax;
    disc_total := disc_total + v_disc;
  end loop;

  update purchase_orders set
    subtotal_minor = sub,
    tax_minor = tax_total,
    discount_minor = disc_total,
    total_minor = greatest(sub + tax_total - disc_total, 0)
  where id = p_po_id;
end;
$$;


create or replace function create_purchase_order(
  p_facility_id uuid,
  p_vendor_id uuid,
  p_lines jsonb,
  p_order_date date default null,
  p_expected_delivery date default null,
  p_reference text default null,
  p_notes text default null,
  p_invoice_path text default null
) returns purchase_orders
language plpgsql security definer set search_path = public as $$
declare result purchase_orders;
begin
  if not has_permission(p_facility_id, 'PURCHASE_CREATE') then
    raise exception 'You don''t have permission to create purchase orders.' using errcode = '42501';
  end if;
  if not exists (select 1 from vendors v where v.id = p_vendor_id and v.facility_id = p_facility_id and v.status = 'ACTIVE') then
    raise exception 'Choose an active vendor.' using errcode = '23503';
  end if;

  insert into purchase_orders (facility_id, vendor_id, po_number, order_date, expected_delivery, reference, notes, invoice_path, created_by)
  values (
    p_facility_id, p_vendor_id, next_po_number(p_facility_id),
    coalesce(p_order_date, current_date), p_expected_delivery,
    nullif(trim(coalesce(p_reference, '')), ''), nullif(trim(coalesce(p_notes, '')), ''),
    nullif(trim(coalesce(p_invoice_path, '')), ''), auth.uid()
  )
  returning * into result;

  perform upsert_po_lines(result.id, p_facility_id, p_lines);
  select * into result from purchase_orders where id = result.id;

  perform log_inventory_event(p_facility_id, 'PO_CREATED', 'Purchase order created: ' || result.po_number,
    null, p_vendor_id, result.id, jsonb_build_object('totalMinor', result.total_minor));
  return result;
end;
$$;

grant execute on function create_purchase_order(uuid, uuid, jsonb, date, date, text, text, text) to authenticated;


create or replace function update_purchase_order(
  p_po_id uuid,
  p_lines jsonb default null,
  p_expected_delivery date default null,
  p_reference text default null,
  p_notes text default null,
  p_invoice_path text default null
) returns purchase_orders
language plpgsql security definer set search_path = public as $$
declare po purchase_orders; result purchase_orders;
begin
  select * into po from purchase_orders where id = p_po_id;
  if po.id is null then raise exception 'Purchase order not found.' using errcode = 'P0002'; end if;
  if not has_permission(po.facility_id, 'PURCHASE_EDIT') then
    raise exception 'You don''t have permission to edit purchase orders.' using errcode = '42501';
  end if;
  if po.status not in ('DRAFT', 'ORDERED') then
    raise exception 'A purchase order that has goods received cannot be edited.' using errcode = '23514';
  end if;
  if p_lines is not null and po.status = 'ORDERED'
     and exists (select 1 from purchase_order_items where purchase_order_id = p_po_id and quantity_received > 0) then
    raise exception 'Line items cannot change once goods have been received.' using errcode = '23514';
  end if;

  update purchase_orders set
    expected_delivery = coalesce(p_expected_delivery, expected_delivery),
    reference = coalesce(p_reference, reference),
    notes = coalesce(p_notes, notes),
    invoice_path = coalesce(nullif(trim(coalesce(p_invoice_path, '')), ''), invoice_path)
  where id = p_po_id;

  if p_lines is not null then
    perform upsert_po_lines(p_po_id, po.facility_id, p_lines);
    -- Keep the linked expense in step with the new total.
    update expenses e set amount_minor = pnew.total_minor, tax_minor = pnew.tax_minor, updated_by = auth.uid()
    from (select total_minor, tax_minor from purchase_orders where id = p_po_id) pnew
    where e.id = po.expense_id and e.status = 'RECORDED';
  end if;

  select * into result from purchase_orders where id = p_po_id;
  perform log_inventory_event(po.facility_id, 'PO_UPDATED', 'Purchase order updated: ' || result.po_number,
    null, po.vendor_id, result.id);
  return result;
end;
$$;

grant execute on function update_purchase_order(uuid, jsonb, date, text, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- place_purchase_order — DRAFT → ORDERED. Creates the ONE financial
-- obligation directly in `expenses` (PENDING). Placing a PO is a purchasing
-- action, so it is gated on PURCHASE_CREATE, not on a Finance permission —
-- but the money still lands in the single expenses ledger (spec §16/§51).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function place_purchase_order(p_po_id uuid) returns purchase_orders
language plpgsql security definer set search_path = public as $$
declare
  po purchase_orders;
  v_vendor vendors;
  v_cat uuid;
  v_expense_id uuid;
begin
  select * into po from purchase_orders where id = p_po_id for update;
  if po.id is null then raise exception 'Purchase order not found.' using errcode = 'P0002'; end if;
  if not has_permission(po.facility_id, 'PURCHASE_CREATE') then
    raise exception 'You don''t have permission to place purchase orders.' using errcode = '42501';
  end if;
  if po.status <> 'DRAFT' then
    raise exception 'This purchase order has already been placed.' using errcode = '23505';
  end if;
  if not exists (select 1 from purchase_order_items where purchase_order_id = p_po_id) then
    raise exception 'Add line items before placing the order.' using errcode = '23514';
  end if;
  if po.total_minor <= 0 then
    raise exception 'A purchase order total must be greater than zero.' using errcode = '23514';
  end if;

  select * into v_vendor from vendors where id = po.vendor_id;
  select id into v_cat from expense_categories
    where name = 'Inventory Purchase' and (facility_id is null or facility_id = po.facility_id)
    order by facility_id nulls last limit 1;

  insert into expenses (
    facility_id, category_id, amount_minor, spent_on, vendor, reference, notes,
    payment_status, amount_paid_minor, tax_minor, due_on, receipt_path,
    created_by, updated_by, currency
  ) values (
    po.facility_id, v_cat, po.total_minor, po.order_date, v_vendor.name, po.po_number,
    'Purchase order ' || po.po_number, 'PENDING', 0, po.tax_minor, po.expected_delivery,
    po.invoice_path, auth.uid(), auth.uid(),
    coalesce((select currency from facilities where id = po.facility_id), 'INR')
  )
  returning id into v_expense_id;

  update purchase_orders set status = 'ORDERED', expense_id = v_expense_id where id = p_po_id
  returning * into po;

  perform log_inventory_event(po.facility_id, 'PO_PLACED', 'Purchase order placed: ' || po.po_number,
    null, po.vendor_id, po.id, jsonb_build_object('totalMinor', po.total_minor, 'expenseId', v_expense_id));
  return po;
end;
$$;

grant execute on function place_purchase_order(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- receive_purchase_order — atomic goods receipt (spec §62). Each entry:
--   [{ "lineId": uuid, "quantity": int }]
-- Stock moves for the received quantity only; can never exceed pending;
-- PO status recomputed; audited. Any failure rolls back the whole receipt.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function receive_purchase_order(p_po_id uuid, p_receipts jsonb)
returns purchase_orders
language plpgsql security definer set search_path = public as $$
declare
  po purchase_orders;
  r jsonb;
  v_line purchase_order_items;
  v_recv integer;
  v_item inventory_items;
  new_balance integer;
  new_cost integer;
  all_received boolean;
  any_received boolean;
begin
  select * into po from purchase_orders where id = p_po_id for update;
  if po.id is null then raise exception 'Purchase order not found.' using errcode = 'P0002'; end if;
  if not has_permission(po.facility_id, 'PURCHASE_RECEIVE') then
    raise exception 'You don''t have permission to receive goods.' using errcode = '42501';
  end if;
  if po.status not in ('ORDERED', 'PARTIALLY_RECEIVED') then
    raise exception 'This purchase order is not open for receiving.' using errcode = '23514';
  end if;
  if p_receipts is null or jsonb_array_length(p_receipts) = 0 then
    raise exception 'Enter a quantity to receive.' using errcode = '23514';
  end if;

  for r in select * from jsonb_array_elements(p_receipts) loop
    v_recv := coalesce((r ->> 'quantity')::integer, 0);
    if v_recv <= 0 then continue; end if;

    select * into v_line from purchase_order_items
      where id = (r ->> 'lineId')::uuid and purchase_order_id = p_po_id for update;
    if v_line.id is null then
      raise exception 'A receipt line does not belong to this purchase order.' using errcode = '23503';
    end if;
    if v_line.quantity_received + v_recv > v_line.quantity_ordered then
      raise exception 'Cannot receive more than the % pending for a line.',
        v_line.quantity_ordered - v_line.quantity_received using errcode = '23514';
    end if;

    select * into v_item from inventory_items where id = v_line.item_id for update;

    new_balance := v_item.current_stock + v_recv;
    new_cost := v_item.unit_cost_minor;
    if v_item.current_stock + v_recv > 0 then
      new_cost := ((v_item.current_stock * v_item.unit_cost_minor) + (v_recv * v_line.unit_cost_minor))
                  / (v_item.current_stock + v_recv);
    end if;

    update inventory_items
      set current_stock = new_balance, unit_cost_minor = new_cost, updated_by = auth.uid()
      where id = v_item.id;

    update purchase_order_items set quantity_received = quantity_received + v_recv where id = v_line.id;

    insert into inventory_movements (
      facility_id, item_id, movement_type, quantity, balance_after, unit_cost_minor,
      reason, reference_type, reference_id, performed_by
    ) values (
      po.facility_id, v_item.id, 'PURCHASE_RECEIVED', v_recv, new_balance, v_line.unit_cost_minor,
      'Received against ' || po.po_number, 'purchase_order', po.id, auth.uid()
    );
  end loop;

  select
    bool_and(quantity_received >= quantity_ordered),
    bool_or(quantity_received > 0)
  into all_received, any_received
  from purchase_order_items where purchase_order_id = p_po_id;

  update purchase_orders set
    status = case when all_received then 'RECEIVED' when any_received then 'PARTIALLY_RECEIVED' else status end
  where id = p_po_id
  returning * into po;

  perform log_inventory_event(po.facility_id, 'PO_RECEIVED',
    'Goods received against ' || po.po_number, null, po.vendor_id, po.id,
    jsonb_build_object('status', po.status));
  return po;
end;
$$;

grant execute on function receive_purchase_order(uuid, jsonb) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- cancel_purchase_order — never once fully received (spec §63). A PO with no
-- goods received also voids its expense; a partially-received one keeps the
-- obligation and the received stock, and is marked CANCELLED for the rest.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function cancel_purchase_order(p_po_id uuid, p_reason text) returns purchase_orders
language plpgsql security definer set search_path = public as $$
declare po purchase_orders; received_total integer;
begin
  select * into po from purchase_orders where id = p_po_id for update;
  if po.id is null then raise exception 'Purchase order not found.' using errcode = 'P0002'; end if;
  if not has_permission(po.facility_id, 'PURCHASE_CANCEL') then
    raise exception 'You don''t have permission to cancel purchase orders.' using errcode = '42501';
  end if;
  if po.status = 'RECEIVED' then
    raise exception 'A fully received purchase order cannot be cancelled.' using errcode = '23514';
  end if;
  if po.status = 'CANCELLED' then
    raise exception 'This purchase order is already cancelled.' using errcode = '23505';
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Cancelling a purchase order needs a reason.' using errcode = '23514';
  end if;

  select coalesce(sum(quantity_received), 0) into received_total from purchase_order_items where purchase_order_id = p_po_id;

  update purchase_orders set status = 'CANCELLED', cancelled_at = now(), cancel_reason = trim(p_reason)
  where id = p_po_id returning * into po;

  -- No goods received → the obligation never really existed; void the expense.
  if received_total = 0 and po.expense_id is not null then
    update expenses set status = 'VOID', voided_by = auth.uid(), voided_at = now(),
      void_reason = 'Purchase order cancelled', updated_by = auth.uid()
    where id = po.expense_id and status = 'RECORDED';
  end if;

  perform log_inventory_event(po.facility_id, 'PO_CANCELLED', 'Purchase order cancelled: ' || po.po_number,
    null, po.vendor_id, po.id, jsonb_build_object('reason', trim(p_reason), 'receivedTotal', received_total));
  return po;
end;
$$;

grant execute on function cancel_purchase_order(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- record_purchase_payment — settle (part of) a PO's expense. Gated on
-- FINANCE_RECORD_PAYMENT so PURCHASE_CREATE alone cannot mark money as paid
-- (spec §33). Settles the same `expenses` row — no second ledger.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function record_purchase_payment(
  p_po_id uuid,
  p_amount_minor integer default null,
  p_paid_on date default null,
  p_payment_method text default null,
  p_reference text default null,
  p_note text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  po purchase_orders;
  exp expenses;
  v_amount integer;
  v_remaining integer;
begin
  select * into po from purchase_orders where id = p_po_id;
  if po.id is null then raise exception 'Purchase order not found.' using errcode = 'P0002'; end if;
  if not has_permission(po.facility_id, 'FINANCE_RECORD_PAYMENT') then
    raise exception 'You don''t have permission to record payments.' using errcode = '42501';
  end if;
  if po.expense_id is null then
    raise exception 'Place the purchase order before recording a payment.' using errcode = '23514';
  end if;

  select * into exp from expenses where id = po.expense_id for update;
  if exp.status <> 'RECORDED' then raise exception 'This purchase order''s expense is not open.' using errcode = '23514'; end if;
  if exp.payment_status = 'PAID' then raise exception 'This purchase order is already fully paid.' using errcode = '23514'; end if;

  v_remaining := exp.amount_minor - exp.amount_paid_minor;
  v_amount := coalesce(p_amount_minor, v_remaining);
  if v_amount <= 0 or v_amount > v_remaining then
    raise exception 'Enter an amount between 1 and the % outstanding.', v_remaining using errcode = '23514';
  end if;

  insert into expense_payments (expense_id, facility_id, amount_minor, paid_on, payment_method, reference, note, created_by)
  values (exp.id, po.facility_id, v_amount, coalesce(p_paid_on, current_date),
          nullif(trim(coalesce(p_payment_method, '')), ''), coalesce(nullif(trim(coalesce(p_reference, '')), ''), po.po_number),
          nullif(trim(coalesce(p_note, '')), ''), auth.uid());

  update expenses set
    amount_paid_minor = amount_paid_minor + v_amount,
    payment_status = case when amount_paid_minor + v_amount >= amount_minor then 'PAID' else 'PARTIAL' end,
    payment_method = coalesce(payment_method, nullif(trim(coalesce(p_payment_method, '')), '')),
    updated_by = auth.uid()
  where id = exp.id;

  perform log_inventory_event(po.facility_id, 'PO_PAYMENT_RECORDED',
    'Payment recorded for ' || po.po_number, null, po.vendor_id, po.id,
    jsonb_build_object('amountMinor', v_amount));
end;
$$;

grant execute on function record_purchase_payment(uuid, integer, date, text, text, text) to authenticated;
