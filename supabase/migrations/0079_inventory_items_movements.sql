-- ═══════════════════════════════════════════════════════════════════════════
-- Inventory items (supplies model) + the stock-movement ledger.
--
-- inventory_items gains the supplies fields. current_stock is the
-- authoritative balance and is only ever changed inside record_stock_movement
-- (row-locked, transactional). Every stock change writes an inventory_movements
-- row with balance_after — history is append-only (spec §36 / §9).
--
-- Valuation: WEIGHTED-AVERAGE cost. unit_cost_minor is recomputed on every
-- inbound movement that carries a cost:
--   new = (old_qty*old_cost + in_qty*in_cost) / (old_qty + in_qty)
-- Inventory value = current_stock * unit_cost_minor. Never revenue (spec §23).
-- ═══════════════════════════════════════════════════════════════════════════


alter table inventory_items
  add column if not exists category_id uuid references inventory_categories (id) on delete restrict,
  add column if not exists brand text,
  add column if not exists description text,
  add column if not exists unit text not null default 'piece',
  add column if not exists reorder_level integer not null default 0 check (reorder_level >= 0),
  add column if not exists default_unit_cost_minor integer check (default_unit_cost_minor is null or default_unit_cost_minor >= 0),
  -- The current weighted-average cost. Seeded from default_unit_cost_minor.
  add column if not exists unit_cost_minor integer not null default 0 check (unit_cost_minor >= 0),
  add column if not exists preferred_vendor_id uuid references vendors (id) on delete set null,
  add column if not exists image_path text,
  add column if not exists status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE')),
  -- The authoritative stock balance for the supplies model. The legacy
  -- total_quantity / available_quantity columns belong to the dormant
  -- equipment-lending concept and are not used here.
  add column if not exists current_stock integer not null default 0 check (current_stock >= 0),
  add column if not exists created_by uuid references profiles (id) on delete set null,
  add column if not exists updated_by uuid references profiles (id) on delete set null,
  add column if not exists updated_at timestamptz not null default now();

-- The legacy `category` text column stays NOT NULL; new items sync it from the
-- category row's name so old readers keep working.
alter table inventory_items alter column category set default '';

create index if not exists inventory_items_facility_status_idx on inventory_items (facility_id, status);
create index if not exists inventory_items_category_id_idx on inventory_items (category_id) where category_id is not null;
create index if not exists inventory_items_facility_name_idx on inventory_items (facility_id, lower(name));

drop trigger if exists inventory_items_set_updated_at on inventory_items;
create trigger inventory_items_set_updated_at
  before update on inventory_items
  for each row execute function set_updated_at();

-- Tighten the RLS: SELECT needs INVENTORY_VIEW; writes go through the RPCs.
drop policy if exists "inventory_items_staff_all" on inventory_items;
drop policy if exists "inventory_items_select" on inventory_items;
create policy "inventory_items_select" on inventory_items for select
  using (has_permission(facility_id, 'INVENTORY_VIEW'));


