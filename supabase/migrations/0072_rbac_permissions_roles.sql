-- ═══════════════════════════════════════════════════════════════════════════
-- Staff / Roles / Permissions — the authorization layer.
--
-- GameAll already has authentication (auth.users → profiles) and a
-- facility-scoped role enum (facility_users.role = owner|manager|staff, with
-- the SECURITY DEFINER helpers is_facility_member / has_facility_role driving
-- ~40 RLS policies). What was missing is *granularity*: "a manager" was an
-- all-or-nothing bundle, there was no way to say "this person can take
-- payments but not issue refunds", and no custom roles.
--
-- This does NOT replace the enum. facility_users.role stays as the base tier
-- (owner is always full access; it anchors the last-owner protection). On top
-- of it:
--   * permissions  — the catalog. MODULE + ACTION. Seeded here; a future
--     module registers its own permissions in its own migration.
--   * roles        — the 3 system templates (facility_id null, is_system) plus
--     a facility's own custom roles. Editing a system role's permissions for
--     one facility copies it to a facility-scoped row (copy-on-write) so one
--     facility's changes never touch another's.
--   * role_permissions — which permission keys a role grants.
--
-- has_permission(facility, key) — added in 0074 — is the one check every
-- sensitive operation routes through.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- permissions: the catalog. Read-only from the client (a catalog, no
-- secrets); rows are only ever added by a migration.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists permissions (
  key text primary key,
  module text not null,
  action text not null,
  label text not null,
  description text,
  is_dangerous boolean not null default false,
  sort_order integer not null default 0
);

alter table permissions enable row level security;

drop policy if exists "permissions_select_authenticated" on permissions;
create policy "permissions_select_authenticated" on permissions for select
  using (auth.uid() is not null);

