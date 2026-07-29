-- GameAll Club Management: initial schema
-- Domains: memberships & billing, bookings/reservations, inventory/assets
-- Roles: admin, staff, member

create extension if not exists "pgcrypto";

create type role as enum ('admin', 'staff', 'member');
create type membership_status as enum ('active', 'expired', 'cancelled', 'pending');
create type payment_status as enum ('created', 'paid', 'failed', 'refunded');
create type booking_status as enum ('pending', 'confirmed', 'cancelled', 'completed');
create type inventory_txn_type as enum ('checkout', 'return', 'restock', 'damage');

-- ─────────────────────────────────────────────────────────────────────────
-- profiles (1:1 with auth.users)
-- ─────────────────────────────────────────────────────────────────────────
create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  avatar_url text,
  role role not null default 'member',
  phone text,
  created_at timestamptz not null default now()
);

-- SECURITY DEFINER: reads profiles.role bypassing RLS, so policies below can
-- call role() without recursing into the profiles table's own RLS check.
create function role() returns role
language sql security definer stable
set search_path = public
as $$
  select role from profiles where id = auth.uid();
$$;

create function handle_new_user() returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.email), 'member');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ─────────────────────────────────────────────────────────────────────────
-- membership_plans / memberships / payments
-- ─────────────────────────────────────────────────────────────────────────
create table membership_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price_inr integer not null check (price_inr >= 0),
  duration_days integer not null check (duration_days > 0),
  features text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table memberships (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references profiles (id) on delete cascade,
  plan_id uuid not null references membership_plans (id) on delete restrict,
  status membership_status not null default 'pending',
  start_date date not null,
  end_date date not null,
  auto_renew boolean not null default false,
  created_at timestamptz not null default now(),
  constraint memberships_dates_check check (end_date >= start_date)
);
create index memberships_member_id_idx on memberships (member_id);

create table payments (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references profiles (id) on delete cascade,
  membership_id uuid references memberships (id) on delete set null,
  razorpay_order_id text,
  razorpay_payment_id text,
  amount_inr integer not null check (amount_inr >= 0),
  status payment_status not null default 'created',
  created_at timestamptz not null default now()
);
create index payments_member_id_idx on payments (member_id);

-- ─────────────────────────────────────────────────────────────────────────
-- stations / bookings
-- ─────────────────────────────────────────────────────────────────────────
create table stations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text not null,
  hourly_rate_inr integer not null check (hourly_rate_inr >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table bookings (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references profiles (id) on delete cascade,
  station_id uuid not null references stations (id) on delete restrict,
  start_time timestamptz not null,
  end_time timestamptz not null,
  status booking_status not null default 'pending',
  created_by uuid not null references profiles (id),
  created_at timestamptz not null default now(),
  constraint bookings_time_check check (end_time > start_time)
);
create index bookings_member_id_idx on bookings (member_id);
create index bookings_station_id_time_idx on bookings (station_id, start_time);

-- ─────────────────────────────────────────────────────────────────────────
-- inventory_items / inventory_transactions
-- ─────────────────────────────────────────────────────────────────────────
create table inventory_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null,
  sku text not null unique,
  total_quantity integer not null default 0 check (total_quantity >= 0),
  available_quantity integer not null default 0 check (available_quantity >= 0),
  condition text not null default 'good',
  created_at timestamptz not null default now(),
  constraint inventory_available_lte_total check (available_quantity <= total_quantity)
);

create table inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references inventory_items (id) on delete cascade,
  member_id uuid references profiles (id) on delete set null,
  quantity integer not null check (quantity > 0),
  type inventory_txn_type not null,
  staff_id uuid not null references profiles (id),
  created_at timestamptz not null default now()
);
create index inventory_transactions_item_id_idx on inventory_transactions (item_id);

-- ─────────────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────────────
alter table profiles enable row level security;
alter table membership_plans enable row level security;
alter table memberships enable row level security;
alter table payments enable row level security;
alter table stations enable row level security;
alter table bookings enable row level security;
alter table inventory_items enable row level security;
alter table inventory_transactions enable row level security;

-- profiles: everyone reads their own row; staff/admin read all; only admin writes others' roles
create policy "profiles_select_own_or_staff" on profiles for select
  using (id = auth.uid() or role() in ('admin', 'staff'));
create policy "profiles_update_own" on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());
create policy "profiles_admin_all" on profiles for all
  using (role() = 'admin') with check (role() = 'admin');

-- membership_plans: everyone reads active plans; only admin manages
create policy "plans_select_active" on membership_plans for select
  using (is_active or role() in ('admin', 'staff'));
create policy "plans_admin_write" on membership_plans for insert with check (role() = 'admin');
create policy "plans_admin_update" on membership_plans for update using (role() = 'admin');
create policy "plans_admin_delete" on membership_plans for delete using (role() = 'admin');

-- memberships: member reads own; staff/admin read+write all
create policy "memberships_select_own_or_staff" on memberships for select
  using (member_id = auth.uid() or role() in ('admin', 'staff'));
create policy "memberships_staff_write" on memberships for insert with check (role() in ('admin', 'staff'));
create policy "memberships_staff_update" on memberships for update using (role() in ('admin', 'staff'));
create policy "memberships_admin_delete" on memberships for delete using (role() = 'admin');

-- payments: member reads own; staff/admin read all; only staff/admin write (server-side via Razorpay webhook)
create policy "payments_select_own_or_staff" on payments for select
  using (member_id = auth.uid() or role() in ('admin', 'staff'));
create policy "payments_staff_write" on payments for insert with check (role() in ('admin', 'staff'));
create policy "payments_staff_update" on payments for update using (role() in ('admin', 'staff'));

-- stations: everyone reads active; only admin manages
create policy "stations_select_active" on stations for select
  using (is_active or role() in ('admin', 'staff'));
create policy "stations_admin_write" on stations for insert with check (role() = 'admin');
create policy "stations_admin_update" on stations for update using (role() = 'admin');
create policy "stations_admin_delete" on stations for delete using (role() = 'admin');

-- bookings: member reads/creates own; staff/admin read+write all
create policy "bookings_select_own_or_staff" on bookings for select
  using (member_id = auth.uid() or role() in ('admin', 'staff'));
create policy "bookings_insert_own_or_staff" on bookings for insert
  with check (member_id = auth.uid() or role() in ('admin', 'staff'));
create policy "bookings_update_own_or_staff" on bookings for update
  using (member_id = auth.uid() or role() in ('admin', 'staff'));
create policy "bookings_admin_delete" on bookings for delete using (role() = 'admin');

-- inventory: staff/admin only (members don't self-serve inventory)
create policy "inventory_items_staff_all" on inventory_items for all
  using (role() in ('admin', 'staff')) with check (role() in ('admin', 'staff'));
create policy "inventory_txn_staff_all" on inventory_transactions for all
  using (role() in ('admin', 'staff')) with check (role() in ('admin', 'staff'));