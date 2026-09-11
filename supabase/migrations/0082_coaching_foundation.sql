-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching Management — the foundation: permissions, coaches, coach
-- availability, programs, the per-domain audit trail.
--
-- Coaching is an INTEGRATION module. It reuses:
--   * profiles / facility_users  — a coach is an existing staff member with a
--     coaching profile (never a second account).
--   * members                    — a student is an existing facility member.
--   * courts + the availability engine (create_booking / court_has_active_*
--     predicates, 0007/0014/0045/0068) — coaching sessions reserve courts
--     through the same conflict checks, never a second availability algorithm.
--   * has_permission (0074)       — every write is gated here.
--   * payments / record_obligation_payment / list_pending_payments (0052) —
--     coaching fees are obligations settled through the one payment path
--     (extended in 0085), never a second ledger.
--
-- Tables added: coaches, coach_availability, coach_availability_exceptions,
-- coaching_programs, coaching_events (0082); coaching_sessions,
-- coaching_session_students (0083); coaching_enrollments,
-- student_progress_notes (0084).
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- Permissions (spec §36). Added to the catalog and granted to the system
-- roles here — 0072's one-time "owner gets every key" seed does not reach
-- rows inserted later (same as the inventory module, 0078).
-- ─────────────────────────────────────────────────────────────────────────
insert into permissions (key, module, action, label, description, is_dangerous, sort_order) values
  ('COACHING_VIEW',               'Coaching', 'VIEW',               'View coaching',            'See coaches, programs, the schedule, sessions and enrollments.', false, 1100),
  ('COACHING_MANAGE_COACHES',     'Coaching', 'MANAGE_COACHES',     'Manage coaches',           'Add coaching profiles to staff, edit them, set availability.', false, 1110),
  ('COACHING_MANAGE_PROGRAMS',    'Coaching', 'MANAGE_PROGRAMS',    'Manage programs',          'Create, edit and deactivate coaching programs.', false, 1120),
  ('COACHING_CREATE_SESSION',     'Coaching', 'CREATE_SESSION',     'Create sessions',          'Schedule coaching sessions on a court.', false, 1130),
  ('COACHING_EDIT_SESSION',       'Coaching', 'EDIT_SESSION',       'Edit sessions',            'Reschedule a session, start it, complete it, edit its roster.', false, 1140),
  ('COACHING_CANCEL_SESSION',     'Coaching', 'CANCEL_SESSION',     'Cancel sessions',          'Cancel a scheduled coaching session.', true, 1150),
  ('COACHING_MANAGE_ENROLLMENTS', 'Coaching', 'MANAGE_ENROLLMENTS', 'Manage enrollments',       'Enrol members into programs and manage those enrollments.', false, 1160),
  ('COACHING_MANAGE_PRICING',     'Coaching', 'MANAGE_PRICING',     'Manage coaching pricing',  'Set program prices and per-enrollment fee overrides.', false, 1170),
  ('COACHING_VIEW_PROGRESS',      'Coaching', 'VIEW_PROGRESS',      'View student progress',    'Read student progress and coach notes.', false, 1180),
  ('COACHING_MANAGE_PROGRESS',    'Coaching', 'MANAGE_PROGRESS',    'Record student progress',  'Add and edit student progress notes.', false, 1190)
on conflict (key) do nothing;

-- Owner + Manager: full coaching management.
insert into role_permissions (role_id, permission_key)
select r, key from (values
  ('00000000-0000-0000-0000-0000000000a1'::uuid), ('00000000-0000-0000-0000-0000000000a2'::uuid)
) as roles(r)
cross join (select key from permissions where module = 'Coaching') as p
on conflict do nothing;

-- Staff: view coaching + record progress (front-desk enrols via the manager
-- flow; a plain staff member can still see the schedule and note progress).
insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000a3', key
from (values ('COACHING_VIEW'), ('COACHING_VIEW_PROGRESS')) as p(key)
on conflict do nothing;

