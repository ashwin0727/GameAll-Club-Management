-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching Program Batches (v1) — the missing piece behind the "Schedule &
-- Batches" wizard step: a recurring weekly time slot (days/time/court/coach/
-- capacity) under a program. Nothing like this existed for coaching programs
-- before — coaching_sessions (0083) are individual DATED occurrences, not a
-- recurring template.
--
-- Mirrors membership_batches (0014) almost exactly on purpose — same shape
-- (days_of_week smallint[], start_time, end_time, court_id, capacity), same
-- "batch creation only checks the court belongs to this facility/sport, real
-- conflicts are resolved per-occurrence when a session is actually booked"
-- convention create_membership_batch already established. No second
-- availability engine, no upfront N-occurrences-out conflict scan invented
-- here — that's not what the existing pattern does either.
--
-- Also extends coaching_programs with the wizard's new fields (image, program
-- type, dates, capacity floor, structure tags, pricing/discount/tax, the
-- settings toggles) and its status lifecycle (DRAFT/ACTIVE/PAUSED/COMPLETED/
-- ARCHIVED — INACTIVE kept for backward compatibility with existing rows).
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- coaching_programs — new columns.
-- ─────────────────────────────────────────────────────────────────────────
alter table coaching_programs add column if not exists image_url text;
alter table coaching_programs add column if not exists program_type text not null default 'GROUP'
  check (program_type in ('GROUP', 'ONE_ON_ONE', 'TRIAL'));
alter table coaching_programs add column if not exists min_capacity integer
  check (min_capacity is null or min_capacity >= 0);
-- Structured focus-area tags ("Basic Techniques", "Footwork", ...) — a plain
-- array, not a lookup table, same reasoning as coaches.expertise_levels (0095):
-- small, facility-authored, free-text-ish vocabulary, not something queried by.
alter table coaching_programs add column if not exists program_structure text[] not null default '{}';
alter table coaching_programs add column if not exists session_format text;
alter table coaching_programs add column if not exists sessions_per_week integer
  check (sessions_per_week is null or sessions_per_week between 1 and 14);
alter table coaching_programs add column if not exists start_date date;
alter table coaching_programs add column if not exists end_date date;
alter table coaching_programs add column if not exists payment_mode text not null default 'OFFLINE'
  check (payment_mode in ('OFFLINE', 'ONLINE', 'BOTH'));
alter table coaching_programs add column if not exists early_bird_discount_minor integer
  check (early_bird_discount_minor is null or early_bird_discount_minor >= 0);
alter table coaching_programs add column if not exists discount_valid_till date;
alter table coaching_programs add column if not exists tax_percent numeric(5, 2)
  check (tax_percent is null or (tax_percent >= 0 and tax_percent <= 100));
alter table coaching_programs add column if not exists payment_notes text;
alter table coaching_programs add column if not exists allow_waitlist boolean not null default true;
alter table coaching_programs add column if not exists allow_trial_session boolean not null default false;
alter table coaching_programs add column if not exists auto_enroll_next_batch boolean not null default false;
alter table coaching_programs add column if not exists send_notifications boolean not null default true;
alter table coaching_programs add column if not exists visible_in_booking boolean not null default false;
alter table coaching_programs add column if not exists enrollment_deadline date;

alter table coaching_programs drop constraint if exists coaching_programs_status_check;
alter table coaching_programs add constraint coaching_programs_status_check
  check (status in ('DRAFT', 'ACTIVE', 'PAUSED', 'COMPLETED', 'ARCHIVED', 'INACTIVE'));

-- Postgres has no `ADD CONSTRAINT IF NOT EXISTS` for check constraints (unlike
-- ADD COLUMN or DROP CONSTRAINT) — drop-then-add is the idiomatic idempotent
-- form, same as coaching_programs_status_check above.
alter table coaching_programs drop constraint if exists coaching_programs_dates_check;
alter table coaching_programs add constraint coaching_programs_dates_check
  check (end_date is null or start_date is null or end_date >= start_date);
