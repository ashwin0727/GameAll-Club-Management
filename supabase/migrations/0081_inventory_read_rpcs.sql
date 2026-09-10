-- ═══════════════════════════════════════════════════════════════════════════
-- Inventory & Vendors — read RPCs + document storage.
--
-- Stock status is DERIVED, never stored (spec §2: don't mix item lifecycle
-- status with stock status):
--   current_stock = 0                      → OUT_OF_STOCK
--   0 < current_stock <= reorder_level     → LOW_STOCK
--   else                                   → IN_STOCK
-- Inventory value = current_stock * unit_cost_minor (weighted average).
-- Every RPC gates on INVENTORY_VIEW / PURCHASE_VIEW / VENDOR_VIEW.
-- ═══════════════════════════════════════════════════════════════════════════


create or replace function inventory_stock_status(p_current integer, p_reorder integer) returns text
language sql immutable as $$
  select case
    when coalesce(p_current, 0) <= 0 then 'OUT_OF_STOCK'
    when p_current <= coalesce(p_reorder, 0) then 'LOW_STOCK'
    else 'IN_STOCK'
  end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- get_inventory_overview — the dashboard.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_inventory_overview(p_facility_id uuid)
returns jsonb
language plpgsql stable as $$
declare result jsonb;
begin
  if not has_permission(p_facility_id, 'INVENTORY_VIEW') then
    raise exception 'You don''t have permission to view inventory.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'kpis', (
      select jsonb_build_object(
        'totalItems', count(*) filter (where status = 'ACTIVE'),
        'lowStockItems', count(*) filter (where status = 'ACTIVE' and current_stock > 0 and current_stock <= reorder_level),
        'outOfStockItems', count(*) filter (where status = 'ACTIVE' and current_stock <= 0),
        'inactiveItems', count(*) filter (where status = 'INACTIVE'),
        'inventoryValueMinor', coalesce(sum(current_stock::bigint * unit_cost_minor) filter (where status = 'ACTIVE'), 0),
        'activeVendors', (select count(*) from vendors where facility_id = p_facility_id and status = 'ACTIVE'),
        'pendingPurchaseOrders', (select count(*) from purchase_orders where facility_id = p_facility_id and status in ('ORDERED', 'PARTIALLY_RECEIVED'))
      )
      from inventory_items where facility_id = p_facility_id
    ),
    'stockStatus', (
      select jsonb_build_object(
        'inStock', count(*) filter (where status = 'ACTIVE' and current_stock > reorder_level),
        'lowStock', count(*) filter (where status = 'ACTIVE' and current_stock > 0 and current_stock <= reorder_level),
        'outOfStock', count(*) filter (where status = 'ACTIVE' and current_stock <= 0),
        'inactive', count(*) filter (where status = 'INACTIVE')
      )
      from inventory_items where facility_id = p_facility_id
    ),
    'recentMovements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'date', m.created_at, 'type', m.movement_type, 'itemName', i.name,
        'quantity', m.quantity, 'reference', coalesce(po.po_number, m.reason),
        'performedBy', pr.full_name
      ) order by m.created_at desc)
      from (select * from inventory_movements where facility_id = p_facility_id order by created_at desc limit 10) m
      join inventory_items i on i.id = m.item_id
      left join profiles pr on pr.id = m.performed_by
      left join purchase_orders po on m.reference_type = 'purchase_order' and po.id = m.reference_id
    ), '[]'::jsonb),
    'lowStockItems', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'name', i.name, 'sku', i.sku, 'category', i.category,
        'currentStock', i.current_stock, 'reorderLevel', i.reorder_level,
        'stockStatus', inventory_stock_status(i.current_stock, i.reorder_level)
      ) order by i.current_stock)
      from inventory_items i
      where i.facility_id = p_facility_id and i.status = 'ACTIVE' and i.current_stock <= i.reorder_level
      limit 10
    ), '[]'::jsonb),
    'topCategoriesByValue', coalesce((
      select jsonb_agg(jsonb_build_object('category', cat, 'valueMinor', val) order by val desc)
      from (
        select coalesce(c.name, i.category, 'Uncategorised') as cat,
               sum(i.current_stock::bigint * i.unit_cost_minor) as val
        from inventory_items i
        left join inventory_categories c on c.id = i.category_id
        where i.facility_id = p_facility_id and i.status = 'ACTIVE'
        group by 1
        order by val desc
        limit 6
      ) t
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

grant execute on function get_inventory_overview(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- list_inventory_items
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_inventory_items(
  p_facility_id uuid,
  p_search text default null,
  p_category_id uuid default null,
  p_status text default null,
  p_stock_status text default null,
  p_vendor_id uuid default null,
  p_sort text default 'name',
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid, name text, sku text, category_id uuid, category_name text, brand text,
  unit text, current_stock integer, reorder_level integer, unit_cost_minor integer,
  inventory_value_minor bigint, status text, stock_status text, image_path text,
  total_count bigint
)
language plpgsql stable as $$
begin
  if not has_permission(p_facility_id, 'INVENTORY_VIEW') then
    raise exception 'You don''t have permission to view inventory.' using errcode = '42501';
  end if;

  return query
  with rows as (
    select
      i.id, i.name, i.sku, i.category_id, coalesce(c.name, i.category) as category_name, i.brand,
      i.unit, i.current_stock, i.reorder_level, i.unit_cost_minor,
      (i.current_stock::bigint * i.unit_cost_minor) as inventory_value_minor,
      i.status, inventory_stock_status(i.current_stock, i.reorder_level) as stock_status, i.image_path
    from inventory_items i
    left join inventory_categories c on c.id = i.category_id
    where i.facility_id = p_facility_id
      and (p_category_id is null or i.category_id = p_category_id)
      and (p_status is null or i.status = p_status)
      and (p_vendor_id is null or i.preferred_vendor_id = p_vendor_id)
      and (p_stock_status is null or inventory_stock_status(i.current_stock, i.reorder_level) = p_stock_status)
      and (
        p_search is null or trim(p_search) = ''
        or i.name ilike '%' || trim(p_search) || '%'
        or i.sku ilike '%' || trim(p_search) || '%'
        or coalesce(i.brand, '') ilike '%' || trim(p_search) || '%'
        or coalesce(c.name, i.category) ilike '%' || trim(p_search) || '%'
      )
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by
    case when p_sort = 'stock_asc' then r.current_stock end asc nulls last,
    case when p_sort = 'value_desc' then r.inventory_value_minor end desc nulls last,
    r.name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_inventory_items(uuid, text, uuid, text, text, uuid, text, integer, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_inventory_item — the details screen (server-side aggregates, spec §4).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_inventory_item(p_item_id uuid)
returns jsonb
language plpgsql stable as $$
declare i inventory_items; result jsonb;
begin
  select * into i from inventory_items where id = p_item_id;
  if i.id is null then raise exception 'Item not found.' using errcode = 'P0002'; end if;
  if not has_permission(i.facility_id, 'INVENTORY_VIEW') then
    raise exception 'You don''t have permission to view inventory.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', i.id, 'facilityId', i.facility_id, 'name', i.name, 'sku', i.sku, 'brand', i.brand,
    'description', i.description, 'unit', i.unit, 'categoryId', i.category_id,
    'categoryName', (select name from inventory_categories where id = i.category_id),
    'currentStock', i.current_stock, 'reorderLevel', i.reorder_level,
    'unitCostMinor', i.unit_cost_minor, 'defaultUnitCostMinor', i.default_unit_cost_minor,
    'inventoryValueMinor', i.current_stock::bigint * i.unit_cost_minor,
    'status', i.status, 'stockStatus', inventory_stock_status(i.current_stock, i.reorder_level),
    'imagePath', i.image_path,
    'preferredVendorId', i.preferred_vendor_id,
    'preferredVendorName', (select name from vendors where id = i.preferred_vendor_id),
    'stats', (
      select jsonb_build_object(
        'totalInQty', coalesce(sum(quantity) filter (where quantity > 0), 0),
        'totalOutQty', coalesce(-sum(quantity) filter (where quantity < 0), 0),
        'lastStockInAt', max(created_at) filter (where movement_type in ('STOCK_IN', 'PURCHASE_RECEIVED', 'RETURN')),
        'lastStockOutAt', max(created_at) filter (where movement_type = 'STOCK_OUT')
      )
      from inventory_movements where item_id = i.id
    ),
    'recentMovements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'date', m.created_at, 'type', m.movement_type, 'quantity', m.quantity,
        'balanceAfter', m.balance_after, 'reason', m.reason, 'notes', m.notes,
        'performedBy', pr.full_name, 'referenceType', m.reference_type, 'referenceId', m.reference_id
      ) order by m.created_at desc)
      from (select * from inventory_movements where item_id = i.id order by created_at desc limit 20) m
      left join profiles pr on pr.id = m.performed_by
    ), '[]'::jsonb),
    'purchases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'poId', po.id, 'poNumber', po.po_number, 'vendorName', v.name, 'orderDate', po.order_date,
        'quantityOrdered', poi.quantity_ordered, 'quantityReceived', poi.quantity_received,
        'unitCostMinor', poi.unit_cost_minor, 'status', po.status
      ) order by po.order_date desc)
      from purchase_order_items poi
      join purchase_orders po on po.id = poi.purchase_order_id
      join vendors v on v.id = po.vendor_id
      where poi.item_id = i.id
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