-- "Coach" template (0072 b2): the coach's own operational surface — see the
-- schedule, run sessions (start/complete/roster), record progress. Not
-- program management, pricing, enrollments or cancellation (spec §37).
insert into role_permissions (role_id, permission_key)
select '00000000-0000-0000-0000-0000000000b2', key
from (values
  ('COACHING_VIEW'), ('COACHING_EDIT_SESSION'),
  ('COACHING_VIEW_PROGRESS'), ('COACHING_MANAGE_PROGRESS')
) as p(key)
on conflict do nothing;


-- ─────────────────────────────────────────────────────────────────────────
-- coaches — a coaching profile on an existing staff member. Name, email,
-- phone and photo live on profiles; this table only adds coaching data
-- (spec §43). One profile per facility.
-- ─────────────────────────────────────────────────────────────────────────
create table coaches (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  specialization text,
  experience_years numeric(4,1) check (experience_years is null or experience_years >= 0),
  certifications text,
  bio text,
  hourly_rate_minor integer check (hourly_rate_minor is null or hourly_rate_minor >= 0),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE', 'ON_LEAVE')),
  joined_on date,
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (facility_id, user_id)
);

create index coaches_facility_status_idx on coaches (facility_id, status);

alter table coaches enable row level security;

drop policy if exists "coaches_select" on coaches;
create policy "coaches_select" on coaches for select
  using (has_permission(facility_id, 'COACHING_VIEW'));
-- Writes go through the SECURITY DEFINER RPCs below (gated COACHING_MANAGE_COACHES).

drop trigger if exists coaches_set_updated_at on coaches;
create trigger coaches_set_updated_at
  before update on coaches
  for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- coach_availability — recurring weekly windows in the facility's local
-- time (spec §5 / §47 / §69). day_of_week: 0 = Sunday … 6 = Saturday, to
-- match extract(dow) used throughout the availability engine.
-- ─────────────────────────────────────────────────────────────────────────
create table coach_availability (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null references coaches (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6),
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default now(),
  constraint coach_availability_time_check check (end_time > start_time)
);

create index coach_availability_coach_idx on coach_availability (coach_id, day_of_week);

alter table coach_availability enable row level security;
drop policy if exists "coach_availability_select" on coach_availability;
create policy "coach_availability_select" on coach_availability for select
  using (has_permission(facility_id, 'COACHING_VIEW'));


-- coach_availability_exceptions — a specific date the coach is off (holiday)
-- or has a one-off window. is_available = false → unavailable all day.
create table coach_availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null references coaches (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  exception_date date not null,
  is_available boolean not null default false,
  start_time time,
  end_time time,
  reason text,
  created_at timestamptz not null default now(),
  constraint coach_exception_window_check check (
    (is_available = false) or (start_time is not null and end_time is not null and end_time > start_time)
  ),
  unique (coach_id, exception_date)
);

alter table coach_availability_exceptions enable row level security;
drop policy if exists "coach_availability_exceptions_select" on coach_availability_exceptions;
create policy "coach_availability_exceptions_select" on coach_availability_exceptions for select
  using (has_permission(facility_id, 'COACHING_VIEW'));