alter table coaching_programs drop constraint if exists coaching_programs_min_capacity_check;
alter table coaching_programs add constraint coaching_programs_min_capacity_check
  check (min_capacity is null or min_capacity <= default_capacity);
alter table coaching_programs drop constraint if exists coaching_programs_discount_check;
alter table coaching_programs add constraint coaching_programs_discount_check
  check (early_bird_discount_minor is null or default_price_minor is null or early_bird_discount_minor <= default_price_minor);


-- ─────────────────────────────────────────────────────────────────────────
-- coaching_program_batches — same shape as membership_batches (0014).
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists coaching_program_batches (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  program_id uuid not null references coaching_programs (id) on delete cascade,
  court_id uuid not null references courts (id) on delete restrict,
  coach_id uuid references coaches (id) on delete set null,
  name text not null,
  -- 0=Sunday..6=Saturday, matching extract(dow from timestamp).
  days_of_week smallint[] not null,
  start_time time not null,
  end_time time not null,
  capacity integer not null check (capacity > 0),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE')),
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coaching_program_batches_time_check check (end_time > start_time),
  constraint coaching_program_batches_days_check check (
    coalesce(array_length(days_of_week, 1), 0) > 0
    and days_of_week <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
  )
);

create index if not exists coaching_program_batches_program_idx on coaching_program_batches (program_id);
create index if not exists coaching_program_batches_court_idx on coaching_program_batches (court_id);

alter table coaching_program_batches enable row level security;

drop policy if exists "coaching_program_batches_select" on coaching_program_batches;
create policy "coaching_program_batches_select" on coaching_program_batches for select
  using (has_permission(facility_id, 'COACHING_VIEW'));
-- Writes go through the RPCs below (SECURITY DEFINER, gated COACHING_MANAGE_PROGRAMS).

drop trigger if exists coaching_program_batches_set_updated_at on coaching_program_batches;
create trigger coaching_program_batches_set_updated_at
  before update on coaching_program_batches
  for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- Batch CRUD.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function create_coaching_program_batch(
  p_program_id uuid,
  p_court_id uuid,
  p_name text,
  p_days_of_week smallint[],
  p_start_time time,
  p_end_time time,
  p_capacity integer,
  p_coach_id uuid default null
) returns coaching_program_batches
language plpgsql
security definer
set search_path = public
as $$
declare
  program coaching_programs;
  court courts;
  result coaching_program_batches;
begin
  select * into program from coaching_programs where id = p_program_id;
  if program.id is null then
    raise exception 'Program not found.' using errcode = 'P0002';
  end if;
  if not has_permission(program.facility_id, 'COACHING_MANAGE_PROGRAMS') then
    raise exception 'You don''t have permission to manage programs.' using errcode = '42501';
  end if;
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Batch name is required.' using errcode = '23514';
  end if;

  select * into court from courts where id = p_court_id and facility_id = program.facility_id;
  if court.id is null then
    raise exception 'That court does not belong to this facility.' using errcode = '23503';
  end if;

  if p_coach_id is not null and not exists (
    select 1 from coaches where id = p_coach_id and facility_id = program.facility_id and status = 'ACTIVE'
  ) then
    raise exception 'That coach is not an active coach at this facility.' using errcode = '23503';
  end if;

  insert into coaching_program_batches (
    facility_id, program_id, court_id, coach_id, name, days_of_week, start_time, end_time, capacity, created_by
  ) values (
    program.facility_id, p_program_id, p_court_id, p_coach_id, trim(p_name), p_days_of_week, p_start_time, p_end_time,
    p_capacity, auth.uid()
  ) returning * into result;

  perform log_coaching_event(program.facility_id, 'BATCH_CREATED', 'Batch created: ' || result.name, null, p_program_id);
  return result;
end;
$$;

