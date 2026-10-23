// Generates supabase/migrations/0155_page_access_matrix.sql from one catalog definition.
const fs = require("fs");

// [key, group, label, description, canEdit, editLabel, view[], edit[], extras[]]
const PAGES = [
  // ── Main ──
  ["HOME", "Main", "Home", "The home / today overview (called Today in the mobile app).", false, null, ["DASHBOARD_VIEW"], [], []],
  ["CALENDAR", "Main", "Calendar", "Court calendar and bookings.", true, null,
    ["BOOKINGS_VIEW", "COURTS_VIEW"], ["BOOKINGS_CREATE", "BOOKINGS_EDIT", "BOOKINGS_CANCEL", "BOOKINGS_MANAGE_PAYMENTS"], ["BOOKINGS_VIEW_CUSTOMER"]],
  ["TOURNAMENTS", "Main", "Tournaments", "The tournament app page.", false, null, ["TOURNAMENTS_VIEW"], [], []],
  // ── Guest ──
  ["GUEST_BOOKINGS", "Guest Management", "Guest Booking", "Ad-hoc guest bookings.", true, null,
    ["GUEST_BOOKINGS_VIEW"], ["GUEST_BOOKINGS_CREATE", "GUEST_BOOKINGS_EDIT", "GUEST_BOOKINGS_CANCEL"], []],
  ["GUEST_PLAYERS", "Guest Management", "Guest Players", "Guest player directory.", true, null,
    ["GUEST_PLAYERS_VIEW"], ["GUEST_PLAYERS_EDIT"], []],
  // ── Memberships ──
  ["MEMBERSHIP_DASHBOARD", "Memberships", "Dashboard & Members", "Membership dashboard, members and memberships.", true, null,
    ["MEMBERSHIPS_VIEW"], ["MEMBERSHIPS_CREATE", "MEMBERSHIPS_EDIT", "MEMBERSHIPS_CANCEL"], []],
  ["MEMBERSHIP_SCHEDULE", "Memberships", "Membership Schedule", "The weekly membership schedule.", false, null,
    ["MEMBERSHIP_SCHEDULE_VIEW"], [], []],
  ["MEMBERSHIP_PLANS", "Memberships", "Membership Plans", "Plans and pricing.", true, null,
    ["MEMBERSHIP_PLANS_VIEW"], ["MEMBERSHIP_PLANS_EDIT"], []],
  ["MEMBERSHIP_SESSIONS", "Memberships", "Membership Sessions", "Court sessions, allocation and guest releases.", true, null,
    ["MEMBERSHIP_SESSIONS_VIEW"], ["MEMBERSHIP_SESSIONS_EDIT"], []],
  // ── Coaching ──
  ["COACHING_OVERVIEW", "Coaching", "Coaching & Coaches", "Coaching overview and the coaches.", true, null,
    ["COACHING_VIEW"], ["COACHING_MANAGE_COACHES"], []],
  ["COACHING_PROGRAMS", "Coaching", "Programs", "Coaching programs and batches.", true, null,
    ["COACHING_PROGRAMS_VIEW"], ["COACHING_MANAGE_PROGRAMS", "COACHING_MANAGE_PRICING"], []],
  ["COACHING_STUDENTS", "Coaching", "Students", "Students, enrollments and progress.", true, null,
    ["COACHING_STUDENTS_VIEW", "COACHING_VIEW_PROGRESS"], ["COACHING_MANAGE_ENROLLMENTS", "COACHING_MANAGE_PROGRESS"], []],
  ["COACHING_SESSIONS", "Coaching", "Sessions", "Coaching session list.", true, null,
    ["COACHING_SESSIONS_VIEW"], ["COACHING_CREATE_SESSION", "COACHING_EDIT_SESSION", "COACHING_CANCEL_SESSION"], []],
  ["COACHING_SCHEDULE", "Coaching", "Coaching Schedule", "The coaching schedule calendar.", false, null,
    ["COACHING_SCHEDULE_VIEW"], [], []],
  ["COACHING_REPORTS", "Coaching", "Coaching Reports", "Coaching reports.", true, "Edit (can export)",
    ["COACHING_REPORTS_VIEW"], ["COACHING_REPORTS_EXPORT"], []],
  // ── Maintenance ──
  ["MAINTENANCE", "Maintenance", "Maintenance & Tracker", "Maintenance overview, tickets and court blocks.", true, null,
    ["MAINTENANCE_VIEW"], ["MAINTENANCE_CREATE", "MAINTENANCE_ASSIGN", "MAINTENANCE_SCHEDULE", "MAINTENANCE_BLOCK_COURT", "MAINTENANCE_RESOLVE"], []],
  ["MAINTENANCE_CATEGORIES", "Maintenance", "Issue Categories", "Maintenance issue categories.", true, null,
    ["MAINTENANCE_CATEGORIES_VIEW"], ["MAINTENANCE_CATEGORIES_EDIT"], []],
  // ── Finance ──
  ["FINANCE_OVERVIEW", "Finance", "Finance Overview", "Finance dashboard.", true, "Edit (can export)",
    ["FINANCE_VIEW"], ["FINANCE_OVERVIEW_EXPORT"], []],
  ["FINANCE_TRANSACTIONS", "Finance", "Transactions", "Transaction ledger.", true, "Edit (can export)",
    ["FINANCE_TRANSACTIONS_VIEW"], ["FINANCE_TRANSACTIONS_EXPORT"], []],
  ["FINANCE_PAYMENTS", "Finance", "Payments", "Pending payments and collections.", true, null,
    ["FINANCE_PAYMENTS_VIEW"], ["FINANCE_RECORD_PAYMENT"], []],
  ["FINANCE_EXPENSES", "Finance", "Expenses", "Expenses and vendor payments.", true, null,
    ["FINANCE_EXPENSES_VIEW"], ["FINANCE_MANAGE_EXPENSES"], []],
  ["FINANCE_DAILY_CLOSING", "Finance", "Daily Closing", "End-of-day closing.", true, null,
    ["FINANCE_CLOSING_VIEW"], ["FINANCE_DAILY_CLOSING"], ["FINANCE_REOPEN_CLOSING"]],
  ["FINANCE_PNL", "Finance", "Profit & Loss", "Profit and loss statement.", true, "Edit (can export)",
    ["FINANCE_VIEW_PNL"], ["FINANCE_PNL_EXPORT"], []],
  ["REFUNDS", "Finance", "Refunds", "Refund requests and history.", true, null,
    ["REFUNDS_VIEW"], ["FINANCE_REFUND"], []],
  // ── Reports ──
  ["REPORT_OVERVIEW", "Reports & Analytics", "Reports Overview", "Analytics overview.", true, "Edit (can export)",
    ["REPORT_OVERVIEW_VIEW", "REPORTS_VIEW"], ["REPORT_OVERVIEW_EXPORT"], []],
  ["REPORT_COURT_UTILIZATION", "Reports & Analytics", "Court Utilization", "Court utilization report.", true, "Edit (can export)",
    ["REPORT_UTILIZATION_VIEW"], ["REPORT_UTILIZATION_EXPORT"], []],
  ["REPORT_REVENUE", "Reports & Analytics", "Revenue Report", "Revenue report.", true, "Edit (can export)",
    ["REPORT_REVENUE_VIEW", "REPORTS_VIEW_FINANCIAL"], ["REPORT_REVENUE_EXPORT"], []],
  ["REPORT_MEMBERSHIPS", "Reports & Analytics", "Memberships Report", "Membership report.", true, "Edit (can export)",
    ["REPORT_MEMBERSHIPS_VIEW"], ["REPORT_MEMBERSHIPS_EXPORT"], []],
  ["REPORT_GUEST_BOOKINGS", "Reports & Analytics", "Guest Bookings Report", "Guest booking report.", true, "Edit (can export)",
    ["REPORT_GUESTS_VIEW"], ["REPORT_GUESTS_EXPORT"], []],
  // ── Staff ──
  ["STAFF", "Staff Management", "Staff", "Staff members.", true, null,
    ["USERS_VIEW"], ["USERS_CREATE", "USERS_EDIT", "USERS_DEACTIVATE"], ["USERS_MANAGE_FACILITY_ACCESS"]],
  ["ROLES", "Staff Management", "Roles & Permissions", "Roles and what they can access.", true, null,
    ["ROLES_VIEW"], ["USERS_MANAGE_ROLES"], []],
  ["ACCESS_HISTORY", "Staff Management", "Access History", "Security and access log.", false, null,
    ["ACCESS_HISTORY_VIEW"], [], []],
  // ── Settings ──
  ["FACILITY_SETTINGS", "Facility", "Facility Settings", "Facility details, sports & courts, operating hours, pricing and payment methods.", true, null,
    ["FACILITY_SETTINGS_VIEW"], ["FACILITY_SETTINGS_EDIT", "COURTS_CREATE", "COURTS_EDIT", "COURTS_BLOCK"], []],
];