insert into permissions (key, module, action, label, description, is_dangerous, sort_order) values
  ('DASHBOARD_VIEW',           'Dashboard',      'VIEW',            'View dashboard',            'Access the facility dashboard and headline metrics.', false, 10),

  ('BOOKINGS_VIEW',            'Bookings',       'VIEW',            'View bookings',             'See the bookings calendar and booking details.', false, 100),
  ('BOOKINGS_CREATE',         'Bookings',       'CREATE',          'Create bookings',           'Create new court bookings.', false, 110),
  ('BOOKINGS_EDIT',           'Bookings',       'EDIT',            'Edit bookings',             'Reschedule or amend existing bookings.', false, 120),
  ('BOOKINGS_CANCEL',         'Bookings',       'CANCEL',          'Cancel bookings',           'Cancel a booking. Refunds are a separate permission.', true, 130),
  ('BOOKINGS_MANAGE_PAYMENTS','Bookings',       'MANAGE_PAYMENTS', 'Manage booking payments',   'Record and manage payments taken against a booking.', false, 140),
  ('BOOKINGS_VIEW_CUSTOMER',  'Bookings',       'VIEW_CUSTOMER',   'View customer details',     'See the customer / member contact details on a booking.', false, 150),

  ('COURTS_VIEW',             'Courts',         'VIEW',            'View courts',               'See the facility''s courts and their configuration.', false, 200),
  ('COURTS_CREATE',          'Courts',         'CREATE',          'Add courts',                'Add a new court to the facility.', false, 210),
  ('COURTS_EDIT',            'Courts',         'EDIT',            'Edit courts',               'Change a court''s name, sport, or pricing.', false, 220),
  ('COURTS_BLOCK',           'Courts',         'BLOCK',           'Block courts',              'Take a court offline outside the maintenance workflow.', true, 230),

  ('MEMBERSHIPS_VIEW',       'Memberships',    'VIEW',            'View memberships',          'See members, plans and membership sessions.', false, 300),
  ('MEMBERSHIPS_CREATE',     'Memberships',    'CREATE',          'Create memberships',        'Enrol a member on a plan.', false, 310),
  ('MEMBERSHIPS_EDIT',       'Memberships',    'EDIT',            'Edit memberships',          'Amend an existing membership.', false, 320),
  ('MEMBERSHIPS_CANCEL',     'Memberships',    'CANCEL',          'Cancel memberships',        'Cancel a member''s membership.', true, 330),

  ('GUEST_BOOKINGS_VIEW',    'Guest Bookings', 'VIEW',            'View guest bookings',       'See the guest bookings list and details.', false, 400),
  ('GUEST_BOOKINGS_CREATE',  'Guest Bookings', 'CREATE',          'Create guest bookings',     'Take a walk-in / guest booking.', false, 410),
  ('GUEST_BOOKINGS_EDIT',    'Guest Bookings', 'EDIT',            'Edit guest bookings',       'Amend an existing guest booking.', false, 420),
  ('GUEST_BOOKINGS_CANCEL',  'Guest Bookings', 'CANCEL',          'Cancel guest bookings',     'Cancel a guest booking.', true, 430),

  ('FINANCE_VIEW',           'Finance',        'VIEW',            'View finance',              'See the finance overview, transactions and pending payments.', false, 500),
  ('FINANCE_RECORD_PAYMENT', 'Finance',        'RECORD_PAYMENT',  'Record payments',           'Collect a payment against an obligation.', false, 510),
  ('FINANCE_REFUND',         'Finance',        'REFUND',          'Issue refunds',             'Users with this permission can issue refunds for facility payments.', true, 520),
  ('FINANCE_MANAGE_EXPENSES','Finance',        'MANAGE_EXPENSES', 'Manage expenses',           'Record, edit and void facility expenses.', false, 530),
  ('FINANCE_DAILY_CLOSING',  'Finance',        'DAILY_CLOSING',   'Run daily closing',         'Open and complete the end-of-day cash reconciliation.', false, 540),
  ('FINANCE_REOPEN_CLOSING', 'Finance',        'REOPEN_CLOSING',  'Reopen a closed day',       'Reopen a completed daily closing. Historical totals can change.', true, 550),
  ('FINANCE_VIEW_PNL',       'Finance',        'VIEW_PNL',        'View Profit & Loss',        'See the owner-level Profit & Loss statement.', false, 560),

  ('REPORTS_VIEW',           'Reports',        'VIEW',            'View reports',              'Access operational reports (bookings, utilisation, memberships).', false, 600),
  ('REPORTS_VIEW_FINANCIAL', 'Reports',        'VIEW_FINANCIAL',  'View financial reports',    'Access revenue and other reports containing financial data.', false, 610),

  ('MAINTENANCE_VIEW',       'Maintenance',    'VIEW',            'View maintenance',          'See maintenance tickets and the court schedule.', false, 700),
  ('MAINTENANCE_CREATE',     'Maintenance',    'CREATE',          'Report issues',             'Raise a maintenance ticket.', false, 710),
  ('MAINTENANCE_ASSIGN',     'Maintenance',    'ASSIGN',          'Assign maintenance',        'Assign a ticket to a person.', false, 720),
  ('MAINTENANCE_SCHEDULE',   'Maintenance',    'SCHEDULE',        'Schedule maintenance',      'Schedule a maintenance window.', false, 730),
  ('MAINTENANCE_BLOCK_COURT','Maintenance',    'BLOCK_COURT',     'Block courts for maintenance','Take a court offline for a maintenance window.', true, 740),
  ('MAINTENANCE_RESOLVE',    'Maintenance',    'RESOLVE',         'Resolve maintenance',       'Mark a maintenance ticket resolved.', false, 750),

  ('USERS_VIEW',             'Users & Roles',  'VIEW',            'View staff & roles',        'See the staff list, roles and access history.', false, 800),
  ('USERS_CREATE',           'Users & Roles',  'CREATE',          'Add staff',                 'Invite or add a staff member to the facility.', false, 810),
  ('USERS_EDIT',             'Users & Roles',  'EDIT',            'Edit staff',                'Edit a staff member''s profile and notes.', false, 820),
  ('USERS_MANAGE_ROLES',     'Users & Roles',  'MANAGE_ROLES',    'Manage roles & permissions','Create roles and change what any role or staff member can do.', true, 830),
  ('USERS_MANAGE_FACILITY_ACCESS','Users & Roles','MANAGE_FACILITY_ACCESS','Manage facility access','Grant or remove a staff member''s access to a facility.', true, 840),
  ('USERS_DEACTIVATE',       'Users & Roles',  'DEACTIVATE',      'Activate / deactivate staff','Deactivate or reactivate a staff member''s access.', true, 850)