grant execute on function create_coaching_program_batch(uuid, uuid, text, smallint[], time, time, integer, uuid) to authenticated;


create or replace function update_coaching_program_batch(
  p_batch_id uuid,
  p_name text default null,
  p_court_id uuid default null,
  p_coach_id uuid default null,
  p_days_of_week smallint[] default null,
  p_start_time time default null,
  p_end_time time default null,
  p_capacity integer default null,
  p_status text default null
) returns coaching_program_batches
language plpgsql
security definer
set search_path = public
as $$
declare
  existing coaching_program_batches;
  court courts;
  result coaching_program_batches;
begin
  select * into existing from coaching_program_batches where id = p_batch_id;
  if existing.id is null then
    raise exception 'Batch not found.' using errcode = 'P0002';
  end if;
  if not has_permission(existing.facility_id, 'COACHING_MANAGE_PROGRAMS') then
    raise exception 'You don''t have permission to manage programs.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('ACTIVE', 'INACTIVE') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  if p_court_id is not null then
    select * into court from courts where id = p_court_id and facility_id = existing.facility_id;
    if court.id is null then
      raise exception 'That court does not belong to this facility.' using errcode = '23503';
    end if;
  end if;
  if p_coach_id is not null and not exists (
    select 1 from coaches where id = p_coach_id and facility_id = existing.facility_id and status = 'ACTIVE'
  ) then
    raise exception 'That coach is not an active coach at this facility.' using errcode = '23503';
  end if;

  update coaching_program_batches set
    name = coalesce(nullif(trim(coalesce(p_name, '')), ''), name),
    court_id = coalesce(p_court_id, court_id),
    coach_id = case when p_coach_id is not null then p_coach_id else coach_id end,
    days_of_week = coalesce(p_days_of_week, days_of_week),
    start_time = coalesce(p_start_time, start_time),
    end_time = coalesce(p_end_time, end_time),
    capacity = coalesce(p_capacity, capacity),
    status = coalesce(p_status, status)
  where id = p_batch_id
  returning * into result;

  perform log_coaching_event(result.facility_id, 'BATCH_UPDATED', 'Batch updated: ' || result.name, null, result.program_id);
  return result;
end;
$$;

grant execute on function update_coaching_program_batch(uuid, text, uuid, uuid, smallint[], time, time, integer, text) to authenticated;


