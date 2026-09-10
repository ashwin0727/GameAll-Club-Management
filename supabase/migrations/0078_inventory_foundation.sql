-- ═══════════════════════════════════════════════════════════════════════════
-- Inventory & Vendors — the foundation: permissions, categories, vendors.
--
-- GameAll already has an `inventory_items` / `inventory_transactions` pair
-- from 0001, but they model *equipment lending* (a member borrows a racket:
-- available_quantity <= total_quantity) and have never been wired to any UI.
-- This module is *supplies / consumables / purchasing* — reorder levels,
-- unit cost, vendors, purchase orders, weighted-average valuation.
--
-- Rather than a second "items" table (spec §54 warns against that), 0079
-- extends inventory_items with the supplies fields and adds a proper
-- inventory_movements ledger; inventory_transactions is left dormant.
--
-- Authorization reuses has_permission (0074). Finance reuses create_expense /
-- record_expense_payment (0077) — a purchase is a normal expense with a
-- payment status, never a second ledger.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- Permissions (spec §32). Added to the catalog and granted to the three
-- system roles here — 0072's one-time "owner gets every key" seed does not
-- reach rows inserted later.
-- ─────────────────────────────────────────────────────────────────────────
insert into permissions (key, module, action, label, description, is_dangerous, sort_order) values
  ('INVENTORY_VIEW',              'Inventory & Vendors', 'VIEW',              'View inventory',            'See items, stock levels, movements and the overview.', false, 900),
  ('INVENTORY_CREATE_ITEM',       'Inventory & Vendors', 'CREATE_ITEM',       'Add items',                 'Create new inventory items.', false, 910),
  ('INVENTORY_EDIT_ITEM',        'Inventory & Vendors', 'EDIT_ITEM',         'Edit items',                'Change an item''s details or deactivate it.', false, 920),
  ('INVENTORY_STOCK_IN',         'Inventory & Vendors', 'STOCK_IN',          'Record stock in',           'Add stock (replenishment, returns, manual additions).', false, 930),
  ('INVENTORY_STOCK_OUT',        'Inventory & Vendors', 'STOCK_OUT',         'Record stock out',          'Issue or consume stock.', false, 940),
  ('INVENTORY_ADJUST',          'Inventory & Vendors', 'ADJUST',           'Adjust stock',              'Correct stock to a physical count. Every adjustment is recorded.', true, 950),
  ('INVENTORY_MANAGE_CATEGORIES','Inventory & Vendors', 'MANAGE_CATEGORIES','Manage categories',         'Create, edit and deactivate inventory categories.', false, 960),

  ('PURCHASE_VIEW',             'Inventory & Vendors', 'PURCHASE_VIEW',    'View purchase orders',      'See purchase orders and their line items.', false, 970),
  ('PURCHASE_CREATE',          'Inventory & Vendors', 'PURCHASE_CREATE',  'Create purchase orders',    'Raise a purchase order with a vendor.', false, 980),
  ('PURCHASE_EDIT',            'Inventory & Vendors', 'PURCHASE_EDIT',    'Edit purchase orders',      'Amend a draft or placed purchase order.', false, 990),
  ('PURCHASE_RECEIVE',         'Inventory & Vendors', 'PURCHASE_RECEIVE', 'Receive goods',             'Record goods received against a purchase order — this moves stock.', false, 1000),
  ('PURCHASE_CANCEL',          'Inventory & Vendors', 'PURCHASE_CANCEL',  'Cancel purchase orders',    'Cancel a purchase order that has not been received.', true, 1010),

  ('VENDOR_VIEW',              'Inventory & Vendors', 'VENDOR_VIEW',      'View vendors',              'See the vendor list and vendor details.', false, 1020),
  ('VENDOR_CREATE',           'Inventory & Vendors', 'VENDOR_CREATE',    'Add vendors',               'Add a new vendor / supplier.', false, 1030),
  ('VENDOR_EDIT',             'Inventory & Vendors', 'VENDOR_EDIT',      'Edit vendors',              'Edit a vendor or deactivate one.', false, 1040)
on conflict (key) do nothing;

-- Owner: everything.
insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000a1', key from permissions
where module = 'Inventory & Vendors'
on conflict do nothing;

-- Manager: full operational inventory + purchasing + vendor management.
insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000a2', key from permissions
where module = 'Inventory & Vendors'
on conflict do nothing;

-- Staff: view + the two everyday stock actions + view vendors/POs.
insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000a3', key
from (values ('INVENTORY_VIEW'), ('INVENTORY_STOCK_IN'), ('INVENTORY_STOCK_OUT'), ('PURCHASE_VIEW'), ('VENDOR_VIEW')) as p(key)
on conflict do nothing;

-- Templates: Maintenance Staff can view + issue stock; Finance Staff can see purchases.
insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000b3', key
from (values ('INVENTORY_VIEW'), ('INVENTORY_STOCK_OUT')) as p(key)
on conflict do nothing;
insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000b4', key
from (values ('PURCHASE_VIEW'), ('INVENTORY_VIEW')) as p(key)
on conflict do nothing;


