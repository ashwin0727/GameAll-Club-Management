-- Page access matrix: every page gets None / View / Edit, per role.
--
-- The enforcement primitive stays the permission key (roles / role_permissions / has_permission), so every existing check
-- keeps working. This migration adds:
--   * new permission keys for pages that had none of their own,
--   * access_pages — the catalog the role editor and both apps read (which keys each level grants),
--   * a backfill so every role keeps the access it already had (exports excepted — they now need Edit),
--   * helpers: require_page_access() for the data RPCs, coaching_scope_own() / my_coach_id() for the coach scope.
-- See docs/superpowers/specs/2026-10-23-page-access-matrix-design.md.

-- ── 1. New permission keys ───────────────────────────────────────────────
insert into permissions (key, module, action, label, description, is_dangerous, sort_order) values
  ('TOURNAMENTS_VIEW', 'Main', 'VIEW', 'Tournaments View', 'Page access: Tournaments View.', false, 1000),
  ('GUEST_PLAYERS_VIEW', 'Guest Management', 'VIEW', 'Guest Players View', 'Page access: Guest Players View.', false, 1001),
  ('GUEST_PLAYERS_EDIT', 'Guest Management', 'EDIT', 'Guest Players Edit', 'Page access: Guest Players Edit.', false, 1002),
  ('MEMBERSHIP_SCHEDULE_VIEW', 'Memberships', 'VIEW', 'Membership Schedule View', 'Page access: Membership Schedule View.', false, 1003),
  ('MEMBERSHIP_PLANS_VIEW', 'Memberships', 'VIEW', 'Membership Plans View', 'Page access: Membership Plans View.', false, 1004),
  ('MEMBERSHIP_PLANS_EDIT', 'Memberships', 'EDIT', 'Membership Plans Edit', 'Page access: Membership Plans Edit.', false, 1005),
  ('MEMBERSHIP_SESSIONS_VIEW', 'Memberships', 'VIEW', 'Membership Sessions View', 'Page access: Membership Sessions View.', false, 1006),
  ('MEMBERSHIP_SESSIONS_EDIT', 'Memberships', 'EDIT', 'Membership Sessions Edit', 'Page access: Membership Sessions Edit.', false, 1007),
  ('COACHING_PROGRAMS_VIEW', 'Coaching', 'VIEW', 'Coaching Programs View', 'Page access: Coaching Programs View.', false, 1008),
  ('COACHING_STUDENTS_VIEW', 'Coaching', 'VIEW', 'Coaching Students View', 'Page access: Coaching Students View.', false, 1009),
  ('COACHING_SESSIONS_VIEW', 'Coaching', 'VIEW', 'Coaching Sessions View', 'Page access: Coaching Sessions View.', false, 1010),
  ('COACHING_SCHEDULE_VIEW', 'Coaching', 'VIEW', 'Coaching Schedule View', 'Page access: Coaching Schedule View.', false, 1011),
  ('COACHING_REPORTS_VIEW', 'Coaching', 'VIEW', 'Coaching Reports View', 'Page access: Coaching Reports View.', false, 1012),
  ('COACHING_REPORTS_EXPORT', 'Coaching', 'EXPORT', 'Coaching Reports Export', 'Page access: Coaching Reports Export.', false, 1013),
  ('MAINTENANCE_CATEGORIES_VIEW', 'Maintenance', 'VIEW', 'Maintenance Categories View', 'Page access: Maintenance Categories View.', false, 1014),
  ('MAINTENANCE_CATEGORIES_EDIT', 'Maintenance', 'EDIT', 'Maintenance Categories Edit', 'Page access: Maintenance Categories Edit.', false, 1015),
  ('FINANCE_OVERVIEW_EXPORT', 'Finance', 'EXPORT', 'Finance Overview Export', 'Page access: Finance Overview Export.', false, 1016),
  ('FINANCE_TRANSACTIONS_VIEW', 'Finance', 'VIEW', 'Finance Transactions View', 'Page access: Finance Transactions View.', false, 1017),
  ('FINANCE_TRANSACTIONS_EXPORT', 'Finance', 'EXPORT', 'Finance Transactions Export', 'Page access: Finance Transactions Export.', false, 1018),
  ('FINANCE_PAYMENTS_VIEW', 'Finance', 'VIEW', 'Finance Payments View', 'Page access: Finance Payments View.', false, 1019),
  ('FINANCE_EXPENSES_VIEW', 'Finance', 'VIEW', 'Finance Expenses View', 'Page access: Finance Expenses View.', false, 1020),
  ('FINANCE_CLOSING_VIEW', 'Finance', 'VIEW', 'Finance Closing View', 'Page access: Finance Closing View.', false, 1021),
  ('FINANCE_PNL_EXPORT', 'Finance', 'EXPORT', 'Finance Pnl Export', 'Page access: Finance Pnl Export.', false, 1022),
  ('REFUNDS_VIEW', 'Finance', 'VIEW', 'Refunds View', 'Page access: Refunds View.', false, 1023),
  ('REPORT_OVERVIEW_VIEW', 'Reports & Analytics', 'VIEW', 'Report Overview View', 'Page access: Report Overview View.', false, 1024),
  ('REPORT_OVERVIEW_EXPORT', 'Reports & Analytics', 'EXPORT', 'Report Overview Export', 'Page access: Report Overview Export.', false, 1025),
  ('REPORT_UTILIZATION_VIEW', 'Reports & Analytics', 'VIEW', 'Report Utilization View', 'Page access: Report Utilization View.', false, 1026),
  ('REPORT_UTILIZATION_EXPORT', 'Reports & Analytics', 'EXPORT', 'Report Utilization Export', 'Page access: Report Utilization Export.', false, 1027),
  ('REPORT_REVENUE_VIEW', 'Reports & Analytics', 'VIEW', 'Report Revenue View', 'Page access: Report Revenue View.', false, 1028),
  ('REPORT_REVENUE_EXPORT', 'Reports & Analytics', 'EXPORT', 'Report Revenue Export', 'Page access: Report Revenue Export.', false, 1029),
  ('REPORT_MEMBERSHIPS_VIEW', 'Reports & Analytics', 'VIEW', 'Report Memberships View', 'Page access: Report Memberships View.', false, 1030),
  ('REPORT_MEMBERSHIPS_EXPORT', 'Reports & Analytics', 'EXPORT', 'Report Memberships Export', 'Page access: Report Memberships Export.', false, 1031),
  ('REPORT_GUESTS_VIEW', 'Reports & Analytics', 'VIEW', 'Report Guests View', 'Page access: Report Guests View.', false, 1032),
  ('REPORT_GUESTS_EXPORT', 'Reports & Analytics', 'EXPORT', 'Report Guests Export', 'Page access: Report Guests Export.', false, 1033),
  ('ROLES_VIEW', 'Staff Management', 'VIEW', 'Roles View', 'Page access: Roles View.', false, 1034),
  ('ACCESS_HISTORY_VIEW', 'Staff Management', 'VIEW', 'Access History View', 'Page access: Access History View.', false, 1035),
  ('FACILITY_SETTINGS_VIEW', 'Facility', 'VIEW', 'Facility Settings View', 'Page access: Facility Settings View.', false, 1036),
  ('FACILITY_SETTINGS_EDIT', 'Facility', 'EDIT', 'Facility Settings Edit', 'Page access: Facility Settings Edit.', false, 1037),
  ('COACHING_OWN_ONLY', 'Coaching', 'RESTRICT', 'Limit coaching to own coach profile', 'Restriction: the person only sees their own coach profile, sessions, programs and students.', false, 1038)