grant execute on function get_inventory_item(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- list_stock_movements
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_stock_movements(
  p_facility_id uuid,
  p_movement_type text default null,
  p_item_id uuid default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_performed_by uuid default null,
  p_limit integer default 25,
  p_offset integer default 0
)
returns table (
  id uuid, created_at timestamptz, movement_type text, item_id uuid, item_name text,
  quantity integer, balance_after integer, reference text, reference_type text, reference_id uuid,
  performed_by_name text, reason text, notes text, total_count bigint
)
language plpgsql stable as $$
begin
  if not has_permission(p_facility_id, 'INVENTORY_VIEW') then
    raise exception 'You don''t have permission to view inventory.' using errcode = '42501';
  end if;

  return query
  with rows as (
    select m.id, m.created_at, m.movement_type, m.item_id, i.name as item_name,
           m.quantity, m.balance_after,
           coalesce(po.po_number, mt.title, m.reason) as reference,
           m.reference_type, m.reference_id, pr.full_name as performed_by_name, m.reason, m.notes
    from inventory_movements m
    join inventory_items i on i.id = m.item_id
    left join profiles pr on pr.id = m.performed_by
    left join purchase_orders po on m.reference_type = 'purchase_order' and po.id = m.reference_id
    left join maintenance_tickets mt on m.reference_type = 'maintenance_ticket' and mt.id = m.reference_id
    where m.facility_id = p_facility_id
      and (p_movement_type is null or m.movement_type = p_movement_type)
      and (p_item_id is null or m.item_id = p_item_id)
      and (p_from is null or m.created_at >= p_from)
      and (p_to is null or m.created_at <= p_to)
      and (p_performed_by is null or m.performed_by = p_performed_by)
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by r.created_at desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_stock_movements(uuid, text, uuid, timestamptz, timestamptz, uuid, integer, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Vendors — list + detail. Total purchases and outstanding come from the
-- expenses the placed POs created (the ONE finance source, spec §53).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_vendors(
  p_facility_id uuid, p_search text default null, p_status text default null,
  p_limit integer default 20, p_offset integer default 0
)
returns table (
  id uuid, name text, contact_person text, phone text, email text, status text,
  po_count bigint, total_purchases_minor bigint, outstanding_minor bigint, total_count bigint
)
language plpgsql stable as $$
begin
  if not has_permission(p_facility_id, 'VENDOR_VIEW') then
    raise exception 'You don''t have permission to view vendors.' using errcode = '42501';
  end if;

  return query
  with rows as (
    select v.id, v.name, v.contact_person, v.phone, v.email, v.status,
      (select count(*) from purchase_orders po where po.vendor_id = v.id and po.status <> 'DRAFT') as po_count,
      coalesce((select sum(e.amount_minor) from purchase_orders po
                join expenses e on e.id = po.expense_id and e.status = 'RECORDED'
                where po.vendor_id = v.id), 0) as total_purchases_minor,
      coalesce((select sum(e.amount_minor - e.amount_paid_minor) from purchase_orders po
                join expenses e on e.id = po.expense_id and e.status = 'RECORDED'
                where po.vendor_id = v.id), 0) as outstanding_minor
    from vendors v
    where v.facility_id = p_facility_id
      and (p_status is null or v.status = p_status)
      and (
        p_search is null or trim(p_search) = ''
        or v.name ilike '%' || trim(p_search) || '%'
        or coalesce(v.contact_person, '') ilike '%' || trim(p_search) || '%'
        or coalesce(v.email, '') ilike '%' || trim(p_search) || '%'
      )
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by r.name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_vendors(uuid, text, text, integer, integer) to authenticated;


create or replace function get_vendor(p_vendor_id uuid)
returns jsonb
language plpgsql stable as $$
declare v vendors; result jsonb;
begin
  select * into v from vendors where id = p_vendor_id;
  if v.id is null then raise exception 'Vendor not found.' using errcode = 'P0002'; end if;
  if not has_permission(v.facility_id, 'VENDOR_VIEW') then
    raise exception 'You don''t have permission to view vendors.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', v.id, 'facilityId', v.facility_id, 'name', v.name, 'contactPerson', v.contact_person,
    'phone', v.phone, 'email', v.email, 'address', v.address, 'gstNumber', v.gst_number,
    'panNumber', v.pan_number, 'notes', v.notes, 'status', v.status, 'createdAt', v.created_at,
    'summary', (
      select jsonb_build_object(
        'purchaseOrderCount', count(*) filter (where po.status <> 'DRAFT'),
        'totalPurchasesMinor', coalesce(sum(e.amount_minor), 0),
        'outstandingMinor', coalesce(sum(e.amount_minor - e.amount_paid_minor), 0),
        'itemsSupplied', (select count(distinct poi.item_id) from purchase_order_items poi
                          join purchase_orders p2 on p2.id = poi.purchase_order_id where p2.vendor_id = v.id)
      )
      from purchase_orders po
      left join expenses e on e.id = po.expense_id and e.status = 'RECORDED'
      where po.vendor_id = v.id
    ),
    'suppliedItems', coalesce((
      select jsonb_agg(distinct jsonb_build_object('itemId', i.id, 'name', i.name, 'sku', i.sku))
      from purchase_order_items poi
      join purchase_orders po on po.id = poi.purchase_order_id
      join inventory_items i on i.id = poi.item_id
      where po.vendor_id = v.id
    ), '[]'::jsonb),
    'purchaseHistory', coalesce((
      select jsonb_agg(jsonb_build_object(
        'poId', po.id, 'poNumber', po.po_number, 'orderDate', po.order_date,
        'totalMinor', po.total_minor, 'status', po.status,
        'paymentStatus', coalesce(e.payment_status, 'UNBILLED'),
        'lineCount', (select count(*) from purchase_order_items x where x.purchase_order_id = po.id)
      ) order by po.order_date desc)
      from purchase_orders po
      left join expenses e on e.id = po.expense_id
      where po.vendor_id = v.id and po.status <> 'DRAFT'
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'amountMinor', ep.amount_minor, 'paidOn', ep.paid_on, 'method', ep.payment_method,
        'poNumber', po.po_number
      ) order by ep.paid_on desc)
      from expense_payments ep
      join purchase_orders po on po.expense_id = ep.expense_id
      where po.vendor_id = v.id
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

grant execute on function get_vendor(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Purchase Orders — list + detail.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_purchase_orders(
  p_facility_id uuid,
  p_vendor_id uuid default null,
  p_status text default null,
  p_payment_status text default null,
  p_from date default null,
  p_to date default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid, po_number text, vendor_id uuid, vendor_name text, order_date date, expected_delivery date,
  status text, payment_status text, total_items bigint, total_quantity bigint, total_minor integer,
  outstanding_minor integer, total_count bigint
)
language plpgsql stable as $$
begin
  if not has_permission(p_facility_id, 'PURCHASE_VIEW') then
    raise exception 'You don''t have permission to view purchase orders.' using errcode = '42501';
  end if;

  return query
  with rows as (
    select po.id, po.po_number, po.vendor_id, v.name as vendor_name, po.order_date, po.expected_delivery,
           po.status, coalesce(e.payment_status, 'UNBILLED') as payment_status,
           (select count(*) from purchase_order_items x where x.purchase_order_id = po.id) as total_items,
           (select coalesce(sum(quantity_ordered), 0) from purchase_order_items x where x.purchase_order_id = po.id) as total_quantity,
           po.total_minor,
           coalesce(e.amount_minor - e.amount_paid_minor, 0) as outstanding_minor
    from purchase_orders po
    join vendors v on v.id = po.vendor_id
    left join expenses e on e.id = po.expense_id and e.status = 'RECORDED'
    where po.facility_id = p_facility_id
      and (p_vendor_id is null or po.vendor_id = p_vendor_id)
      and (p_status is null or po.status = p_status)
      and (p_payment_status is null or coalesce(e.payment_status, 'UNBILLED') = p_payment_status)
      and (p_from is null or po.order_date >= p_from)
      and (p_to is null or po.order_date <= p_to)
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by r.order_date desc, r.po_number desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_purchase_orders(uuid, uuid, text, text, date, date, integer, integer) to authenticated;


create or replace function get_purchase_order(p_po_id uuid)
returns jsonb
language plpgsql stable as $$
declare po purchase_orders; e expenses; result jsonb;
begin
  select * into po from purchase_orders where id = p_po_id;
  if po.id is null then raise exception 'Purchase order not found.' using errcode = 'P0002'; end if;
  if not has_permission(po.facility_id, 'PURCHASE_VIEW') then
    raise exception 'You don''t have permission to view purchase orders.' using errcode = '42501';
  end if;
  select * into e from expenses where id = po.expense_id;

  select jsonb_build_object(
    'id', po.id, 'facilityId', po.facility_id, 'poNumber', po.po_number, 'status', po.status,
    'paymentStatus', coalesce(e.payment_status, 'UNBILLED'),
    'orderDate', po.order_date, 'expectedDelivery', po.expected_delivery, 'reference', po.reference,
    'notes', po.notes, 'invoicePath', po.invoice_path, 'cancelReason', po.cancel_reason,
    'createdByName', (select full_name from profiles where id = po.created_by),
    'vendor', (select jsonb_build_object('id', v.id, 'name', v.name, 'contactPerson', v.contact_person, 'phone', v.phone)
               from vendors v where v.id = po.vendor_id),
    'financials', jsonb_build_object(
      'subtotalMinor', po.subtotal_minor, 'taxMinor', po.tax_minor, 'discountMinor', po.discount_minor,
      'totalMinor', po.total_minor,
      'paidMinor', coalesce(e.amount_paid_minor, 0),
      'outstandingMinor', coalesce(e.amount_minor - e.amount_paid_minor, 0)
    ),
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lineId', poi.id, 'itemId', i.id, 'itemName', i.name, 'sku', i.sku,
        'quantityOrdered', poi.quantity_ordered, 'quantityReceived', poi.quantity_received,
        'quantityPending', poi.quantity_ordered - poi.quantity_received,
        'unitCostMinor', poi.unit_cost_minor, 'taxMinor', poi.tax_minor, 'discountMinor', poi.discount_minor,
        'lineTotalMinor', poi.line_total_minor
      ) order by i.name)
      from purchase_order_items poi join inventory_items i on i.id = poi.item_id
      where poi.purchase_order_id = po.id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object('event', ev.event, 'summary', ev.summary, 'at', ev.created_at,
        'actorName', ap.full_name) order by ev.created_at desc)
      from inventory_events ev left join profiles ap on ap.id = ev.actor
      where ev.purchase_order_id = po.id
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

grant execute on function get_purchase_order(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- list_inventory_categories — with item count + value.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_inventory_categories(p_facility_id uuid)
returns table (
  id uuid, name text, description text, is_active boolean, sort_order integer,
  item_count bigint, inventory_value_minor bigint
)
language plpgsql stable as $$
begin
  if not has_permission(p_facility_id, 'INVENTORY_VIEW') then
    raise exception 'You don''t have permission to view inventory.' using errcode = '42501';
  end if;

  return query
  select c.id, c.name, c.description, c.is_active, c.sort_order,
    (select count(*) from inventory_items i where i.category_id = c.id) as item_count,
    coalesce((select sum(i.current_stock::bigint * i.unit_cost_minor) from inventory_items i
              where i.category_id = c.id and i.status = 'ACTIVE'), 0) as inventory_value_minor
  from inventory_categories c
  where c.facility_id = p_facility_id
  order by c.sort_order, c.name;
end;
$$;

grant execute on function list_inventory_categories(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Documents: item images + purchase-order invoices. Private bucket, folder
-- scoped by facility_id, readable by anyone with INVENTORY_VIEW (spec §37).
-- ─────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('inventory', 'inventory', false, 10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

drop policy if exists "inventory docs readable by inventory viewers" on storage.objects;
create policy "inventory docs readable by inventory viewers"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'inventory'
    and has_permission(((storage.foldername(name))[1])::uuid, 'INVENTORY_VIEW')
  );

drop policy if exists "inventory docs written by inventory editors" on storage.objects;
create policy "inventory docs written by inventory editors"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'inventory'
    and (
      has_permission(((storage.foldername(name))[1])::uuid, 'INVENTORY_CREATE_ITEM')
      or has_permission(((storage.foldername(name))[1])::uuid, 'INVENTORY_EDIT_ITEM')
      or has_permission(((storage.foldername(name))[1])::uuid, 'PURCHASE_CREATE')
    )
  );

drop policy if exists "inventory docs updated by inventory editors" on storage.objects;
create policy "inventory docs updated by inventory editors"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'inventory'
    and (
      has_permission(((storage.foldername(name))[1])::uuid, 'INVENTORY_EDIT_ITEM')
      or has_permission(((storage.foldername(name))[1])::uuid, 'PURCHASE_EDIT')
    )
  );
