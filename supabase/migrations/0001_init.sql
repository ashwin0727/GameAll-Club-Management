-- ═══════════════════════════════════════════════════════════════════════════
-- Turf & Sports Facility Management — initial schema
--
-- Tenancy model: a facility is the root of everything operational.
--
--   auth.users → profiles → facility_users → facilities
--                                              ├── facility_sports → sports
--                                              │        └── courts
--                                              ├── membership_plans → memberships → payments
--                                              ├── bookings (court × time)
--                                              └── inventory_items → inventory_transactions
--
-- Every operational row carries facility_id so RLS can answer "may this user
-- see this row?" with a single membership lookup, and so a query never has to
-- join three levels up to find its tenant.
-- ═══════════════════════════════════════════════════════════════════════════

create extension if not exists "pgcrypto";
-- btree_gist lets the bookings exclusion constraint mix uuid equality with
-- tstzrange overlap in one index.
create extension if not exists "btree_gist";

-- ─────────────────────────────────────────────────────────────────────────
-- Enums
-- ─────────────────────────────────────────────────────────────────────────
create type role as enum ('admin', 'staff', 'member');
create type facility_role as enum ('owner', 'manager', 'staff');
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
  email text not null,
  avatar_url text,
  role role not null default 'member',
  phone text,
  -- Drives the post-login redirect: false → facility setup, true → dashboard.
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index profiles_email_idx on profiles (lower(email));

-- SECURITY DEFINER: reads profiles.role bypassing RLS, so policies below can
-- call role() without recursing into the profiles table's own RLS check.
create function role() returns role
language sql security definer stable
set search_path = public
as $$
  select role from profiles where id = auth.uid();
$$;

-- Signup metadata → profile row. `account_type = 'owner'` is what the web
-- signup form sends; anything else lands as a plain member.
create function handle_new_user() returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), new.email),
    new.email,
    case when new.raw_user_meta_data ->> 'account_type' = 'owner' then 'admin'::role
         else 'member'::role end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- Keep profiles.email in step when a user changes their address through
-- Supabase Auth (the change only lands once the new address is confirmed).
create function handle_user_email_change() returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.email is distinct from old.email then
    update public.profiles set email = new.email where id = new.id;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function handle_user_email_change();

-- ─────────────────────────────────────────────────────────────────────────
-- facilities / facility_users
-- ─────────────────────────────────────────────────────────────────────────
create table facilities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  owner_id uuid not null references profiles (id) on delete restrict,
  city text,
  address text,
  timezone text not null default 'Asia/Kolkata',
  currency text not null default 'INR',
  created_at timestamptz not null default now()
);
create index facilities_owner_id_idx on facilities (owner_id);