// Existing keys (already in `permissions`) — everything else referenced above is new.
const EXISTING = new Set(`DASHBOARD_VIEW BOOKINGS_VIEW BOOKINGS_CREATE BOOKINGS_EDIT BOOKINGS_CANCEL BOOKINGS_MANAGE_PAYMENTS BOOKINGS_VIEW_CUSTOMER
COURTS_VIEW COURTS_CREATE COURTS_EDIT COURTS_BLOCK MEMBERSHIPS_VIEW MEMBERSHIPS_CREATE MEMBERSHIPS_EDIT MEMBERSHIPS_CANCEL
GUEST_BOOKINGS_VIEW GUEST_BOOKINGS_CREATE GUEST_BOOKINGS_EDIT GUEST_BOOKINGS_CANCEL FINANCE_VIEW FINANCE_RECORD_PAYMENT FINANCE_REFUND
FINANCE_MANAGE_EXPENSES FINANCE_DAILY_CLOSING FINANCE_REOPEN_CLOSING FINANCE_VIEW_PNL REPORTS_VIEW REPORTS_VIEW_FINANCIAL
MAINTENANCE_VIEW MAINTENANCE_CREATE MAINTENANCE_ASSIGN MAINTENANCE_SCHEDULE MAINTENANCE_BLOCK_COURT MAINTENANCE_RESOLVE
USERS_VIEW USERS_CREATE USERS_EDIT USERS_DEACTIVATE USERS_MANAGE_ROLES USERS_MANAGE_FACILITY_ACCESS
COACHING_VIEW COACHING_MANAGE_COACHES COACHING_MANAGE_PROGRAMS COACHING_CREATE_SESSION COACHING_EDIT_SESSION COACHING_CANCEL_SESSION
COACHING_MANAGE_ENROLLMENTS COACHING_MANAGE_PRICING COACHING_VIEW_PROGRESS COACHING_MANAGE_PROGRESS`.split(/\s+/));