on conflict (key) do nothing;

-- ── 2. The page catalog ──────────────────────────────────────────────────
create table if not exists access_pages (
  page_key     text primary key,
  group_label  text not null,
  label        text not null,
  description  text,
  can_edit     boolean not null default true,   -- false: the page only supports None / View
  edit_label   text,                            -- e.g. 'Edit (can export)' on report pages
  view_keys    text[] not null default '{}',    -- permission keys View grants
  edit_keys    text[] not null default '{}',    -- additional keys Edit grants
  extra_keys   text[] not null default '{}',    -- optional toggles shown under the page
  sort_order   integer not null default 0
);

alter table access_pages enable row level security;
drop policy if exists access_pages_select on access_pages;
create policy access_pages_select on access_pages for select using (auth.uid() is not null);

delete from access_pages;
insert into access_pages (page_key, group_label, label, description, can_edit, edit_label, view_keys, edit_keys, extra_keys, sort_order) values
  ('HOME', 'Main', 'Home', 'The home / today overview (called Today in the mobile app).', false, null, array['DASHBOARD_VIEW']::text[], '{}'::text[], '{}'::text[], 10),
  ('CALENDAR', 'Main', 'Calendar', 'Court calendar and bookings.', true, null, array['BOOKINGS_VIEW', 'COURTS_VIEW']::text[], array['BOOKINGS_CREATE', 'BOOKINGS_EDIT', 'BOOKINGS_CANCEL', 'BOOKINGS_MANAGE_PAYMENTS']::text[], array['BOOKINGS_VIEW_CUSTOMER']::text[], 20),
  ('TOURNAMENTS', 'Main', 'Tournaments', 'The tournament app page.', false, null, array['TOURNAMENTS_VIEW']::text[], '{}'::text[], '{}'::text[], 30),
  ('GUEST_BOOKINGS', 'Guest Management', 'Guest Booking', 'Ad-hoc guest bookings.', true, null, array['GUEST_BOOKINGS_VIEW']::text[], array['GUEST_BOOKINGS_CREATE', 'GUEST_BOOKINGS_EDIT', 'GUEST_BOOKINGS_CANCEL']::text[], '{}'::text[], 40),
  ('GUEST_PLAYERS', 'Guest Management', 'Guest Players', 'Guest player directory.', true, null, array['GUEST_PLAYERS_VIEW']::text[], array['GUEST_PLAYERS_EDIT']::text[], '{}'::text[], 50),
  ('MEMBERSHIP_DASHBOARD', 'Memberships', 'Dashboard & Members', 'Membership dashboard, members and memberships.', true, null, array['MEMBERSHIPS_VIEW']::text[], array['MEMBERSHIPS_CREATE', 'MEMBERSHIPS_EDIT', 'MEMBERSHIPS_CANCEL']::text[], '{}'::text[], 60),
  ('MEMBERSHIP_SCHEDULE', 'Memberships', 'Membership Schedule', 'The weekly membership schedule.', false, null, array['MEMBERSHIP_SCHEDULE_VIEW']::text[], '{}'::text[], '{}'::text[], 70),
  ('MEMBERSHIP_PLANS', 'Memberships', 'Membership Plans', 'Plans and pricing.', true, null, array['MEMBERSHIP_PLANS_VIEW']::text[], array['MEMBERSHIP_PLANS_EDIT']::text[], '{}'::text[], 80),
  ('MEMBERSHIP_SESSIONS', 'Memberships', 'Membership Sessions', 'Court sessions, allocation and guest releases.', true, null, array['MEMBERSHIP_SESSIONS_VIEW']::text[], array['MEMBERSHIP_SESSIONS_EDIT']::text[], '{}'::text[], 90),
  ('COACHING_OVERVIEW', 'Coaching', 'Coaching & Coaches', 'Coaching overview and the coaches.', true, null, array['COACHING_VIEW']::text[], array['COACHING_MANAGE_COACHES']::text[], '{}'::text[], 100),
  ('COACHING_PROGRAMS', 'Coaching', 'Programs', 'Coaching programs and batches.', true, null, array['COACHING_PROGRAMS_VIEW']::text[], array['COACHING_MANAGE_PROGRAMS', 'COACHING_MANAGE_PRICING']::text[], '{}'::text[], 110),
  ('COACHING_STUDENTS', 'Coaching', 'Students', 'Students, enrollments and progress.', true, null, array['COACHING_STUDENTS_VIEW', 'COACHING_VIEW_PROGRESS']::text[], array['COACHING_MANAGE_ENROLLMENTS', 'COACHING_MANAGE_PROGRESS']::text[], '{}'::text[], 120),
  ('COACHING_SESSIONS', 'Coaching', 'Sessions', 'Coaching session list.', true, null, array['COACHING_SESSIONS_VIEW']::text[], array['COACHING_CREATE_SESSION', 'COACHING_EDIT_SESSION', 'COACHING_CANCEL_SESSION']::text[], '{}'::text[], 130),
  ('COACHING_SCHEDULE', 'Coaching', 'Coaching Schedule', 'The coaching schedule calendar.', false, null, array['COACHING_SCHEDULE_VIEW']::text[], '{}'::text[], '{}'::text[], 140),
  ('COACHING_REPORTS', 'Coaching', 'Coaching Reports', 'Coaching reports.', true, 'Edit (can export)', array['COACHING_REPORTS_VIEW']::text[], array['COACHING_REPORTS_EXPORT']::text[], '{}'::text[], 150),
  ('MAINTENANCE', 'Maintenance', 'Maintenance & Tracker', 'Maintenance overview, tickets and court blocks.', true, null, array['MAINTENANCE_VIEW']::text[], array['MAINTENANCE_CREATE', 'MAINTENANCE_ASSIGN', 'MAINTENANCE_SCHEDULE', 'MAINTENANCE_BLOCK_COURT', 'MAINTENANCE_RESOLVE']::text[], '{}'::text[], 160),
  ('MAINTENANCE_CATEGORIES', 'Maintenance', 'Issue Categories', 'Maintenance issue categories.', true, null, array['MAINTENANCE_CATEGORIES_VIEW']::text[], array['MAINTENANCE_CATEGORIES_EDIT']::text[], '{}'::text[], 170),
  ('FINANCE_OVERVIEW', 'Finance', 'Finance Overview', 'Finance dashboard.', true, 'Edit (can export)', array['FINANCE_VIEW']::text[], array['FINANCE_OVERVIEW_EXPORT']::text[], '{}'::text[], 180),
  ('FINANCE_TRANSACTIONS', 'Finance', 'Transactions', 'Transaction ledger.', true, 'Edit (can export)', array['FINANCE_TRANSACTIONS_VIEW']::text[], array['FINANCE_TRANSACTIONS_EXPORT']::text[], '{}'::text[], 190),
  ('FINANCE_PAYMENTS', 'Finance', 'Payments', 'Pending payments and collections.', true, null, array['FINANCE_PAYMENTS_VIEW']::text[], array['FINANCE_RECORD_PAYMENT']::text[], '{}'::text[], 200),
  ('FINANCE_EXPENSES', 'Finance', 'Expenses', 'Expenses and vendor payments.', true, null, array['FINANCE_EXPENSES_VIEW']::text[], array['FINANCE_MANAGE_EXPENSES']::text[], '{}'::text[], 210),
  ('FINANCE_DAILY_CLOSING', 'Finance', 'Daily Closing', 'End-of-day closing.', true, null, array['FINANCE_CLOSING_VIEW']::text[], array['FINANCE_DAILY_CLOSING']::text[], array['FINANCE_REOPEN_CLOSING']::text[], 220),
  ('FINANCE_PNL', 'Finance', 'Profit & Loss', 'Profit and loss statement.', true, 'Edit (can export)', array['FINANCE_VIEW_PNL']::text[], array['FINANCE_PNL_EXPORT']::text[], '{}'::text[], 230),
  ('REFUNDS', 'Finance', 'Refunds', 'Refund requests and history.', true, null, array['REFUNDS_VIEW']::text[], array['FINANCE_REFUND']::text[], '{}'::text[], 240),
  ('REPORT_OVERVIEW', 'Reports & Analytics', 'Reports Overview', 'Analytics overview.', true, 'Edit (can export)', array['REPORT_OVERVIEW_VIEW', 'REPORTS_VIEW']::text[], array['REPORT_OVERVIEW_EXPORT']::text[], '{}'::text[], 250),
  ('REPORT_COURT_UTILIZATION', 'Reports & Analytics', 'Court Utilization', 'Court utilization report.', true, 'Edit (can export)', array['REPORT_UTILIZATION_VIEW']::text[], array['REPORT_UTILIZATION_EXPORT']::text[], '{}'::text[], 260),
  ('REPORT_REVENUE', 'Reports & Analytics', 'Revenue Report', 'Revenue report.', true, 'Edit (can export)', array['REPORT_REVENUE_VIEW', 'REPORTS_VIEW_FINANCIAL']::text[], array['REPORT_REVENUE_EXPORT']::text[], '{}'::text[], 270),
  ('REPORT_MEMBERSHIPS', 'Reports & Analytics', 'Memberships Report', 'Membership report.', true, 'Edit (can export)', array['REPORT_MEMBERSHIPS_VIEW']::text[], array['REPORT_MEMBERSHIPS_EXPORT']::text[], '{}'::text[], 280),
  ('REPORT_GUEST_BOOKINGS', 'Reports & Analytics', 'Guest Bookings Report', 'Guest booking report.', true, 'Edit (can export)', array['REPORT_GUESTS_VIEW']::text[], array['REPORT_GUESTS_EXPORT']::text[], '{}'::text[], 290),
  ('STAFF', 'Staff Management', 'Staff', 'Staff members.', true, null, array['USERS_VIEW']::text[], array['USERS_CREATE', 'USERS_EDIT', 'USERS_DEACTIVATE']::text[], array['USERS_MANAGE_FACILITY_ACCESS']::text[], 300),
  ('ROLES', 'Staff Management', 'Roles & Permissions', 'Roles and what they can access.', true, null, array['ROLES_VIEW']::text[], array['USERS_MANAGE_ROLES']::text[], '{}'::text[], 310),
  ('ACCESS_HISTORY', 'Staff Management', 'Access History', 'Security and access log.', false, null, array['ACCESS_HISTORY_VIEW']::text[], '{}'::text[], '{}'::text[], 320),
  ('FACILITY_SETTINGS', 'Facility', 'Facility Settings', 'Facility details, sports & courts, operating hours, pricing and payment methods.', true, null, array['FACILITY_SETTINGS_VIEW']::text[], array['FACILITY_SETTINGS_EDIT', 'COURTS_CREATE', 'COURTS_EDIT', 'COURTS_BLOCK']::text[], '{}'::text[], 330);