-- ─────────────────────────────────────────────────────────────────────────
-- inventory_categories — a facility's own item groupings. A category
-- referenced by an item is deactivated, never deleted (spec §27).
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists inventory_categories (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  name text not null,
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists inventory_categories_facility_name_idx
  on inventory_categories (facility_id, lower(name));

alter table inventory_categories enable row level security;

drop policy if exists "inventory_categories_select" on inventory_categories;
create policy "inventory_categories_select" on inventory_categories for select
  using (has_permission(facility_id, 'INVENTORY_VIEW'));
-- Writes go through the RPCs in 0079 (gated on INVENTORY_MANAGE_CATEGORIES).

drop trigger if exists inventory_categories_set_updated_at on inventory_categories;
create trigger inventory_categories_set_updated_at
  before update on inventory_categories
  for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- vendors — suppliers a facility buys from. Deactivated, never deleted, once
-- referenced by a purchase order (spec §18 / §65).
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists vendors (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  gst_number text,
  pan_number text,
  notes text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE')),
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists vendors_facility_name_idx
  on vendors (facility_id, lower(name));
create index if not exists vendors_facility_status_idx on vendors (facility_id, status);

alter table vendors enable row level security;

drop policy if exists "vendors_select" on vendors;
create policy "vendors_select" on vendors for select
  using (has_permission(facility_id, 'VENDOR_VIEW'));

drop trigger if exists vendors_set_updated_at on vendors;
create trigger vendors_set_updated_at
  before update on vendors
  for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- create_vendor / update_vendor — server-validated, duplicate name rejected
-- within the facility, GST format checked when supplied.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function create_vendor(
  p_facility_id uuid,
  p_name text,
  p_contact_person text default null,
  p_phone text default null,
  p_email text default null,
  p_address text default null,
  p_gst_number text default null,
  p_pan_number text default null,
  p_notes text default null
) returns vendors
language plpgsql
security definer
set search_path = public
as $$
declare result vendors;
begin
  if not has_permission(p_facility_id, 'VENDOR_CREATE') then
    raise exception 'You don''t have permission to add vendors.' using errcode = '42501';
  end if;
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'A vendor needs a name.' using errcode = '23514';
  end if;
  if p_email is not null and trim(p_email) <> '' and p_email !~* '^[^\s@]+@[^\s@]+\.[^\s@]+$' then
    raise exception 'Enter a valid email address.' using errcode = '23514';
  end if;
  if p_gst_number is not null and trim(p_gst_number) <> ''
     and upper(trim(p_gst_number)) !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$' then
    raise exception 'That GST number is not in a valid format.' using errcode = '23514';
  end if;

  insert into vendors (facility_id, name, contact_person, phone, email, address, gst_number, pan_number, notes, created_by)
  values (
    p_facility_id, trim(p_name), nullif(trim(coalesce(p_contact_person, '')), ''),
    nullif(trim(coalesce(p_phone, '')), ''), nullif(lower(trim(coalesce(p_email, ''))), ''),
    nullif(trim(coalesce(p_address, '')), ''), nullif(upper(trim(coalesce(p_gst_number, ''))), ''),
    nullif(upper(trim(coalesce(p_pan_number, ''))), ''), nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
  )
  returning * into result;
  return result;
exception when unique_violation then
  raise exception 'A vendor with this name already exists.' using errcode = '23505';
end;
$$;

grant execute on function create_vendor(uuid, text, text, text, text, text, text, text, text) to authenticated;


create or replace function update_vendor(
  p_vendor_id uuid,
  p_name text default null,
  p_contact_person text default null,
  p_phone text default null,
  p_email text default null,
  p_address text default null,
  p_gst_number text default null,
  p_pan_number text default null,
  p_notes text default null,
  p_status text default null
) returns vendors
language plpgsql
security definer
set search_path = public
as $$
declare result vendors;
begin
  select * into result from vendors where id = p_vendor_id;
  if result.id is null then
    raise exception 'Vendor not found.' using errcode = 'P0002';
  end if;
  if not has_permission(result.facility_id, 'VENDOR_EDIT') then
    raise exception 'You don''t have permission to edit vendors.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('ACTIVE', 'INACTIVE') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  update vendors set
    name = coalesce(nullif(trim(coalesce(p_name, '')), ''), name),
    contact_person = coalesce(p_contact_person, contact_person),
    phone = coalesce(p_phone, phone),
    email = coalesce(nullif(lower(trim(coalesce(p_email, ''))), ''), email),
    address = coalesce(p_address, address),
    gst_number = coalesce(nullif(upper(trim(coalesce(p_gst_number, ''))), ''), gst_number),
    pan_number = coalesce(nullif(upper(trim(coalesce(p_pan_number, ''))), ''), pan_number),
    notes = coalesce(p_notes, notes),
    status = coalesce(p_status, status)
  where id = p_vendor_id
  returning * into result;
  return result;
end;
$$;

grant execute on function update_vendor(uuid, text, text, text, text, text, text, text, text, text) to authenticated;