// New key → [existing keys whose holders should receive it so nobody loses access they already had]. Exports get none:
// under the new rules they need an explicit Edit.
const BACKFILL = {
  TOURNAMENTS_VIEW: ["DASHBOARD_VIEW"],
  GUEST_PLAYERS_VIEW: ["GUEST_BOOKINGS_VIEW"],
  GUEST_PLAYERS_EDIT: ["GUEST_BOOKINGS_EDIT"],
  MEMBERSHIP_SCHEDULE_VIEW: ["MEMBERSHIPS_VIEW"],
  MEMBERSHIP_PLANS_VIEW: ["MEMBERSHIPS_VIEW"],
  MEMBERSHIP_PLANS_EDIT: ["MEMBERSHIPS_EDIT"],
  MEMBERSHIP_SESSIONS_VIEW: ["MEMBERSHIPS_VIEW"],
  MEMBERSHIP_SESSIONS_EDIT: ["MEMBERSHIPS_EDIT"],
  COACHING_PROGRAMS_VIEW: ["COACHING_VIEW"],
  COACHING_STUDENTS_VIEW: ["COACHING_VIEW"],
  COACHING_SESSIONS_VIEW: ["COACHING_VIEW"],
  COACHING_SCHEDULE_VIEW: ["COACHING_VIEW"],
  COACHING_REPORTS_VIEW: ["COACHING_VIEW"],
  MAINTENANCE_CATEGORIES_VIEW: ["MAINTENANCE_VIEW"],
  MAINTENANCE_CATEGORIES_EDIT: ["MAINTENANCE_CREATE"],
  FINANCE_TRANSACTIONS_VIEW: ["FINANCE_VIEW"],
  FINANCE_PAYMENTS_VIEW: ["FINANCE_VIEW"],
  FINANCE_EXPENSES_VIEW: ["FINANCE_VIEW"],
  FINANCE_CLOSING_VIEW: ["FINANCE_VIEW"],
  REFUNDS_VIEW: ["FINANCE_VIEW"],
  REPORT_OVERVIEW_VIEW: ["REPORTS_VIEW"],
  REPORT_UTILIZATION_VIEW: ["REPORTS_VIEW"],
  REPORT_REVENUE_VIEW: ["REPORTS_VIEW_FINANCIAL"],
  REPORT_MEMBERSHIPS_VIEW: ["REPORTS_VIEW"],
  REPORT_GUESTS_VIEW: ["REPORTS_VIEW"],
  ROLES_VIEW: ["USERS_VIEW"],
  ACCESS_HISTORY_VIEW: ["USERS_VIEW"],
  FACILITY_SETTINGS_VIEW: ["COURTS_VIEW"],
  FACILITY_SETTINGS_EDIT: ["COURTS_EDIT"],
};