create or replace function list_access_pages()
returns table (
  page_key text, group_label text, label text, description text, can_edit boolean, edit_label text,
  view_keys text[], edit_keys text[], extra_keys text[], sort_order integer
)
language sql stable security definer set search_path = public
as $$
  select page_key, group_label, label, description, can_edit, edit_label, view_keys, edit_keys, extra_keys, sort_order
  from access_pages order by sort_order;
$$;
grant execute on function list_access_pages() to authenticated;

-- ── 3. Backfill: existing roles keep the access they had ─────────────────
insert into role_permissions (role_id, permission_key)
select distinct rp.role_id, b.new_key
from (values
  ('TOURNAMENTS_VIEW', array['DASHBOARD_VIEW']::text[]),
  ('GUEST_PLAYERS_VIEW', array['GUEST_BOOKINGS_VIEW']::text[]),
  ('GUEST_PLAYERS_EDIT', array['GUEST_BOOKINGS_EDIT']::text[]),
  ('MEMBERSHIP_SCHEDULE_VIEW', array['MEMBERSHIPS_VIEW']::text[]),
  ('MEMBERSHIP_PLANS_VIEW', array['MEMBERSHIPS_VIEW']::text[]),
  ('MEMBERSHIP_PLANS_EDIT', array['MEMBERSHIPS_EDIT']::text[]),
  ('MEMBERSHIP_SESSIONS_VIEW', array['MEMBERSHIPS_VIEW']::text[]),
  ('MEMBERSHIP_SESSIONS_EDIT', array['MEMBERSHIPS_EDIT']::text[]),
  ('COACHING_PROGRAMS_VIEW', array['COACHING_VIEW']::text[]),
  ('COACHING_STUDENTS_VIEW', array['COACHING_VIEW']::text[]),
  ('COACHING_SESSIONS_VIEW', array['COACHING_VIEW']::text[]),
  ('COACHING_SCHEDULE_VIEW', array['COACHING_VIEW']::text[]),
  ('COACHING_REPORTS_VIEW', array['COACHING_VIEW']::text[]),
  ('MAINTENANCE_CATEGORIES_VIEW', array['MAINTENANCE_VIEW']::text[]),
  ('MAINTENANCE_CATEGORIES_EDIT', array['MAINTENANCE_CREATE']::text[]),
  ('FINANCE_TRANSACTIONS_VIEW', array['FINANCE_VIEW']::text[]),
  ('FINANCE_PAYMENTS_VIEW', array['FINANCE_VIEW']::text[]),
  ('FINANCE_EXPENSES_VIEW', array['FINANCE_VIEW']::text[]),
  ('FINANCE_CLOSING_VIEW', array['FINANCE_VIEW']::text[]),
  ('REFUNDS_VIEW', array['FINANCE_VIEW']::text[]),
  ('REPORT_OVERVIEW_VIEW', array['REPORTS_VIEW']::text[]),
  ('REPORT_UTILIZATION_VIEW', array['REPORTS_VIEW']::text[]),
  ('REPORT_REVENUE_VIEW', array['REPORTS_VIEW_FINANCIAL']::text[]),
  ('REPORT_MEMBERSHIPS_VIEW', array['REPORTS_VIEW']::text[]),
  ('REPORT_GUESTS_VIEW', array['REPORTS_VIEW']::text[]),
  ('ROLES_VIEW', array['USERS_VIEW']::text[]),
  ('ACCESS_HISTORY_VIEW', array['USERS_VIEW']::text[]),
  ('FACILITY_SETTINGS_VIEW', array['COURTS_VIEW']::text[]),
  ('FACILITY_SETTINGS_EDIT', array['COURTS_EDIT']::text[])
) as b(new_key, from_keys)
join role_permissions rp on rp.permission_key = any (b.from_keys)
where exists (select 1 from permissions p where p.key = b.new_key)
on conflict do nothing;

