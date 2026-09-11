-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching enrollments, session rosters, and student progress.
--
--   coaching_enrollments      — an existing member's participation in a
--                               program (spec §19-§22). Never a new account.
--   coaching_session_students — which enrolled students are on a session's
--                               roster (referenced by 0083's RPCs at runtime).
--   student_progress_notes    — lightweight per-student progress (spec §32).
--                               No health/biometric data; permission-gated.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- coaching_enrollments
-- ─────────────────────────────────────────────────────────────────────────
create table coaching_enrollments (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  member_id uuid not null references members (id) on delete restrict,
  program_id uuid not null references coaching_programs (id) on delete restrict,
  coach_id uuid references coaches (id) on delete set null,
  start_date date not null default current_date,
  end_date date,
  sessions_total integer check (sessions_total is null or sessions_total >= 1),
  -- The coaching fee for this enrollment, in minor units (paise). This is the
  -- obligation total; revenue is recognised only through payments (0085).
  price_minor integer not null default 0 check (price_minor >= 0),
  pricing_type text not null default 'STANDARD'
    check (pricing_type in ('STANDARD', 'CUSTOM', 'MEMBERSHIP_INCLUDED')),
  status text not null default 'ACTIVE'
    check (status in ('ACTIVE', 'PAUSED', 'COMPLETED', 'CANCELLED')),
  notes text,
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancel_reason text,
  constraint coaching_enrollments_date_check check (end_date is null or end_date >= start_date)
);

-- One live enrollment per member per program (spec §20 / §75 duplicate rule).
create unique index coaching_enrollments_one_active
  on coaching_enrollments (facility_id, member_id, program_id)
  where status in ('ACTIVE', 'PAUSED');

create index coaching_enrollments_facility_status_idx on coaching_enrollments (facility_id, status);
create index coaching_enrollments_program_idx on coaching_enrollments (program_id);
create index coaching_enrollments_member_idx on coaching_enrollments (member_id);

alter table coaching_enrollments enable row level security;
drop policy if exists "coaching_enrollments_select" on coaching_enrollments;
create policy "coaching_enrollments_select" on coaching_enrollments for select
  using (has_permission(facility_id, 'COACHING_VIEW'));

drop trigger if exists coaching_enrollments_set_updated_at on coaching_enrollments;
create trigger coaching_enrollments_set_updated_at
  before update on coaching_enrollments
  for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- coaching_session_students — the per-session roster (spec §17 / §24).
-- REMOVED rows are kept so a dropped-then-re-added student is one row.
-- ─────────────────────────────────────────────────────────────────────────
create table coaching_session_students (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references coaching_sessions (id) on delete cascade,
  enrollment_id uuid not null references coaching_enrollments (id) on delete restrict,
  facility_id uuid not null references facilities (id) on delete cascade,
  status text not null default 'ENROLLED' check (status in ('ENROLLED', 'REMOVED')),
  added_by uuid references profiles (id) on delete set null,
  added_at timestamptz not null default now(),
  unique (session_id, enrollment_id)
);

create index coaching_session_students_session_idx on coaching_session_students (session_id) where status = 'ENROLLED';
create index coaching_session_students_enrollment_idx on coaching_session_students (enrollment_id);

alter table coaching_session_students enable row level security;
drop policy if exists "coaching_session_students_select" on coaching_session_students;
create policy "coaching_session_students_select" on coaching_session_students for select
  using (has_permission(facility_id, 'COACHING_VIEW'));


-- ─────────────────────────────────────────────────────────────────────────
-- student_progress_notes — spec §32. Lightweight; read gated on
-- COACHING_VIEW_PROGRESS, write on COACHING_MANAGE_PROGRESS (spec §34).
-- ─────────────────────────────────────────────────────────────────────────
create table student_progress_notes (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  enrollment_id uuid not null references coaching_enrollments (id) on delete cascade,
  session_id uuid references coaching_sessions (id) on delete set null,
  coach_id uuid references coaches (id) on delete set null,
  skill_or_goal text,
  note text not null,
  progress_status text not null default 'ON_TRACK'
    check (progress_status in ('ON_TRACK', 'NEEDS_WORK', 'EXCELLING', 'AT_RISK')),
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index student_progress_notes_enrollment_idx on student_progress_notes (enrollment_id, created_at desc);
create index student_progress_notes_session_idx on student_progress_notes (session_id) where session_id is not null;

alter table student_progress_notes enable row level security;
drop policy if exists "student_progress_notes_select" on student_progress_notes;
create policy "student_progress_notes_select" on student_progress_notes for select
  using (has_permission(facility_id, 'COACHING_VIEW_PROGRESS'));

drop trigger if exists student_progress_notes_set_updated_at on student_progress_notes;
create trigger student_progress_notes_set_updated_at
  before update on student_progress_notes
  for each row execute function set_updated_at();


-- ═════════════════════════════════════════════════════════════════════════
-- Enrollment write RPCs.
-- ═════════════════════════════════════════════════════════════════════════
create or replace function create_coaching_enrollment(
  p_facility_id uuid,
  p_member_id uuid,
  p_program_id uuid,
  p_coach_id uuid default null,
  p_start_date date default null,
  p_end_date date default null,
  p_sessions_total integer default null,
  p_price_minor integer default null,
  p_pricing_type text default null,
  p_notes text default null
) returns coaching_enrollments
language plpgsql
security definer
set search_path = public
as $$
declare
  result coaching_enrollments;
  v_program coaching_programs;
  v_price integer;
  v_pricing text;
begin
  if not has_permission(p_facility_id, 'COACHING_MANAGE_ENROLLMENTS') then
    raise exception 'You don''t have permission to manage enrollments.' using errcode = '42501';
  end if;

  if not exists (select 1 from members where id = p_member_id and facility_id = p_facility_id) then
    raise exception 'That member does not belong to this facility.' using errcode = '23503';
  end if;

  select * into v_program from coaching_programs where id = p_program_id and facility_id = p_facility_id;
  if v_program.id is null then
    raise exception 'That program does not belong to this facility.' using errcode = '23503';
  end if;
  if v_program.status <> 'ACTIVE' then
    raise exception 'That program is not active.' using errcode = '23514';
  end if;

  if p_coach_id is not null
     and not exists (select 1 from coaches where id = p_coach_id and facility_id = p_facility_id) then
    raise exception 'That coach does not belong to this facility.' using errcode = '23503';
  end if;

  -- Resolve the fee. A price override or a non-standard pricing type needs
  -- the pricing permission (spec §25 / §36).
  v_pricing := coalesce(p_pricing_type,
    case when v_program.is_membership_included then 'MEMBERSHIP_INCLUDED' else 'STANDARD' end);
  if v_pricing = 'MEMBERSHIP_INCLUDED' then
    v_price := 0;
  elsif p_price_minor is not null then
    if p_price_minor <> coalesce(v_program.default_price_minor, -1)
       and not has_permission(p_facility_id, 'COACHING_MANAGE_PRICING') then
      raise exception 'You don''t have permission to override coaching pricing.' using errcode = '42501';
    end if;
    v_price := p_price_minor;
  else
    v_price := coalesce(v_program.default_price_minor, 0);
  end if;
  if v_pricing = 'CUSTOM' and not has_permission(p_facility_id, 'COACHING_MANAGE_PRICING') then
    raise exception 'You don''t have permission to override coaching pricing.' using errcode = '42501';
  end if;

  begin
    insert into coaching_enrollments (
      facility_id, member_id, program_id, coach_id, start_date, end_date,
      sessions_total, price_minor, pricing_type, notes, created_by
    ) values (
      p_facility_id, p_member_id, p_program_id, p_coach_id,
      coalesce(p_start_date, current_date), p_end_date,
      coalesce(p_sessions_total, v_program.session_count),
      greatest(v_price, 0), v_pricing,
      nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
    ) returning * into result;
  exception when unique_violation then
    raise exception 'This member already has an active enrollment in this program.' using errcode = '23505';
  end;

  perform log_coaching_event(p_facility_id, 'ENROLLMENT_CREATED', 'Member enrolled in ' || v_program.name,
    p_coach_id, p_program_id, null, result.id,
    jsonb_build_object('memberId', p_member_id, 'priceMinor', result.price_minor));
  return result;
end;
$$;

grant execute on function create_coaching_enrollment(uuid, uuid, uuid, uuid, date, date, integer, integer, text, text) to authenticated;


create or replace function update_coaching_enrollment(
  p_enrollment_id uuid,
  p_coach_id uuid default null,
  p_start_date date default null,
  p_end_date date default null,
  p_sessions_total integer default null,
  p_price_minor integer default null,
  p_notes text default null
) returns coaching_enrollments
language plpgsql
security definer
set search_path = public
as $$
declare result coaching_enrollments;
begin
  select * into result from coaching_enrollments where id = p_enrollment_id;
  if result.id is null then
    raise exception 'Enrollment not found.' using errcode = 'P0002';
  end if;
  if not has_permission(result.facility_id, 'COACHING_MANAGE_ENROLLMENTS') then
    raise exception 'You don''t have permission to manage enrollments.' using errcode = '42501';
  end if;
  if p_price_minor is not null and p_price_minor <> result.price_minor
     and not has_permission(result.facility_id, 'COACHING_MANAGE_PRICING') then
    raise exception 'You don''t have permission to change coaching pricing.' using errcode = '42501';
  end if;

  update coaching_enrollments set
    coach_id = coalesce(p_coach_id, coach_id),
    start_date = coalesce(p_start_date, start_date),
    end_date = coalesce(p_end_date, end_date),
    sessions_total = coalesce(p_sessions_total, sessions_total),
    price_minor = coalesce(greatest(p_price_minor, 0), price_minor),
    notes = coalesce(p_notes, notes)
  where id = p_enrollment_id
  returning * into result;

  perform log_coaching_event(result.facility_id, 'ENROLLMENT_UPDATED', 'Enrollment updated',
    result.coach_id, result.program_id, null, result.id);
  return result;
end;
$$;

grant execute on function update_coaching_enrollment(uuid, uuid, date, date, integer, integer, text) to authenticated;


-- set_coaching_enrollment_status — pause / resume / complete / cancel. The
-- historical row is never deleted (spec §54); a cancellation records a
-- reason. Financial consequences stay with existing Finance / refunds.
create or replace function set_coaching_enrollment_status(
  p_enrollment_id uuid,
  p_status text,
  p_reason text default null
) returns coaching_enrollments
language plpgsql
security definer
set search_path = public
as $$
declare
  e coaching_enrollments;
  result coaching_enrollments;
begin
  select * into e from coaching_enrollments where id = p_enrollment_id;
  if e.id is null then
    raise exception 'Enrollment not found.' using errcode = 'P0002';
  end if;
  if not has_permission(e.facility_id, 'COACHING_MANAGE_ENROLLMENTS') then
    raise exception 'You don''t have permission to manage enrollments.' using errcode = '42501';
  end if;
  if p_status not in ('ACTIVE', 'PAUSED', 'COMPLETED', 'CANCELLED') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;
  if p_status = 'CANCELLED' and trim(coalesce(p_reason, '')) = '' then
    raise exception 'A cancellation reason is required.' using errcode = '23514';
  end if;

  begin
    update coaching_enrollments set
      status = p_status,
      cancelled_at = case when p_status = 'CANCELLED' then now() else cancelled_at end,
      cancel_reason = case when p_status = 'CANCELLED' then trim(p_reason) else cancel_reason end
    where id = p_enrollment_id
    returning * into result;
  exception when unique_violation then
    raise exception 'This member already has an active enrollment in this program.' using errcode = '23505';
  end;

  -- Take a cancelled/completed student off future session rosters.
  if p_status in ('CANCELLED', 'COMPLETED') then
    update coaching_session_students css
      set status = 'REMOVED'
      from coaching_sessions cs
      where css.session_id = cs.id
        and css.enrollment_id = p_enrollment_id
        and css.status = 'ENROLLED'
        and cs.status in ('SCHEDULED', 'CONFIRMED');
  end if;

  perform log_coaching_event(result.facility_id,
    case p_status
      when 'CANCELLED' then 'ENROLLMENT_CANCELLED'
      when 'COMPLETED' then 'ENROLLMENT_COMPLETED'
      when 'PAUSED' then 'ENROLLMENT_PAUSED'
      else 'ENROLLMENT_UPDATED'
    end,
    'Enrollment ' || lower(p_status), result.coach_id, result.program_id, null, result.id);
  return result;
end;
$$;

grant execute on function set_coaching_enrollment_status(uuid, text, text) to authenticated;


-- ═════════════════════════════════════════════════════════════════════════
-- Session roster — add / remove a student. Capacity is checked under a lock
-- on the session row so two concurrent adds to the last free seat can't both
-- succeed (spec §15 / §52).
-- ═════════════════════════════════════════════════════════════════════════
create or replace function add_session_student(p_session_id uuid, p_enrollment_id uuid)
returns coaching_session_students
language plpgsql
security definer
set search_path = public
as $$
declare
  s coaching_sessions;
  e coaching_enrollments;
  v_count integer;
  v_existing coaching_session_students;
  result coaching_session_students;
begin
  select * into s from coaching_sessions where id = p_session_id for update;
  if s.id is null then
    raise exception 'Session not found.' using errcode = 'P0002';
  end if;
  if not has_permission(s.facility_id, 'COACHING_EDIT_SESSION') then
    raise exception 'You don''t have permission to edit this session''s roster.' using errcode = '42501';
  end if;
  if s.status in ('COMPLETED', 'CANCELLED') then
    raise exception 'This session is % — its roster is closed.', lower(s.status) using errcode = '23514';
  end if;

  select * into e from coaching_enrollments where id = p_enrollment_id;
  if e.id is null or e.facility_id <> s.facility_id then
    raise exception 'That enrollment does not belong to this facility.' using errcode = '23503';
  end if;
  if e.program_id <> s.program_id then
    raise exception 'That student is enrolled in a different program.' using errcode = '23514';
  end if;
  if e.status <> 'ACTIVE' then
    raise exception 'That enrollment is not active.' using errcode = '23514';
  end if;

  select * into v_existing from coaching_session_students
    where session_id = p_session_id and enrollment_id = p_enrollment_id;
  if v_existing.id is not null and v_existing.status = 'ENROLLED' then
    return v_existing;
  end if;

  select count(*) into v_count from coaching_session_students
    where session_id = p_session_id and status = 'ENROLLED';
  if v_count >= s.capacity then
    raise exception 'This session is full (% / % students).', v_count, s.capacity using errcode = '23514';
  end if;

  if v_existing.id is not null then
    update coaching_session_students set status = 'ENROLLED', added_by = auth.uid(), added_at = now()
      where id = v_existing.id returning * into result;
  else
    insert into coaching_session_students (session_id, enrollment_id, facility_id, added_by)
      values (p_session_id, p_enrollment_id, s.facility_id, auth.uid())
      returning * into result;
  end if;

  perform log_coaching_event(s.facility_id, 'SESSION_STUDENT_ADDED', 'Student added to session',
    s.coach_id, s.program_id, s.id, p_enrollment_id);
  return result;
end;
$$;

grant execute on function add_session_student(uuid, uuid) to authenticated;


create or replace function remove_session_student(p_session_id uuid, p_enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare s coaching_sessions;
begin
  select * into s from coaching_sessions where id = p_session_id;
  if s.id is null then
    raise exception 'Session not found.' using errcode = 'P0002';
  end if;
  if not has_permission(s.facility_id, 'COACHING_EDIT_SESSION') then
    raise exception 'You don''t have permission to edit this session''s roster.' using errcode = '42501';
  end if;

  update coaching_session_students set status = 'REMOVED'
    where session_id = p_session_id and enrollment_id = p_enrollment_id and status = 'ENROLLED';

  perform log_coaching_event(s.facility_id, 'SESSION_STUDENT_REMOVED', 'Student removed from session',
    s.coach_id, s.program_id, s.id, p_enrollment_id);
end;
$$;

grant execute on function remove_session_student(uuid, uuid) to authenticated;


-- ═════════════════════════════════════════════════════════════════════════
-- Student progress notes — gated COACHING_MANAGE_PROGRESS.
-- ═════════════════════════════════════════════════════════════════════════
create or replace function add_progress_note(
  p_enrollment_id uuid,
  p_note text,
  p_skill_or_goal text default null,
  p_progress_status text default 'ON_TRACK',
  p_session_id uuid default null
) returns student_progress_notes
language plpgsql
security definer
set search_path = public
as $$
declare
  e coaching_enrollments;
  v_coach uuid;
  result student_progress_notes;
begin
  select * into e from coaching_enrollments where id = p_enrollment_id;
  if e.id is null then
    raise exception 'Enrollment not found.' using errcode = 'P0002';
  end if;
  if not has_permission(e.facility_id, 'COACHING_MANAGE_PROGRESS') then
    raise exception 'You don''t have permission to record student progress.' using errcode = '42501';
  end if;
  if trim(coalesce(p_note, '')) = '' then
    raise exception 'A progress note cannot be empty.' using errcode = '23514';
  end if;
  if coalesce(p_progress_status, 'ON_TRACK') not in ('ON_TRACK', 'NEEDS_WORK', 'EXCELLING', 'AT_RISK') then
    raise exception 'Unknown progress status.' using errcode = '22023';
  end if;
  if p_session_id is not null
     and not exists (select 1 from coaching_sessions where id = p_session_id and facility_id = e.facility_id) then
    raise exception 'That session does not belong to this facility.' using errcode = '23503';
  end if;

  select id into v_coach from coaches where facility_id = e.facility_id and user_id = auth.uid();

  insert into student_progress_notes (
    facility_id, enrollment_id, session_id, coach_id, skill_or_goal, note, progress_status, created_by
  ) values (
    e.facility_id, p_enrollment_id, p_session_id, coalesce(v_coach, e.coach_id),
    nullif(trim(coalesce(p_skill_or_goal, '')), ''), trim(p_note),
    coalesce(p_progress_status, 'ON_TRACK'), auth.uid()
  ) returning * into result;

  perform log_coaching_event(e.facility_id, 'PROGRESS_NOTE_ADDED', 'Progress note added',
    result.coach_id, e.program_id, p_session_id, p_enrollment_id);
  return result;
end;
$$;

grant execute on function add_progress_note(uuid, text, text, text, uuid) to authenticated;


create or replace function update_progress_note(
  p_note_id uuid,
  p_note text default null,
  p_skill_or_goal text default null,
  p_progress_status text default null
) returns student_progress_notes
language plpgsql
security definer
set search_path = public
as $$
declare result student_progress_notes;
begin
  select * into result from student_progress_notes where id = p_note_id;
  if result.id is null then
    raise exception 'Progress note not found.' using errcode = 'P0002';
  end if;
  if not has_permission(result.facility_id, 'COACHING_MANAGE_PROGRESS') then
    raise exception 'You don''t have permission to edit student progress.' using errcode = '42501';
  end if;
  if p_progress_status is not null
     and p_progress_status not in ('ON_TRACK', 'NEEDS_WORK', 'EXCELLING', 'AT_RISK') then
    raise exception 'Unknown progress status.' using errcode = '22023';
  end if;

  update student_progress_notes set
    note = coalesce(nullif(trim(coalesce(p_note, '')), ''), note),
    skill_or_goal = coalesce(p_skill_or_goal, skill_or_goal),
    progress_status = coalesce(p_progress_status, progress_status)
  where id = p_note_id
  returning * into result;

  perform log_coaching_event(result.facility_id, 'PROGRESS_NOTE_UPDATED', 'Progress note updated',
    result.coach_id, null, result.session_id, result.enrollment_id);
  return result;
end;
$$;

grant execute on function update_progress_note(uuid, text, text, text) to authenticated;


create or replace function delete_progress_note(p_note_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_facility uuid;
begin
  select facility_id into v_facility from student_progress_notes where id = p_note_id;
  if v_facility is null then return; end if;
  if not has_permission(v_facility, 'COACHING_MANAGE_PROGRESS') then
    raise exception 'You don''t have permission to delete student progress.' using errcode = '42501';
  end if;
  delete from student_progress_notes where id = p_note_id;
end;
$$;

grant execute on function delete_progress_note(uuid) to authenticated;