create or replace function delete_coaching_program_batch(p_batch_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare existing coaching_program_batches;
begin
  select * into existing from coaching_program_batches where id = p_batch_id;
  if existing.id is null then
    raise exception 'Batch not found.' using errcode = 'P0002';
  end if;
  if not has_permission(existing.facility_id, 'COACHING_MANAGE_PROGRAMS') then
    raise exception 'You don''t have permission to manage programs.' using errcode = '42501';
  end if;

  delete from coaching_program_batches where id = p_batch_id;
  perform log_coaching_event(existing.facility_id, 'BATCH_DELETED', 'Batch deleted: ' || existing.name, null, existing.program_id);
end;
$$;

grant execute on function delete_coaching_program_batch(uuid) to authenticated;


create or replace function list_coaching_program_batches(p_program_id uuid)
returns table (
  id uuid,
  court_id uuid,
  court_name text,
  coach_id uuid,
  coach_name text,
  name text,
  days_of_week smallint[],
  start_time time,
  end_time time,
  capacity integer,
  enrolled_count bigint,
  status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare program coaching_programs;
begin
  select * into program from coaching_programs where id = p_program_id;
  if program.id is null then
    raise exception 'Program not found.' using errcode = 'P0002';
  end if;
  if not has_permission(program.facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;

  return query
  select
    b.id, b.court_id, c.name, b.coach_id, pr.full_name, b.name, b.days_of_week, b.start_time, b.end_time,
    b.capacity,
    (select count(*) from coaching_enrollments e where e.program_id = p_program_id and e.status = 'ACTIVE')::bigint,
    b.status
  from coaching_program_batches b
  join courts c on c.id = b.court_id
  left join coaches co on co.id = b.coach_id
  left join profiles pr on pr.id = co.user_id
  where b.program_id = p_program_id
  order by b.created_at;
end;
$$;

grant execute on function list_coaching_program_batches(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- create_coaching_program / update_coaching_program — extended with the
-- wizard's new fields. New params default to null ("don't touch" on update,
-- sensible default on create).
-- ─────────────────────────────────────────────────────────────────────────
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
  p_is_membership_included boolean default false,
  p_image_url text default null,
  p_program_type text default 'GROUP',
  p_min_capacity integer default null,
  p_program_structure text[] default '{}',
  p_session_format text default null,
  p_sessions_per_week integer default null,
  p_start_date date default null,
  p_end_date date default null,
  p_payment_mode text default 'OFFLINE',
  p_early_bird_discount_minor integer default null,
  p_discount_valid_till date default null,
  p_tax_percent numeric default null,
  p_payment_notes text default null,
  p_allow_waitlist boolean default true,
  p_allow_trial_session boolean default false,
  p_auto_enroll_next_batch boolean default false,
  p_send_notifications boolean default true,
  p_visible_in_booking boolean default false,
  p_enrollment_deadline date default null,
  p_status text default 'ACTIVE'
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
  if p_status not in ('DRAFT', 'ACTIVE', 'PAUSED', 'COMPLETED', 'ARCHIVED', 'INACTIVE') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  insert into coaching_programs (
    facility_id, name, level, age_group, category, description, facility_sport_id,
    default_duration_minutes, default_capacity, session_count, default_price_minor,
    is_membership_included, created_by, image_url, program_type, min_capacity, program_structure,
    session_format, sessions_per_week, start_date, end_date, payment_mode, early_bird_discount_minor,
    discount_valid_till, tax_percent, payment_notes, allow_waitlist, allow_trial_session,
    auto_enroll_next_batch, send_notifications, visible_in_booking, enrollment_deadline, status
  ) values (
    p_facility_id, trim(p_name), coalesce(nullif(trim(p_level), ''), 'All Levels'),
    coalesce(nullif(trim(p_age_group), ''), 'All Ages'), coalesce(nullif(trim(p_category), ''), 'General'),
    nullif(trim(coalesce(p_description, '')), ''), p_facility_sport_id,
    coalesce(p_default_duration_minutes, 60), coalesce(p_default_capacity, 1),
    p_session_count, p_default_price_minor, coalesce(p_is_membership_included, false), auth.uid(),
    p_image_url, coalesce(p_program_type, 'GROUP'), p_min_capacity, coalesce(p_program_structure, '{}'),
    nullif(trim(coalesce(p_session_format, '')), ''), p_sessions_per_week, p_start_date, p_end_date,
    coalesce(p_payment_mode, 'OFFLINE'), p_early_bird_discount_minor, p_discount_valid_till, p_tax_percent,
    nullif(trim(coalesce(p_payment_notes, '')), ''), coalesce(p_allow_waitlist, true),
    coalesce(p_allow_trial_session, false), coalesce(p_auto_enroll_next_batch, false),
    coalesce(p_send_notifications, true), coalesce(p_visible_in_booking, false), p_enrollment_deadline,
    coalesce(p_status, 'ACTIVE')
  )
  returning * into result;

  perform log_coaching_event(p_facility_id, 'PROGRAM_CREATED',
    'Program created: ' || result.name, null, result.id);
  return result;
exception when unique_violation then
  raise exception 'A program with this name already exists.' using errcode = '23505';
end;
$$;

grant execute on function create_coaching_program(
  uuid, text, text, text, text, text, uuid, integer, integer, integer, integer, boolean,
  text, text, integer, text[], text, integer, date, date, text, integer, date, numeric, text,
  boolean, boolean, boolean, boolean, boolean, date, text
) to authenticated;


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
  p_status text default null,
  p_image_url text default null,
  p_program_type text default null,
  p_min_capacity integer default null,
  p_program_structure text[] default null,
  p_session_format text default null,
  p_sessions_per_week integer default null,
  p_start_date date default null,
  p_end_date date default null,
  p_payment_mode text default null,
  p_early_bird_discount_minor integer default null,
  p_discount_valid_till date default null,
  p_tax_percent numeric default null,
  p_payment_notes text default null,
  p_allow_waitlist boolean default null,
  p_allow_trial_session boolean default null,
  p_auto_enroll_next_batch boolean default null,
  p_send_notifications boolean default null,
  p_visible_in_booking boolean default null,
  p_enrollment_deadline date default null
) returns coaching_programs
language plpgsql
security definer
set search_path = public
as $$
declare
  result coaching_programs;
  v_pricing_touched boolean := (p_default_price_minor is not null or p_is_membership_included is not null);
  v_active_enrollments integer;
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
  if p_status is not null and p_status not in ('DRAFT', 'ACTIVE', 'PAUSED', 'COMPLETED', 'ARCHIVED', 'INACTIVE') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  if p_default_capacity is not null then
    select count(*) into v_active_enrollments from coaching_enrollments where program_id = p_program_id and status = 'ACTIVE';
    if p_default_capacity < v_active_enrollments then
      raise exception 'Maximum capacity cannot be lower than the current enrollment of %.', v_active_enrollments
        using errcode = '23514';
    end if;
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
    status = coalesce(p_status, status),
    image_url = coalesce(p_image_url, image_url),
    program_type = coalesce(p_program_type, program_type),
    min_capacity = coalesce(p_min_capacity, min_capacity),
    program_structure = coalesce(p_program_structure, program_structure),
    session_format = coalesce(nullif(trim(coalesce(p_session_format, '')), ''), session_format),
    sessions_per_week = coalesce(p_sessions_per_week, sessions_per_week),
    start_date = coalesce(p_start_date, start_date),
    end_date = coalesce(p_end_date, end_date),
    payment_mode = coalesce(p_payment_mode, payment_mode),
    early_bird_discount_minor = coalesce(p_early_bird_discount_minor, early_bird_discount_minor),
    discount_valid_till = coalesce(p_discount_valid_till, discount_valid_till),
    tax_percent = coalesce(p_tax_percent, tax_percent),
    payment_notes = coalesce(p_payment_notes, payment_notes),
    allow_waitlist = coalesce(p_allow_waitlist, allow_waitlist),
    allow_trial_session = coalesce(p_allow_trial_session, allow_trial_session),
    auto_enroll_next_batch = coalesce(p_auto_enroll_next_batch, auto_enroll_next_batch),
    send_notifications = coalesce(p_send_notifications, send_notifications),
    visible_in_booking = coalesce(p_visible_in_booking, visible_in_booking),
    enrollment_deadline = coalesce(p_enrollment_deadline, enrollment_deadline)
  where id = p_program_id
  returning * into result;

  perform log_coaching_event(result.facility_id,
    case when p_status = 'ARCHIVED' then 'PROGRAM_ARCHIVED'
         when p_status = 'PAUSED' then 'PROGRAM_PAUSED'
         when p_status = 'INACTIVE' then 'PROGRAM_DEACTIVATED'
         else 'PROGRAM_UPDATED' end,
    'Program updated: ' || result.name, null, result.id);
  return result;
exception when unique_violation then
  raise exception 'A program with this name already exists.' using errcode = '23505';
end;
$$;

grant execute on function update_coaching_program(
  uuid, text, text, text, text, text, uuid, integer, integer, integer, integer, boolean, text,
  text, text, integer, text[], text, integer, date, date, text, integer, date, numeric, text,
  boolean, boolean, boolean, boolean, boolean, date
) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- create_coaching_program_full — the wizard's "Create Program" submit: the
-- program plus its initial batches, atomically. p_batches is a jsonb array of
-- { courtId, coachId?, name, daysOfWeek, startTime, endTime, capacity } — the
-- same shape the Schedule & Batches step already builds client-side.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function create_coaching_program_full(
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
  p_is_membership_included boolean default false,
  p_image_url text default null,
  p_program_type text default 'GROUP',
  p_min_capacity integer default null,
  p_program_structure text[] default '{}',
  p_session_format text default null,
  p_sessions_per_week integer default null,
  p_start_date date default null,
  p_end_date date default null,
  p_payment_mode text default 'OFFLINE',
  p_early_bird_discount_minor integer default null,
  p_discount_valid_till date default null,
  p_tax_percent numeric default null,
  p_payment_notes text default null,
  p_allow_waitlist boolean default true,
  p_allow_trial_session boolean default false,
  p_auto_enroll_next_batch boolean default false,
  p_send_notifications boolean default true,
  p_visible_in_booking boolean default false,
  p_enrollment_deadline date default null,
  p_status text default 'ACTIVE',
  p_batches jsonb default '[]'::jsonb
) returns coaching_programs
language plpgsql
security definer
set search_path = public
as $$
declare
  result coaching_programs;
  b jsonb;
begin
  result := create_coaching_program(
    p_facility_id, p_name, p_level, p_age_group, p_category, p_description, p_facility_sport_id,
    p_default_duration_minutes, p_default_capacity, p_session_count, p_default_price_minor,
    p_is_membership_included, p_image_url, p_program_type, p_min_capacity, p_program_structure,
    p_session_format, p_sessions_per_week, p_start_date, p_end_date, p_payment_mode,
    p_early_bird_discount_minor, p_discount_valid_till, p_tax_percent, p_payment_notes,
    p_allow_waitlist, p_allow_trial_session, p_auto_enroll_next_batch, p_send_notifications,
    p_visible_in_booking, p_enrollment_deadline, p_status
  );

  if p_batches is not null then
    for b in select * from jsonb_array_elements(p_batches)
    loop
      perform create_coaching_program_batch(
        result.id,
        (b->>'courtId')::uuid,
        b->>'name',
        (select array_agg(x::smallint) from jsonb_array_elements_text(b->'daysOfWeek') x),
        (b->>'startTime')::time,
        (b->>'endTime')::time,
        (b->>'capacity')::integer,
        nullif(b->>'coachId', '')::uuid
      );
    end loop;
  end if;

  -- A single failed batch must not leave a half-created program behind — since
  -- every statement above runs inside this function's own implicit
  -- transaction, an exception raised by create_coaching_program_batch already
  -- rolls the whole call (program insert included) back automatically.
  return result;
end;
$$;

grant execute on function create_coaching_program_full(
  uuid, text, text, text, text, text, uuid, integer, integer, integer, integer, boolean,
  text, text, integer, text[], text, integer, date, date, text, integer, date, numeric, text,
  boolean, boolean, boolean, boolean, boolean, date, text, jsonb
) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Read RPCs — list_coaching_programs / get_coaching_program surface the new
-- fields and batches. list_coaching_programs' output columns changed, so it
-- needs a drop first (create or replace can't change a `returns table` OUT
-- list); get_coaching_program returns jsonb so it can stay a plain replace.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists list_coaching_programs(uuid, text, text, integer, integer);

create or replace function list_coaching_programs(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_facility_sport_id uuid default null,
  p_program_type text default null
)
returns table (
  id uuid,
  name text,
  level text,
  age_group text,
  category text,
  default_duration_minutes integer,
  default_capacity integer,
  session_count integer,
  default_price_minor integer,
  is_membership_included boolean,
  status text,
  image_url text,
  program_type text,
  sports_per_week integer,
  student_count bigint,
  scheduled_session_count bigint,
  batch_count bigint,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  return query
  select
    cp.id, cp.name, cp.level, cp.age_group, cp.category,
    cp.default_duration_minutes, cp.default_capacity, cp.session_count,
    cp.default_price_minor, cp.is_membership_included, cp.status,
    cp.image_url, cp.program_type, cp.sessions_per_week,
    (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')::bigint,
    (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status <> 'CANCELLED')::bigint,
    (select count(*) from coaching_program_batches b where b.program_id = cp.id and b.status = 'ACTIVE')::bigint,
    count(*) over ()::bigint
  from coaching_programs cp
  where cp.facility_id = p_facility_id
    and (p_status is null or cp.status = p_status)
    and (p_facility_sport_id is null or cp.facility_sport_id = p_facility_sport_id)
    and (p_program_type is null or cp.program_type = p_program_type)
    and (p_search is null or trim(p_search) = '' or cp.name ilike '%' || trim(p_search) || '%')
  order by cp.status, cp.name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_coaching_programs(uuid, text, text, integer, integer, uuid, text) to authenticated;


create or replace function get_coaching_program(p_program_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare cp coaching_programs;
begin
  select * into cp from coaching_programs where id = p_program_id;
  if cp.id is null then
    raise exception 'Program not found.' using errcode = 'P0002';
  end if;
  if not has_permission(cp.facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'id', cp.id, 'facilityId', cp.facility_id, 'name', cp.name, 'level', cp.level,
    'ageGroup', cp.age_group, 'category', cp.category, 'description', cp.description,
    'facilitySportId', cp.facility_sport_id,
    'defaultDurationMinutes', cp.default_duration_minutes, 'defaultCapacity', cp.default_capacity,
    'sessionCount', cp.session_count, 'defaultPriceMinor', cp.default_price_minor,
    'isMembershipIncluded', cp.is_membership_included, 'status', cp.status,
    'imageUrl', cp.image_url, 'programType', cp.program_type, 'minCapacity', cp.min_capacity,
    'programStructure', to_jsonb(cp.program_structure), 'sessionFormat', cp.session_format,
    'sessionsPerWeek', cp.sessions_per_week, 'startDate', cp.start_date, 'endDate', cp.end_date,
    'paymentMode', cp.payment_mode, 'earlyBirdDiscountMinor', cp.early_bird_discount_minor,
    'discountValidTill', cp.discount_valid_till, 'taxPercent', cp.tax_percent,
    'paymentNotes', cp.payment_notes, 'allowWaitlist', cp.allow_waitlist,
    'allowTrialSession', cp.allow_trial_session, 'autoEnrollNextBatch', cp.auto_enroll_next_batch,
    'sendNotifications', cp.send_notifications, 'visibleInBooking', cp.visible_in_booking,
    'enrollmentDeadline', cp.enrollment_deadline,
    'createdAt', cp.created_at,
    'batches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name, 'daysOfWeek', b.days_of_week, 'startTime', b.start_time,
        'endTime', b.end_time, 'capacity', b.capacity, 'status', b.status,
        'courtId', b.court_id, 'courtName', c.name,
        'coachId', b.coach_id, 'coachName', pr.full_name
      ) order by b.created_at)
      from coaching_program_batches b
      join courts c on c.id = b.court_id
      left join coaches co on co.id = b.coach_id
      left join profiles pr on pr.id = co.user_id
      where b.program_id = cp.id
    ), '[]'::jsonb),
    'stats', jsonb_build_object(
      'activeStudents', (select count(*) from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE'),
      'totalEnrollments', (select count(*) from coaching_enrollments e where e.program_id = cp.id),
      'scheduledSessions', (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status in ('SCHEDULED','CONFIRMED')),
      'completedSessions', (select count(*) from coaching_sessions cs where cs.program_id = cp.id and cs.status = 'COMPLETED')
    )
  );
end;
$$;

grant execute on function get_coaching_program(uuid) to authenticated;