-- ── 4. Guards ────────────────────────────────────────────────────────────
-- Raises 42501 unless the caller holds the permission key for the facility. Edge functions / internal jobs running as
-- the service role (no end user) are exempt — they enforce their own rules.
create or replace function require_page_access(p_facility uuid, p_permission text)
returns void
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    return; -- service role / internal call; anon callers are already blocked by function grants
  end if;
  if not has_permission(p_facility, p_permission) then
    raise exception 'You don''t have access to this page.' using errcode = '42501';
  end if;
end;
$$;
grant execute on function require_page_access(uuid, text) to authenticated;

-- Coach scope. True for a NON-owner whose role carries COACHING_OWN_ONLY: they may only see their own coach data.
create or replace function coaching_scope_own(p_facility uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from facility_users fu
    where fu.facility_id = p_facility and fu.user_id = auth.uid() and fu.status = 'ACTIVE' and fu.role <> 'owner'
      and exists (
        select 1 from role_permissions rp
        where rp.role_id = effective_role_id(p_facility, auth.uid()) and rp.permission_key = 'COACHING_OWN_ONLY'
      )
  );
$$;
grant execute on function coaching_scope_own(uuid) to authenticated;

-- The signed-in user's own coach record at this facility (null when they are not a coach).
create or replace function my_coach_id(p_facility uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select c.id from coaches c where c.facility_id = p_facility and c.user_id = auth.uid() limit 1;
$$;
grant execute on function my_coach_id(uuid) to authenticated;