-- ─────────────────────────────────────────────────────────────────────────
-- inventory_movements — the append-only stock ledger. quantity is SIGNED:
-- the sign is the effect on current_stock (STOCK_IN/PURCHASE_RECEIVED/RETURN
-- positive, STOCK_OUT negative, ADJUSTMENT either). balance_after is the
-- stock level immediately after this movement.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists inventory_movements (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  item_id uuid not null references inventory_items (id) on delete restrict,
  movement_type text not null check (movement_type in ('STOCK_IN', 'STOCK_OUT', 'ADJUSTMENT', 'PURCHASE_RECEIVED', 'RETURN')),
  quantity integer not null check (quantity <> 0),
  balance_after integer not null check (balance_after >= 0),
  unit_cost_minor integer check (unit_cost_minor is null or unit_cost_minor >= 0),
  reason text,
  notes text,
  -- purchase_order | maintenance_ticket | manual | reversal
  reference_type text,
  reference_id uuid,
  performed_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists inventory_movements_facility_date_idx on inventory_movements (facility_id, created_at desc);
create index if not exists inventory_movements_item_idx on inventory_movements (item_id, created_at desc);
create index if not exists inventory_movements_reference_idx on inventory_movements (reference_type, reference_id) where reference_id is not null;

alter table inventory_movements enable row level security;

drop policy if exists "inventory_movements_select" on inventory_movements;
create policy "inventory_movements_select" on inventory_movements for select
  using (has_permission(facility_id, 'INVENTORY_VIEW'));
-- Insert only through record_stock_movement / receive_purchase_order.


-- ─────────────────────────────────────────────────────────────────────────
-- inventory_events — audit for item / category / vendor / PO lifecycle
-- (movements are self-auditing). Per-domain, matching maintenance / finance.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists inventory_events (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  event text not null,
  actor uuid references profiles (id) on delete set null,
  item_id uuid references inventory_items (id) on delete set null,
  vendor_id uuid references vendors (id) on delete set null,
  purchase_order_id uuid,
  summary text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists inventory_events_facility_idx on inventory_events (facility_id, created_at desc);

alter table inventory_events enable row level security;

drop policy if exists "inventory_events_select" on inventory_events;
create policy "inventory_events_select" on inventory_events for select
  using (has_permission(facility_id, 'INVENTORY_VIEW'));

create or replace function log_inventory_event(
  p_facility_id uuid,
  p_event text,
  p_summary text,
  p_item_id uuid default null,
  p_vendor_id uuid default null,
  p_purchase_order_id uuid default null,
  p_detail jsonb default '{}'::jsonb
) returns void
language sql
security definer
set search_path = public
as $$
  insert into inventory_events (facility_id, event, actor, item_id, vendor_id, purchase_order_id, summary, detail)
  values (p_facility_id, p_event, auth.uid(), p_item_id, p_vendor_id, p_purchase_order_id, p_summary, coalesce(p_detail, '{}'::jsonb));
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- create_inventory_category / update_inventory_category
-- ─────────────────────────────────────────────────────────────────────────
create or replace function create_inventory_category(
  p_facility_id uuid, p_name text, p_description text default null, p_sort_order integer default 0
) returns inventory_categories
language plpgsql security definer set search_path = public as $$
declare result inventory_categories;
begin
  if not has_permission(p_facility_id, 'INVENTORY_MANAGE_CATEGORIES') then
    raise exception 'You don''t have permission to manage categories.' using errcode = '42501';
  end if;
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'A category needs a name.' using errcode = '23514';
  end if;
  insert into inventory_categories (facility_id, name, description, sort_order, created_by)
  values (p_facility_id, trim(p_name), nullif(trim(coalesce(p_description, '')), ''), coalesce(p_sort_order, 0), auth.uid())
  returning * into result;
  perform log_inventory_event(p_facility_id, 'CATEGORY_CREATED', 'Category created: ' || trim(p_name));
  return result;
exception when unique_violation then
  raise exception 'A category with this name already exists.' using errcode = '23505';
end;
$$;

grant execute on function create_inventory_category(uuid, text, text, integer) to authenticated;


create or replace function update_inventory_category(
  p_category_id uuid, p_name text default null, p_description text default null,
  p_is_active boolean default null, p_sort_order integer default null
) returns inventory_categories
language plpgsql security definer set search_path = public as $$
declare result inventory_categories;
begin
  select * into result from inventory_categories where id = p_category_id;
  if result.id is null then raise exception 'Category not found.' using errcode = 'P0002'; end if;
  if not has_permission(result.facility_id, 'INVENTORY_MANAGE_CATEGORIES') then
    raise exception 'You don''t have permission to manage categories.' using errcode = '42501';
  end if;
  update inventory_categories set
    name = coalesce(nullif(trim(coalesce(p_name, '')), ''), name),
    description = coalesce(p_description, description),
    is_active = coalesce(p_is_active, is_active),
    sort_order = coalesce(p_sort_order, sort_order)
  where id = p_category_id returning * into result;
  perform log_inventory_event(result.facility_id, 'CATEGORY_UPDATED', 'Category updated: ' || result.name);
  return result;
end;
$$;

grant execute on function update_inventory_category(uuid, text, text, boolean, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- create_inventory_item / update_inventory_item — SKU uniqueness enforced by
-- the table constraint (spec §3: never trust a client check).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function create_inventory_item(
  p_facility_id uuid,
  p_name text,
  p_sku text,
  p_category_id uuid,
  p_unit text default 'piece',
  p_reorder_level integer default 0,
  p_brand text default null,
  p_description text default null,
  p_default_unit_cost_minor integer default null,
  p_preferred_vendor_id uuid default null,
  p_image_path text default null,
  p_opening_stock integer default 0
) returns inventory_items
language plpgsql security definer set search_path = public as $$
declare
  result inventory_items;
  cat inventory_categories;
begin
  if not has_permission(p_facility_id, 'INVENTORY_CREATE_ITEM') then
    raise exception 'You don''t have permission to add items.' using errcode = '42501';
  end if;
  if trim(coalesce(p_name, '')) = '' then raise exception 'An item needs a name.' using errcode = '23514'; end if;
  if trim(coalesce(p_sku, '')) = '' then raise exception 'An item needs a SKU.' using errcode = '23514'; end if;
  if coalesce(p_reorder_level, 0) < 0 then raise exception 'Reorder level cannot be negative.' using errcode = '23514'; end if;
  if coalesce(p_opening_stock, 0) < 0 then raise exception 'Opening stock cannot be negative.' using errcode = '23514'; end if;

  select * into cat from inventory_categories where id = p_category_id and facility_id = p_facility_id;
  if cat.id is null then raise exception 'Choose a valid category.' using errcode = '23503'; end if;
  if not cat.is_active then raise exception 'That category is inactive.' using errcode = '23514'; end if;

  insert into inventory_items (
    facility_id, name, sku, category, category_id, unit, reorder_level, brand, description,
    default_unit_cost_minor, unit_cost_minor, preferred_vendor_id, image_path,
    current_stock, created_by, updated_by
  ) values (
    p_facility_id, trim(p_name), upper(trim(p_sku)), cat.name, cat.id,
    coalesce(nullif(trim(coalesce(p_unit, '')), ''), 'piece'), coalesce(p_reorder_level, 0),
    nullif(trim(coalesce(p_brand, '')), ''), nullif(trim(coalesce(p_description, '')), ''),
    p_default_unit_cost_minor, coalesce(p_default_unit_cost_minor, 0), p_preferred_vendor_id,
    nullif(trim(coalesce(p_image_path, '')), ''),
    coalesce(p_opening_stock, 0), auth.uid(), auth.uid()
  )
  returning * into result;

  -- Opening stock is its own movement so the ledger explains the balance.
  if coalesce(p_opening_stock, 0) > 0 then
    insert into inventory_movements (facility_id, item_id, movement_type, quantity, balance_after, unit_cost_minor, reason, reference_type, performed_by)
    values (p_facility_id, result.id, 'STOCK_IN', p_opening_stock, p_opening_stock, p_default_unit_cost_minor, 'Opening stock', 'manual', auth.uid());
  end if;

  perform log_inventory_event(p_facility_id, 'ITEM_CREATED', 'Item created: ' || trim(p_name), result.id);
  return result;
exception when unique_violation then
  raise exception 'An item with this SKU already exists in this facility.' using errcode = '23505';
end;
$$;

grant execute on function create_inventory_item(uuid, text, text, uuid, text, integer, text, text, integer, uuid, text, integer) to authenticated;


create or replace function update_inventory_item(
  p_item_id uuid,
  p_name text default null,
  p_category_id uuid default null,
  p_unit text default null,
  p_reorder_level integer default null,
  p_brand text default null,
  p_description text default null,
  p_default_unit_cost_minor integer default null,
  p_preferred_vendor_id uuid default null,
  p_image_path text default null,
  p_status text default null
) returns inventory_items
language plpgsql security definer set search_path = public as $$
declare
  result inventory_items;
  cat inventory_categories;
begin
  select * into result from inventory_items where id = p_item_id;
  if result.id is null then raise exception 'Item not found.' using errcode = 'P0002'; end if;
  if not has_permission(result.facility_id, 'INVENTORY_EDIT_ITEM') then
    raise exception 'You don''t have permission to edit items.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('ACTIVE', 'INACTIVE') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  if p_category_id is not null then
    select * into cat from inventory_categories where id = p_category_id and facility_id = result.facility_id;
    if cat.id is null then raise exception 'Choose a valid category.' using errcode = '23503'; end if;
  end if;

  update inventory_items set
    name = coalesce(nullif(trim(coalesce(p_name, '')), ''), name),
    category_id = coalesce(p_category_id, category_id),
    category = coalesce(cat.name, category),
    unit = coalesce(nullif(trim(coalesce(p_unit, '')), ''), unit),
    reorder_level = coalesce(p_reorder_level, reorder_level),
    brand = coalesce(p_brand, brand),
    description = coalesce(p_description, description),
    default_unit_cost_minor = coalesce(p_default_unit_cost_minor, default_unit_cost_minor),
    preferred_vendor_id = coalesce(p_preferred_vendor_id, preferred_vendor_id),
    image_path = coalesce(nullif(trim(coalesce(p_image_path, '')), ''), image_path),
    status = coalesce(p_status, status),
    updated_by = auth.uid()
  where id = p_item_id returning * into result;

  perform log_inventory_event(result.facility_id,
    case when p_status = 'INACTIVE' then 'ITEM_DEACTIVATED' else 'ITEM_UPDATED' end,
    (case when p_status = 'INACTIVE' then 'Item deactivated: ' else 'Item updated: ' end) || result.name, result.id);
  return result;
end;
$$;

grant execute on function update_inventory_item(uuid, text, uuid, text, integer, text, text, integer, uuid, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- record_stock_movement — the one transactional path for a manual stock
-- change (spec §61). Locks the item row, revalidates the balance, updates
-- current_stock and the weighted-average cost, writes the ledger row.
--
-- p_quantity is SIGNED. The RPC enforces the sign matches the type and that
-- the resulting balance is never negative (spec §7 / §9 / §70).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function record_stock_movement(
  p_item_id uuid,
  p_movement_type text,
  p_quantity integer,
  p_reason text default null,
  p_notes text default null,
  p_unit_cost_minor integer default null,
  p_reference_type text default 'manual',
  p_reference_id uuid default null
) returns inventory_movements
language plpgsql
security definer
set search_path = public
as $$
declare
  item inventory_items;
  new_balance integer;
  new_cost integer;
  perm text;
  result inventory_movements;
begin
  if p_movement_type not in ('STOCK_IN', 'STOCK_OUT', 'ADJUSTMENT', 'RETURN') then
    raise exception 'Unknown movement type.' using errcode = '22023';
  end if;
  if p_quantity is null or p_quantity = 0 then
    raise exception 'Enter a quantity.' using errcode = '23514';
  end if;

  perm := case p_movement_type
    when 'STOCK_OUT' then 'INVENTORY_STOCK_OUT'
    when 'ADJUSTMENT' then 'INVENTORY_ADJUST'
    else 'INVENTORY_STOCK_IN'
  end;

  select * into item from inventory_items where id = p_item_id for update;
  if item.id is null then raise exception 'Item not found.' using errcode = 'P0002'; end if;
  if not has_permission(item.facility_id, perm) then
    raise exception 'You don''t have permission for this stock action.' using errcode = '42501';
  end if;
  if item.status <> 'ACTIVE' then
    raise exception 'This item is inactive.' using errcode = '23514';
  end if;

  -- Enforce the sign per type.
  if p_movement_type in ('STOCK_IN', 'RETURN') and p_quantity < 0 then
    raise exception 'A % adds stock — use a positive quantity.', p_movement_type using errcode = '23514';
  end if;
  if p_movement_type = 'STOCK_OUT' and p_quantity > 0 then
    p_quantity := -p_quantity; -- accept a positive "issue 5" and apply as -5
  end if;

  new_balance := item.current_stock + p_quantity;
  if new_balance < 0 then
    raise exception 'Only % unit(s) are currently available.', item.current_stock using errcode = '23514';
  end if;

  -- Weighted-average cost on inbound movements that carry a cost.
  new_cost := item.unit_cost_minor;
  if p_quantity > 0 and p_unit_cost_minor is not null and p_unit_cost_minor >= 0 then
    if item.current_stock + p_quantity > 0 then
      new_cost := ((item.current_stock * item.unit_cost_minor) + (p_quantity * p_unit_cost_minor))
                  / (item.current_stock + p_quantity);
    end if;
  end if;

  update inventory_items
    set current_stock = new_balance, unit_cost_minor = new_cost, updated_by = auth.uid()
    where id = p_item_id;

  insert into inventory_movements (
    facility_id, item_id, movement_type, quantity, balance_after, unit_cost_minor,
    reason, notes, reference_type, reference_id, performed_by
  ) values (
    item.facility_id, p_item_id, p_movement_type, p_quantity, new_balance, p_unit_cost_minor,
    nullif(trim(coalesce(p_reason, '')), ''), nullif(trim(coalesce(p_notes, '')), ''),
    nullif(trim(coalesce(p_reference_type, '')), ''), p_reference_id, auth.uid()
  )
  returning * into result;

  return result;
end;
$$;

grant execute on function record_stock_movement(uuid, text, integer, text, text, integer, text, uuid) to authenticated;