const MODULE_OF = (key) => {
  const page = PAGES.find((p) => p[6].includes(key) || p[7].includes(key) || p[8].includes(key));
  return page ? page[1] : "Other";
};
const titleCase = (k) => k.toLowerCase().split("_").map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");
const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";
const arr = (a) => (a.length ? "array[" + a.map(q).join(", ") + "]::text[]" : "'{}'::text[]");

const allKeys = new Set();
for (const p of PAGES) for (const k of [...p[6], ...p[7], ...p[8]]) allKeys.add(k);
const newKeys = [...allKeys].filter((k) => !EXISTING.has(k));
newKeys.push("COACHING_OWN_ONLY");

let sort = 1000;
const permRows = newKeys.map((k) => {
  const isView = /_VIEW$/.test(k);
  const action = isView ? "VIEW" : /_EXPORT$/.test(k) ? "EXPORT" : /_EDIT$/.test(k) ? "EDIT" : k === "COACHING_OWN_ONLY" ? "RESTRICT" : "MANAGE";
  const label = k === "COACHING_OWN_ONLY" ? "Limit coaching to own coach profile" : titleCase(k);
  const desc = k === "COACHING_OWN_ONLY" ? "Restriction: the person only sees their own coach profile, sessions, programs and students." : `Page access: ${titleCase(k)}.`;
  return `  (${q(k)}, ${q(k === "COACHING_OWN_ONLY" ? "Coaching" : MODULE_OF(k))}, ${q(action)}, ${q(label)}, ${q(desc)}, false, ${sort++})`;
});

const pageRows = PAGES.map((p, i) =>
  `  (${q(p[0])}, ${q(p[1])}, ${q(p[2])}, ${q(p[3])}, ${p[4]}, ${p[5] ? q(p[5]) : "null"}, ${arr(p[6])}, ${arr(p[7])}, ${arr(p[8])}, ${(i + 1) * 10})`);

const backfill = Object.entries(BACKFILL).map(([nk, from]) => `  (${q(nk)}, ${arr(from)})`);

const sql = `-- Page access matrix: every page gets None / View / Edit, per role.
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
${permRows.join(",\n")}
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
${pageRows.join(",\n")};

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
${backfill.join(",\n")}
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
`;
fs.writeFileSync("c:/Users/umash/OneDrive/Documents/GitHub/GameAll-Club-Management/supabase/migrations/0155_page_access_matrix.sql", sql);
console.log("new keys:", newKeys.length, "pages:", PAGES.length);