-- ─────────────────────────────────────────────────────────────────────────
-- coaching_programs — a reusable class/program *definition* (spec §6 / §44).
-- A program never creates sessions; sessions (0083) are scheduled instances.
-- Deactivated, never deleted, once referenced (spec §"Program Status").
-- ─────────────────────────────────────────────────────────────────────────
create table coaching_programs (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  name text not null,
  level text not null default 'All Levels',
  age_group text not null default 'All Ages',
  category text not null default 'General',
  description text,
  facility_sport_id uuid references facility_sports (id) on delete set null,
  default_duration_minutes integer not null default 60 check (default_duration_minutes between 15 and 480),
  default_capacity integer not null default 1 check (default_capacity between 1 and 100),
  session_count integer check (session_count is null or session_count >= 1),
  -- The default coaching fee for an enrollment, in minor units (paise). Null
  -- → priced per enrollment. 0 → typically membership-included (spec §27).
  default_price_minor integer check (default_price_minor is null or default_price_minor >= 0),
  is_membership_included boolean not null default false,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE')),
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Case-insensitive uniqueness of the program name within a facility. A
-- table-level UNIQUE cannot take an expression, so it is an index (same
-- pattern as vendors / inventory_categories in 0078).
create unique index coaching_programs_facility_name_idx
  on coaching_programs (facility_id, lower(name));
create index coaching_programs_facility_status_idx on coaching_programs (facility_id, status);

alter table coaching_programs enable row level security;
drop policy if exists "coaching_programs_select" on coaching_programs;
create policy "coaching_programs_select" on coaching_programs for select
  using (has_permission(facility_id, 'COACHING_VIEW'));

drop trigger if exists coaching_programs_set_updated_at on coaching_programs;
create trigger coaching_programs_set_updated_at
  before update on coaching_programs
  for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- coaching_events — the per-domain audit trail (spec §56). Same shape as
-- security_events / maintenance_ticket_activity / inventory_events: there is
-- no global audit table. Never records sensitive information.
-- ─────────────────────────────────────────────────────────────────────────
create table coaching_events (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  event text not null,
  actor uuid references profiles (id) on delete set null,
  coach_id uuid,
  program_id uuid,
  session_id uuid,
  enrollment_id uuid,
  summary text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index coaching_events_facility_idx on coaching_events (facility_id, created_at desc);
create index coaching_events_session_idx on coaching_events (session_id) where session_id is not null;
create index coaching_events_enrollment_idx on coaching_events (enrollment_id) where enrollment_id is not null;

alter table coaching_events enable row level security;
drop policy if exists "coaching_events_select" on coaching_events;
create policy "coaching_events_select" on coaching_events for select
  using (has_permission(facility_id, 'COACHING_VIEW'));

create or replace function log_coaching_event(
  p_facility_id uuid,
  p_event text,
  p_summary text,
  p_coach_id uuid default null,
  p_program_id uuid default null,
  p_session_id uuid default null,
  p_enrollment_id uuid default null,
  p_detail jsonb default '{}'::jsonb
) returns void
language sql
security definer
set search_path = public
as $$
  insert into coaching_events (facility_id, event, actor, coach_id, program_id, session_id, enrollment_id, summary, detail)
  values (p_facility_id, p_event, auth.uid(), p_coach_id, p_program_id, p_session_id, p_enrollment_id, p_summary, coalesce(p_detail, '{}'::jsonb));
$$;


-- ═════════════════════════════════════════════════════════════════════════
-- Coach write RPCs — gated COACHING_MANAGE_COACHES.
-- ═════════════════════════════════════════════════════════════════════════

-- add_coach — attach a coaching profile to an existing facility staff member.
-- Rejects a user who is not an ACTIVE facility_users assignment (spec §2/§3:
-- never a second account).
create or replace function add_coach(
  p_facility_id uuid,
  p_user_id uuid,
  p_specialization text default null,
  p_experience_years numeric default null,
  p_certifications text default null,
  p_bio text default null,
  p_hourly_rate_minor integer default null,
  p_status text default 'ACTIVE',
  p_joined_on date default null
) returns coaches
language plpgsql
security definer
set search_path = public
as $$
declare result coaches;
begin
  if not has_permission(p_facility_id, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from facility_users
    where facility_id = p_facility_id and user_id = p_user_id and status = 'ACTIVE'
  ) then
    raise exception 'That person is not an active staff member of this facility. Add them as staff first.' using errcode = '23503';
  end if;
  if coalesce(p_status, 'ACTIVE') not in ('ACTIVE', 'INACTIVE', 'ON_LEAVE') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  insert into coaches (
    facility_id, user_id, specialization, experience_years, certifications, bio,
    hourly_rate_minor, status, joined_on, created_by
  ) values (
    p_facility_id, p_user_id,
    nullif(trim(coalesce(p_specialization, '')), ''), p_experience_years,
    nullif(trim(coalesce(p_certifications, '')), ''), nullif(trim(coalesce(p_bio, '')), ''),
    p_hourly_rate_minor, coalesce(p_status, 'ACTIVE'), coalesce(p_joined_on, current_date), auth.uid()
  )
  returning * into result;

  perform log_coaching_event(p_facility_id, 'COACH_CREATED',
    'Coach profile added', result.id, null, null, null,
    jsonb_build_object('userId', p_user_id));
  return result;
exception when unique_violation then
  raise exception 'This staff member already has a coaching profile.' using errcode = '23505';
end;
$$;

grant execute on function add_coach(uuid, uuid, text, numeric, text, text, integer, text, date) to authenticated;


create or replace function update_coach(
  p_coach_id uuid,
  p_specialization text default null,
  p_experience_years numeric default null,
  p_certifications text default null,
  p_bio text default null,
  p_hourly_rate_minor integer default null,
  p_status text default null,
  p_joined_on date default null
) returns coaches
language plpgsql
security definer
set search_path = public
as $$
declare result coaches;
begin
  select * into result from coaches where id = p_coach_id;
  if result.id is null then
    raise exception 'Coach not found.' using errcode = 'P0002';
  end if;
  if not has_permission(result.facility_id, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('ACTIVE', 'INACTIVE', 'ON_LEAVE') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  update coaches set
    specialization = coalesce(p_specialization, specialization),
    experience_years = coalesce(p_experience_years, experience_years),
    certifications = coalesce(p_certifications, certifications),
    bio = coalesce(p_bio, bio),
    hourly_rate_minor = coalesce(p_hourly_rate_minor, hourly_rate_minor),
    status = coalesce(p_status, status),
    joined_on = coalesce(p_joined_on, joined_on)
  where id = p_coach_id
  returning * into result;

  perform log_coaching_event(result.facility_id,
    case when p_status = 'INACTIVE' then 'COACH_DEACTIVATED' else 'COACH_UPDATED' end,
    'Coach profile updated', result.id);
  return result;
end;
$$;

grant execute on function update_coach(uuid, text, numeric, text, text, integer, text, date) to authenticated;


-- set_coach_availability — replace the coach's whole recurring weekly grid
-- in one call (the UI edits it as a set). p_windows is a jsonb array of
-- { dayOfWeek, startTime, endTime }.
create or replace function set_coach_availability(p_coach_id uuid, p_windows jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_facility uuid;
  w jsonb;
begin
  select facility_id into v_facility from coaches where id = p_coach_id;
  if v_facility is null then
    raise exception 'Coach not found.' using errcode = 'P0002';
  end if;
  if not has_permission(v_facility, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;

  delete from coach_availability where coach_id = p_coach_id;
  for w in select * from jsonb_array_elements(coalesce(p_windows, '[]'::jsonb))
  loop
    insert into coach_availability (coach_id, facility_id, day_of_week, start_time, end_time)
    values (
      p_coach_id, v_facility,
      (w->>'dayOfWeek')::smallint,
      (w->>'startTime')::time,
      (w->>'endTime')::time
    );
  end loop;

  perform log_coaching_event(v_facility, 'COACH_UPDATED', 'Coach availability updated', p_coach_id);
end;
$$;

grant execute on function set_coach_availability(uuid, jsonb) to authenticated;


create or replace function set_coach_availability_exception(
  p_coach_id uuid,
  p_exception_date date,
  p_is_available boolean,
  p_start_time time default null,
  p_end_time time default null,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_facility uuid;
begin
  select facility_id into v_facility from coaches where id = p_coach_id;
  if v_facility is null then
    raise exception 'Coach not found.' using errcode = 'P0002';
  end if;
  if not has_permission(v_facility, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;

  insert into coach_availability_exceptions (coach_id, facility_id, exception_date, is_available, start_time, end_time, reason)
  values (p_coach_id, v_facility, p_exception_date, coalesce(p_is_available, false), p_start_time, p_end_time, nullif(trim(coalesce(p_reason, '')), ''))
  on conflict (coach_id, exception_date) do update
    set is_available = excluded.is_available,
        start_time = excluded.start_time,
        end_time = excluded.end_time,
        reason = excluded.reason;
end;
$$;

grant execute on function set_coach_availability_exception(uuid, date, boolean, time, time, text) to authenticated;

create or replace function delete_coach_availability_exception(p_exception_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_facility uuid;
begin
  select facility_id into v_facility from coach_availability_exceptions where id = p_exception_id;
  if v_facility is null then return; end if;
  if not has_permission(v_facility, 'COACHING_MANAGE_COACHES') then
    raise exception 'You don''t have permission to manage coaches.' using errcode = '42501';
  end if;
  delete from coach_availability_exceptions where id = p_exception_id;
end;
$$;

grant execute on function delete_coach_availability_exception(uuid) to authenticated;


-- coach_is_available(coach, start, end) — does [start, end) fall inside a
-- recurring weekly window for the coach, in the facility's local time, and
-- not inside an "unavailable" date exception? Used by session creation
-- (0083) and coach-utilization reporting (0086).
create or replace function coach_is_available(p_coach_id uuid, p_start timestamptz, p_end timestamptz)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  tz text;
  v_facility uuid;
  local_start timestamp;
  local_end timestamp;
  d date;
  dow smallint;
  start_t time;
  end_t time;
  exc coach_availability_exceptions;
begin
  select c.facility_id, coalesce(f.timezone, 'Asia/Kolkata')
    into v_facility, tz
  from coaches c join facilities f on f.id = c.facility_id
  where c.id = p_coach_id;
  if v_facility is null then return false; end if;

  local_start := p_start at time zone tz;
  local_end := p_end at time zone tz;
  if local_end::date <> local_start::date then
    return false;  -- sessions stay within one local day
  end if;

  d := local_start::date;
  dow := extract(dow from local_start);
  start_t := local_start::time;
  end_t := local_end::time;

  select * into exc from coach_availability_exceptions
    where coach_id = p_coach_id and exception_date = d;
  if exc.id is not null then
    if not exc.is_available then return false; end if;
    return start_t >= exc.start_time and end_t <= exc.end_time;
  end if;

  return exists (
    select 1 from coach_availability ca
    where ca.coach_id = p_coach_id
      and ca.day_of_week = dow
      and start_t >= ca.start_time
      and end_t <= ca.end_time
  );
end;
$$;

grant execute on function coach_is_available(uuid, timestamptz, timestamptz) to authenticated;


-- ═════════════════════════════════════════════════════════════════════════
-- Program write RPCs — gated COACHING_MANAGE_PROGRAMS (pricing fields also
-- need COACHING_MANAGE_PRICING).
-- ═════════════════════════════════════════════════════════════════════════
create or replace function create_coaching_program(
  p_facility_id uuid,
  p_name text,
  p_level text default 'All Levels',
  p_age_group text default 'All Ages',
  p_category text default 'General',
  p_description text default null,
  p_facility_sport_id uuid default null,
  p_default_duration_minutes integer default 60,
  p_default_capacity integer default 1,
  p_session_count integer default null,
  p_default_price_minor integer default null,
  p_is_membership_included boolean default false
) returns coaching_programs
language plpgsql
security definer
set search_path = public
as $$
declare result coaching_programs;
begin
  if not has_permission(p_facility_id, 'COACHING_MANAGE_PROGRAMS') then
    raise exception 'You don''t have permission to manage programs.' using errcode = '42501';
  end if;
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'A program needs a name.' using errcode = '23514';
  end if;
  if (p_default_price_minor is not null or p_is_membership_included)
     and not has_permission(p_facility_id, 'COACHING_MANAGE_PRICING') then
    raise exception 'You don''t have permission to set coaching pricing.' using errcode = '42501';
  end if;

  insert into coaching_programs (
    facility_id, name, level, age_group, category, description, facility_sport_id,
    default_duration_minutes, default_capacity, session_count, default_price_minor,
    is_membership_included, created_by
  ) values (
    p_facility_id, trim(p_name), coalesce(nullif(trim(p_level), ''), 'All Levels'),
    coalesce(nullif(trim(p_age_group), ''), 'All Ages'), coalesce(nullif(trim(p_category), ''), 'General'),
    nullif(trim(coalesce(p_description, '')), ''), p_facility_sport_id,
    coalesce(p_default_duration_minutes, 60), coalesce(p_default_capacity, 1),
    p_session_count, p_default_price_minor, coalesce(p_is_membership_included, false), auth.uid()
  )
  returning * into result;

  perform log_coaching_event(p_facility_id, 'PROGRAM_CREATED',
    'Program created: ' || result.name, null, result.id);
  return result;
exception when unique_violation then
  raise exception 'A program with this name already exists.' using errcode = '23505';
end;
$$;

grant execute on function create_coaching_program(uuid, text, text, text, text, text, uuid, integer, integer, integer, integer, boolean) to authenticated;


create or replace function update_coaching_program(
  p_program_id uuid,
  p_name text default null,
  p_level text default null,
  p_age_group text default null,
  p_category text default null,
  p_description text default null,
  p_facility_sport_id uuid default null,
  p_default_duration_minutes integer default null,
  p_default_capacity integer default null,
  p_session_count integer default null,
  p_default_price_minor integer default null,
  p_is_membership_included boolean default null,
  p_status text default null
) returns coaching_programs
language plpgsql
security definer
set search_path = public
as $$
declare
  result coaching_programs;
  v_pricing_touched boolean := (p_default_price_minor is not null or p_is_membership_included is not null);
begin
  select * into result from coaching_programs where id = p_program_id;
  if result.id is null then
    raise exception 'Program not found.' using errcode = 'P0002';
  end if;
  if not has_permission(result.facility_id, 'COACHING_MANAGE_PROGRAMS') then
    raise exception 'You don''t have permission to manage programs.' using errcode = '42501';
  end if;
  if v_pricing_touched and not has_permission(result.facility_id, 'COACHING_MANAGE_PRICING') then
    raise exception 'You don''t have permission to set coaching pricing.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('ACTIVE', 'INACTIVE') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  update coaching_programs set
    name = coalesce(nullif(trim(coalesce(p_name, '')), ''), name),
    level = coalesce(nullif(trim(coalesce(p_level, '')), ''), level),
    age_group = coalesce(nullif(trim(coalesce(p_age_group, '')), ''), age_group),
    category = coalesce(nullif(trim(coalesce(p_category, '')), ''), category),
    description = coalesce(p_description, description),
    facility_sport_id = coalesce(p_facility_sport_id, facility_sport_id),
    default_duration_minutes = coalesce(p_default_duration_minutes, default_duration_minutes),
    default_capacity = coalesce(p_default_capacity, default_capacity),
    session_count = coalesce(p_session_count, session_count),
    default_price_minor = coalesce(p_default_price_minor, default_price_minor),
    is_membership_included = coalesce(p_is_membership_included, is_membership_included),
    status = coalesce(p_status, status)
  where id = p_program_id
  returning * into result;

  perform log_coaching_event(result.facility_id,
    case when p_status = 'INACTIVE' then 'PROGRAM_DEACTIVATED' else 'PROGRAM_UPDATED' end,
    'Program updated: ' || result.name, null, result.id);
  return result;
exception when unique_violation then
  raise exception 'A program with this name already exists.' using errcode = '23505';
end;
$$;

grant execute on function update_coaching_program(uuid, text, text, text, text, text, uuid, integer, integer, integer, integer, boolean, text) to authenticated;
