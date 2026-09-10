-- ═══════════════════════════════════════════════════════════════════════════
-- Staff assignments — the columns the Staff module needs on facility_users,
-- plus the audit trail and the forced-password-reset flag.
--
-- facility_users keeps its (facility_id, user_id) primary key — one
-- assignment per person per facility, exactly as today. Everything here is
-- additive; every existing row is backfilled to its current effective state
-- (ACTIVE, primary, activated when it was created).
-- ═══════════════════════════════════════════════════════════════════════════


alter table facility_users
  -- A surrogate id so the UI and audit rows can reference one assignment.
  add column if not exists id uuid not null default gen_random_uuid(),
  -- A custom role. Null → the person's `role` enum resolves to its system /
  -- facility-override template (see has_permission, 0074).
  add column if not exists role_id uuid references roles (id) on delete set null,
  add column if not exists status text not null default 'ACTIVE'
    check (status in ('ACTIVE', 'INACTIVE', 'INVITED')),
  -- Which facility a multi-facility staff member lands in by default.
  add column if not exists is_primary boolean not null default true,
  -- Display job title ("Front Desk", "Coach") — cosmetic, independent of role.
  add column if not exists title text,
  add column if not exists notes text,
  add column if not exists invited_by uuid references profiles (id) on delete set null,
  add column if not exists invited_at timestamptz,
  add column if not exists activated_at timestamptz,
  add column if not exists last_login_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists facility_users_id_idx on facility_users (id);
create index if not exists facility_users_facility_status_idx on facility_users (facility_id, status);
create index if not exists facility_users_role_id_idx on facility_users (role_id) where role_id is not null;

-- Existing assignments predate the concept: all active, all primary, activated
-- when the row was created.
update facility_users
  set status = 'ACTIVE', is_primary = true, activated_at = coalesce(activated_at, created_at)
  where activated_at is null;

drop trigger if exists facility_users_set_updated_at on facility_users;
create trigger facility_users_set_updated_at
  before update on facility_users
  for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- A staff account created by an administrator starts with a one-time
-- temporary password (returned once by the create-staff edge function,
-- never stored here) and must set their own on first sign-in.
-- ─────────────────────────────────────────────────────────────────────────
alter table profiles
  add column if not exists must_reset_password boolean not null default false;


-- ─────────────────────────────────────────────────────────────────────────
-- security_events — the audit trail for authorization changes. Per-domain,
-- matching the maintenance / finance modules (there is no global audit
-- table). Never records a password, token or secret.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists security_events (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  -- STAFF_INVITED | STAFF_LINKED | STAFF_ACTIVATED | STAFF_DEACTIVATED |
  -- STAFF_ROLE_CHANGED | STAFF_PROFILE_UPDATED |
  -- FACILITY_ACCESS_GRANTED | FACILITY_ACCESS_REMOVED |
  -- ROLE_CREATED | ROLE_UPDATED | ROLE_DELETED | ROLE_PERMISSIONS_UPDATED
  event text not null,
  actor uuid references profiles (id) on delete set null,
  target_user_id uuid references profiles (id) on delete set null,
  target_role_id uuid references roles (id) on delete set null,
  summary text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists security_events_facility_idx on security_events (facility_id, created_at desc);

alter table security_events enable row level security;

drop policy if exists "security_events_select_users_view" on security_events;
create policy "security_events_select_users_view" on security_events for select
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));
-- Writes only via the SECURITY DEFINER RPCs (0075).


-- ─────────────────────────────────────────────────────────────────────────
-- log_security_event — the single insert path, so every RPC records events
-- the same shape.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function log_security_event(
  p_facility_id uuid,
  p_event text,
  p_summary text,
  p_target_user_id uuid default null,
  p_target_role_id uuid default null,
  p_detail jsonb default '{}'::jsonb
) returns void
language sql
security definer
set search_path = public
as $$
  insert into security_events (facility_id, event, actor, target_user_id, target_role_id, summary, detail)
  values (p_facility_id, p_event, auth.uid(), p_target_user_id, p_target_role_id, p_summary, coalesce(p_detail, '{}'::jsonb));
$$;