on conflict (key) do nothing;


-- ─────────────────────────────────────────────────────────────────────────
-- roles: the 3 system templates (facility_id null) plus a facility's own
-- custom roles and its copy-on-write overrides of the templates.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists roles (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid references facilities (id) on delete cascade,
  -- 'owner' / 'manager' / 'staff' for a system template (or a facility's
  -- override of one); null for a custom role.
  key text,
  -- The base tier a role falls back to for the enum-driven policies that are
  -- not yet permission-gated. System rows: same as key. Custom rows: 'staff'.
  base_role facility_role,
  name text not null,
  description text,
  is_system boolean not null default false,
  -- A null-facility, non-assignable preset offered on the Create Role screen.
  is_template boolean not null default false,
  is_active boolean not null default true,
  -- Optimistic-lock token for concurrent edits (spec §44).
  version integer not null default 1,
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One system template per key; one facility override per (facility, key);
-- one custom role per (facility, name).
create unique index if not exists roles_system_key_idx
  on roles (key) where facility_id is null;
create unique index if not exists roles_facility_key_idx
  on roles (facility_id, key) where facility_id is not null and key is not null;
create unique index if not exists roles_facility_name_idx
  on roles (facility_id, lower(name)) where facility_id is not null;

alter table roles enable row level security;

-- System templates are visible to everyone signed in; a facility's roles to
-- its own staff.
drop policy if exists "roles_select" on roles;
create policy "roles_select" on roles for select
  using (facility_id is null or is_facility_member(facility_id));

-- All writes go through the SECURITY DEFINER RPCs in 0075, which enforce
-- USERS_MANAGE_ROLES and the self-protection rules. No direct-write policy.

drop trigger if exists roles_set_updated_at on roles;
create trigger roles_set_updated_at
  before update on roles
  for each row execute function set_updated_at();


create table if not exists role_permissions (
  role_id uuid not null references roles (id) on delete cascade,
  permission_key text not null references permissions (key) on delete cascade,
  primary key (role_id, permission_key)
);

alter table role_permissions enable row level security;

drop policy if exists "role_permissions_select" on role_permissions;
create policy "role_permissions_select" on role_permissions for select
  using (exists (
    select 1 from roles r
    where r.id = role_permissions.role_id
      and (r.facility_id is null or is_facility_member(r.facility_id))
  ));


-- ─────────────────────────────────────────────────────────────────────────
-- Seed the 3 system templates and their default permission sets.
--
-- The defaults are chosen so that today's behaviour is unchanged: the only
-- non-owner facility_users rows that exist were created by
-- create_facility_with_owner (owners), and owner short-circuits every check.
-- 'manager' keeps the broad access the enum policies currently grant it,
-- minus the two role-administration permissions (owner-level by default,
-- configurable per facility). 'staff' matches spec §11.
-- ─────────────────────────────────────────────────────────────────────────
insert into roles (id, facility_id, key, base_role, name, description, is_system)
values
  ('00000000-0000-0000-0000-0000000000a1', null, 'owner',   'owner',   'Owner',   'Full facility access and management.', true),
  ('00000000-0000-0000-0000-0000000000a2', null, 'manager', 'manager', 'Manager', 'Operational and financial management.', true),
  ('00000000-0000-0000-0000-0000000000a3', null, 'staff',   'staff',   'Staff',   'Day-to-day operational access.', true)
on conflict (id) do nothing;

-- Owner: every permission.
insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000a1', key from permissions
on conflict do nothing;

-- Manager: everything except the two role-administration permissions.
insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000a2', key from permissions
where key not in ('USERS_MANAGE_ROLES', 'USERS_MANAGE_FACILITY_ACCESS')
on conflict do nothing;

-- Staff: view + day-to-day operations, no finance management, no user admin.
insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000a3', key
from (values
  ('DASHBOARD_VIEW'), ('BOOKINGS_VIEW'), ('BOOKINGS_CREATE'), ('BOOKINGS_EDIT'),
  ('BOOKINGS_MANAGE_PAYMENTS'), ('BOOKINGS_VIEW_CUSTOMER'),
  ('COURTS_VIEW'), ('MEMBERSHIPS_VIEW'),
  ('GUEST_BOOKINGS_VIEW'), ('GUEST_BOOKINGS_CREATE'), ('GUEST_BOOKINGS_EDIT'),
  ('MAINTENANCE_VIEW'), ('MAINTENANCE_CREATE'),
  ('REPORTS_VIEW'),
  ('FINANCE_VIEW'), ('FINANCE_RECORD_PAYMENT')
) as p(key)
on conflict do nothing;


-- ─────────────────────────────────────────────────────────────────────────
-- Role templates — the "Pre-configured" presets on the Create Role screen.
-- Not assignable and not shown in the roles list; copied into a real
-- facility-scoped role by create_role(p_from_template_id => ...).
-- ─────────────────────────────────────────────────────────────────────────
insert into roles (id, facility_id, key, base_role, name, description, is_system, is_template)
values
  ('00000000-0000-0000-0000-0000000000b1', null, null, 'staff', 'Front Desk',        'Booking and customer management.',    false, true),
  ('00000000-0000-0000-0000-0000000000b2', null, null, 'staff', 'Coach',             'Coaching and training management.',    false, true),
  ('00000000-0000-0000-0000-0000000000b3', null, null, 'staff', 'Maintenance Staff', 'Maintenance and court operations.',    false, true),
  ('00000000-0000-0000-0000-0000000000b4', null, null, 'staff', 'Finance Staff',     'Finance and payment management.',      false, true)
on conflict (id) do nothing;

insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000b1', key from (values
  ('DASHBOARD_VIEW'), ('BOOKINGS_VIEW'), ('BOOKINGS_CREATE'), ('BOOKINGS_EDIT'),
  ('BOOKINGS_MANAGE_PAYMENTS'), ('BOOKINGS_VIEW_CUSTOMER'),
  ('GUEST_BOOKINGS_VIEW'), ('GUEST_BOOKINGS_CREATE'), ('GUEST_BOOKINGS_EDIT'),
  ('MEMBERSHIPS_VIEW'), ('COURTS_VIEW'), ('FINANCE_VIEW'), ('FINANCE_RECORD_PAYMENT')
) as p(key) on conflict do nothing;

insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000b2', key from (values
  ('DASHBOARD_VIEW'), ('BOOKINGS_VIEW'), ('BOOKINGS_CREATE'),
  ('MEMBERSHIPS_VIEW'), ('COURTS_VIEW'), ('GUEST_BOOKINGS_VIEW')
) as p(key) on conflict do nothing;

insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000b3', key from (values
  ('DASHBOARD_VIEW'), ('COURTS_VIEW'),
  ('MAINTENANCE_VIEW'), ('MAINTENANCE_CREATE'), ('MAINTENANCE_ASSIGN'),
  ('MAINTENANCE_SCHEDULE'), ('MAINTENANCE_BLOCK_COURT'), ('MAINTENANCE_RESOLVE')
) as p(key) on conflict do nothing;

insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000b4', key from (values
  ('DASHBOARD_VIEW'), ('FINANCE_VIEW'), ('FINANCE_RECORD_PAYMENT'),
  ('FINANCE_MANAGE_EXPENSES'), ('FINANCE_DAILY_CLOSING'), ('FINANCE_VIEW_PNL'),
  ('REPORTS_VIEW'), ('REPORTS_VIEW_FINANCIAL')
) as p(key) on conflict do nothing;