// ── Client catalogs (generated from the same definition so the database, web and Flutter can never drift) ──
const ROOT = "c:/Users/umash/OneDrive/Documents/GitHub/GameAll-Club-Management/";
const jsArr = (a) => "[" + a.map((x) => JSON.stringify(x)).join(", ") + "]";
const ts = `// GENERATED by scripts/gen-access-catalog.cjs — do not edit by hand. Mirrors the \`access_pages\` table (migration 0155).
export interface AccessPage {
  key: string;
  group: string;
  label: string;
  description: string;
  /** false: the page only supports None / View. */
  canEdit: boolean;
  /** Label for the top level where it isn't plain "Edit" (report pages: "Edit (can export)"). */
  editLabel: string | null;
  viewKeys: string[];
  editKeys: string[];
  extraKeys: string[];
}

export const ACCESS_PAGES: AccessPage[] = [
${PAGES.map((p) => `  { key: ${JSON.stringify(p[0])}, group: ${JSON.stringify(p[1])}, label: ${JSON.stringify(p[2])}, description: ${JSON.stringify(p[3])}, canEdit: ${p[4]}, editLabel: ${p[5] ? JSON.stringify(p[5]) : "null"}, viewKeys: ${jsArr(p[6])}, editKeys: ${jsArr(p[7])}, extraKeys: ${jsArr(p[8])} },`).join("\n")}
];

export type PageKey = ${PAGES.map((p) => JSON.stringify(p[0])).join(" | ")};

/** The restriction key: limits Coaching to the person's own coach profile, sessions, programs and students. */
export const COACHING_OWN_ONLY = "COACHING_OWN_ONLY";
`;
fs.writeFileSync(ROOT + "src/features/access/catalog.generated.ts", ts);

const dq = (s) => "'" + String(s).split("\\").join("\\\\").split("'").join("\\'").split("$").join("\\$") + "'";
const dList = (a) => "const [" + a.map(dq).join(", ") + "]";
const dart = `// GENERATED by scripts/gen-access-catalog.cjs — do not edit by hand. Mirrors the \`access_pages\` table (migration 0155).

class AccessPage {
  const AccessPage({
    required this.key,
    required this.group,
    required this.label,
    required this.description,
    required this.canEdit,
    required this.editLabel,
    required this.viewKeys,
    required this.editKeys,
    required this.extraKeys,
  });

  final String key;
  final String group;
  final String label;
  final String description;

  /// false: the page only supports None / View.
  final bool canEdit;

  /// Label for the top level where it isn't plain "Edit" (report pages: "Edit (can export)").
  final String? editLabel;
  final List<String> viewKeys;
  final List<String> editKeys;
  final List<String> extraKeys;
}

/// The restriction key: limits Coaching to the person's own coach profile, sessions, programs and students.
const coachingOwnOnly = 'COACHING_OWN_ONLY';

${PAGES.map((p) => `const accessPage${p[0].split("_").map((w) => w[0] + w.slice(1).toLowerCase()).join("")} = ${dq(p[0])};`).join("\n")}

const accessPages = <AccessPage>[
${PAGES.map((p) => `  AccessPage(\n    key: ${dq(p[0])},\n    group: ${dq(p[1])},\n    label: ${dq(p[2])},\n    description: ${dq(p[3])},\n    canEdit: ${p[4]},\n    editLabel: ${p[5] ? dq(p[5]) : "null"},\n    viewKeys: <String>[${p[6].map(dq).join(", ")}],\n    editKeys: <String>[${p[7].map(dq).join(", ")}],\n    extraKeys: <String>[${p[8].map(dq).join(", ")}],\n  ),`).join("\n")}
];
`;
fs.writeFileSync(ROOT + "mobile/lib/core/access/access_pages.g.dart", dart);
console.log("client catalogs written");