create table facility_users (
  facility_id uuid not null references facilities (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  role facility_role not null default 'staff',
  created_at timestamptz not null default now(),
  primary key (facility_id, user_id)
);
create index facility_users_user_id_idx on facility_users (user_id);

-- SECURITY DEFINER membership probes. Policies call these instead of
-- sub-selecting facility_users, which would recurse into that table's own RLS.
create function is_facility_member(target_facility uuid) returns boolean
language sql security definer stable
set search_path = public
as $$
  select exists (
    select 1 from facility_users
    where facility_id = target_facility and user_id = auth.uid()
  );
$$;

create function has_facility_role(target_facility uuid, allowed facility_role[])
returns boolean
language sql security definer stable
set search_path = public
as $$
  select exists (
    select 1 from facility_users
    where facility_id = target_facility
      and user_id = auth.uid()
      and role = any (allowed)
  );
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- sports / facility_sports / courts
-- ─────────────────────────────────────────────────────────────────────────
-- Platform reference data, shared by every facility. New sports are added here
-- once rather than per-tenant.
create table sports (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  is_active boolean not null default true,
  sort_order integer not null default 0
);

insert into sports (key, name, sort_order) values
  ('badminton',  'Badminton',  10),
  ('pickleball', 'Pickleball', 20),
  ('cricket',    'Cricket',    30),
  ('football',   'Football',   40),
  ('tennis',     'Tennis',     50);

create table facility_sports (
  facility_id uuid not null references facilities (id) on delete cascade,
  sport_id uuid not null references sports (id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (facility_id, sport_id)
);

create table courts (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  sport_id uuid not null references sports (id) on delete restrict,
  name text not null,
  surface text,
  hourly_rate_inr integer not null default 0 check (hourly_rate_inr >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (facility_id, name),
  -- A court may only use a sport the facility has actually enabled.
  foreign key (facility_id, sport_id)
    references facility_sports (facility_id, sport_id) on delete cascade
);
create index courts_facility_id_idx on courts (facility_id);

-- ─────────────────────────────────────────────────────────────────────────
-- membership_plans / memberships / payments
-- ─────────────────────────────────────────────────────────────────────────
create table membership_plans (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  name text not null,
  price_inr integer not null check (price_inr >= 0),
  duration_days integer not null check (duration_days > 0),
  features text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (facility_id, name)
);

create table memberships (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
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
create index memberships_facility_id_idx on memberships (facility_id);

create table payments (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  member_id uuid not null references profiles (id) on delete cascade,
  membership_id uuid references memberships (id) on delete set null,
  razorpay_order_id text,
  razorpay_payment_id text,
  amount_inr integer not null check (amount_inr >= 0),
  status payment_status not null default 'created',
  created_at timestamptz not null default now()
);
create index payments_member_id_idx on payments (member_id);
create index payments_facility_id_idx on payments (facility_id);

-- ─────────────────────────────────────────────────────────────────────────
-- bookings
-- ─────────────────────────────────────────────────────────────────────────
create table bookings (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  court_id uuid not null references courts (id) on delete restrict,
  member_id uuid not null references profiles (id) on delete cascade,
  start_time timestamptz not null,
  end_time timestamptz not null,
  status booking_status not null default 'pending',
  created_by uuid not null references profiles (id),
  created_at timestamptz not null default now(),
  constraint bookings_time_check check (end_time > start_time),
  -- Two live bookings can never overlap on the same court. Cancelled and
  -- completed rows are excluded so a freed slot can be rebooked.
  constraint bookings_no_overlap exclude using gist (
    court_id with =,
    tstzrange(start_time, end_time) with &&
  ) where (status in ('pending', 'confirmed'))
);
create index bookings_member_id_idx on bookings (member_id);
create index bookings_court_id_time_idx on bookings (court_id, start_time);
create index bookings_facility_id_time_idx on bookings (facility_id, start_time);

-- ─────────────────────────────────────────────────────────────────────────
-- inventory_items / inventory_transactions
-- ─────────────────────────────────────────────────────────────────────────
create table inventory_items (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  name text not null,
  category text not null,
  sku text not null,
  total_quantity integer not null default 0 check (total_quantity >= 0),
  available_quantity integer not null default 0 check (available_quantity >= 0),
  condition text not null default 'good',
  created_at timestamptz not null default now(),
  unique (facility_id, sku),
  constraint inventory_available_lte_total check (available_quantity <= total_quantity)
);

create table inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  item_id uuid not null references inventory_items (id) on delete cascade,
  member_id uuid references profiles (id) on delete set null,
  quantity integer not null check (quantity > 0),
  type inventory_txn_type not null,
  staff_id uuid not null references profiles (id),
  created_at timestamptz not null default now()
);
create index inventory_transactions_item_id_idx on inventory_transactions (item_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- Row level security
--
-- Shape of every operational policy: you may read a row if you belong to its
-- facility, and write it if you belong with a sufficient facility role.
-- ═══════════════════════════════════════════════════════════════════════════
alter table profiles enable row level security;
alter table facilities enable row level security;
alter table facility_users enable row level security;
alter table sports enable row level security;
alter table facility_sports enable row level security;
alter table courts enable row level security;
alter table membership_plans enable row level security;
alter table memberships enable row level security;
alter table payments enable row level security;
alter table bookings enable row level security;
alter table inventory_items enable row level security;
alter table inventory_transactions enable row level security;

-- profiles: own row always; platform staff/admin see all.
create policy "profiles_select_own_or_staff" on profiles for select
  using (id = auth.uid() or role() in ('admin', 'staff'));
create policy "profiles_update_own" on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());
create policy "profiles_admin_all" on profiles for all
  using (role() = 'admin') with check (role() = 'admin');

-- facilities: visible to their own staff; created by the signed-in owner;
-- only owners may rename or delete.
create policy "facilities_select_members" on facilities for select
  using (is_facility_member(id) or role() = 'admin');
create policy "facilities_insert_self_owned" on facilities for insert
  with check (owner_id = auth.uid());
create policy "facilities_update_owner" on facilities for update
  using (has_facility_role(id, array['owner']::facility_role[]))
  with check (has_facility_role(id, array['owner']::facility_role[]));
create policy "facilities_delete_owner" on facilities for delete
  using (owner_id = auth.uid());

-- facility_users: staff see their team; owners/managers manage it. The
-- self-insert branch is what lets a fresh owner claim the facility they just
-- created, before any membership row exists.
create policy "facility_users_select_members" on facility_users for select
  using (user_id = auth.uid() or is_facility_member(facility_id));
create policy "facility_users_insert_owner_or_self_claim" on facility_users for insert
  with check (
    has_facility_role(facility_id, array['owner', 'manager']::facility_role[])
    or (
      user_id = auth.uid()
      and exists (select 1 from facilities f where f.id = facility_id and f.owner_id = auth.uid())
    )
  );
create policy "facility_users_update_owner" on facility_users for update
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));
create policy "facility_users_delete_owner" on facility_users for delete
  using (has_facility_role(facility_id, array['owner']::facility_role[]));

-- sports: platform reference data — readable by any signed-in user, writable
-- only through the service role (no policy grants writes).
create policy "sports_select_all" on sports for select
  using (auth.uid() is not null);

create policy "facility_sports_select_members" on facility_sports for select
  using (is_facility_member(facility_id));
create policy "facility_sports_write_managers" on facility_sports for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

create policy "courts_select_members" on courts for select
  using (is_facility_member(facility_id));
create policy "courts_write_managers" on courts for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

create policy "plans_select_members" on membership_plans for select
  using (is_facility_member(facility_id));
create policy "plans_write_managers" on membership_plans for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

-- memberships: the member reads their own; facility staff read and manage all.
create policy "memberships_select_own_or_staff" on memberships for select
  using (member_id = auth.uid() or is_facility_member(facility_id));
create policy "memberships_write_staff" on memberships for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

-- payments: readable by the payer and facility staff. Writes come from the
-- Razorpay webhook via the service role, plus manual entry by staff.
create policy "payments_select_own_or_staff" on payments for select
  using (member_id = auth.uid() or is_facility_member(facility_id));
create policy "payments_write_staff" on payments for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

-- bookings: members see and create their own; facility staff manage all.
create policy "bookings_select_own_or_staff" on bookings for select
  using (member_id = auth.uid() or is_facility_member(facility_id));
create policy "bookings_insert_own_or_staff" on bookings for insert
  with check (
    member_id = auth.uid()
    or has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[])
  );
create policy "bookings_update_own_or_staff" on bookings for update
  using (
    member_id = auth.uid()
    or has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[])
  );
create policy "bookings_delete_managers" on bookings for delete
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

-- inventory: facility staff only — members do not self-serve equipment.
create policy "inventory_items_staff_all" on inventory_items for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));
create policy "inventory_txn_staff_all" on inventory_transactions for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));