-- ═══════════════════════════════════════════════════════════════════════════
-- Coaching sessions, generated from the program — not typed in one by one.
--
-- RULES
--   1. A program only produces sessions if it has a START DATE and an END DATE (the limit).
--   2. Its sessions are only shown once the start date is today or in the past.
--   3. It must have at least one ACTIVE student.
--   4. Every program has a limit: each active batch (days of the week, a time, a court, a coach)
--      contributes one session per matching day between the start and end dates. Three days a week
--      for three months = 36 sessions. That number is stored on the program (planned_sessions) and
--      the sessions themselves are stored as coaching_sessions rows (today onward — past days are
--      never invented).
--   5. Once the program has ended no more sessions are created. If the end date is pushed out, the
--      extra days are created; if it is pulled in, later scheduled sessions are cancelled.
--
-- Generation is idempotent (sync_coaching_program_sessions can be re-run safely) and is triggered by
-- anything that can change the answer: the program's dates / status, its batches, its enrollments.
-- A failure inside a trigger is logged as a warning and never blocks the write that caused it.
--
-- The Coaching overview now reports ACTIVE SESSIONS (today's scheduled, active-status sessions) and
-- only the next two upcoming sessions; the session list hides a program's sessions until the program
-- has started and has a student.
-- ═══════════════════════════════════════════════════════════════════════════

alter table coaching_sessions add column if not exists batch_id uuid
  references coaching_program_batches (id) on delete set null;
-- One session per batch per start time — what makes generation safe to repeat.
create unique index if not exists coaching_sessions_batch_start_uidx
  on coaching_sessions (batch_id, start_at) where batch_id is not null;

alter table coaching_programs add column if not exists planned_sessions integer
  check (planned_sessions is null or planned_sessions >= 0);


-- ─────────────────────────────────────────────────────────────────────────
-- sync_coaching_program_sessions — (re)computes the program's session limit and materializes its
-- remaining sessions. Returns how many sessions it created.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function sync_coaching_program_sessions(p_program_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  prog coaching_programs;
  v_tz text;
  v_today date;
  v_planned integer;
  v_created integer := 0;
  v_batch coaching_program_batches;
  v_day date;
  v_start timestamptz;
  v_end timestamptz;
begin
  select * into prog from coaching_programs where id = p_program_id;
  if prog.id is null then
    return 0;
  end if;

  v_tz := coalesce((select f.timezone from facilities f where f.id = prog.facility_id), 'Asia/Kolkata');
  v_today := (now() at time zone v_tz)::date;

  -- Rule 1 / 4: no start or no end date means no limit, so nothing is planned or generated.
  if prog.start_date is null or prog.end_date is null then
    update coaching_programs set planned_sessions = null where id = prog.id and planned_sessions is not null;
    return 0;
  end if;

  -- The limit: one session per active batch per matching day between the start and end dates.
  select count(*)::integer into v_planned
  from coaching_program_batches pb
  cross join generate_series(prog.start_date::timestamp, prog.end_date::timestamp, interval '1 day') as gs(d)
  where pb.program_id = prog.id
    and pb.status = 'ACTIVE'
    and extract(dow from gs.d)::smallint = any (pb.days_of_week);

  update coaching_programs set planned_sessions = v_planned
  where id = prog.id and planned_sessions is distinct from v_planned;

  -- Rule 5 (shortened): sessions past the (possibly pulled-in) end date are cancelled, not deleted.
  update coaching_sessions cs
  set status = 'CANCELLED', cancelled_at = now(), cancel_reason = 'The program end date was changed.'
  where cs.program_id = prog.id
    and cs.batch_id is not null
    and cs.status in ('SCHEDULED', 'CONFIRMED')
    and cs.start_at >= ((prog.end_date + 1)::timestamp at time zone v_tz);

  -- Rules 2, 3, 5: only a started, still-running, ACTIVE program with a student gets sessions.
  if prog.status <> 'ACTIVE'
     or prog.start_date > v_today
     or prog.end_date < v_today
     or not exists (
       select 1 from coaching_enrollments e where e.program_id = prog.id and e.status = 'ACTIVE'
     ) then
    return 0;
  end if;

  for v_batch in
    select pb.* from coaching_program_batches pb
    where pb.program_id = prog.id and pb.status = 'ACTIVE' and pb.coach_id is not null
  loop
    -- Same lock the booking / session writers take, so a booking and a generated session for this
    -- court can't be created at the same instant.
    perform pg_advisory_xact_lock(_coaching_court_lock_key(v_batch.court_id));

    for v_day in
      select gs.d::date
      from generate_series(greatest(prog.start_date, v_today)::timestamp, prog.end_date::timestamp, interval '1 day') as gs(d)
      where extract(dow from gs.d)::smallint = any (v_batch.days_of_week)
    loop
      v_start := (v_day + v_batch.start_time) at time zone v_tz;
      v_end := (v_day + v_batch.end_time) at time zone v_tz;

      -- Earlier today and already over.
      continue when v_end <= now();
      -- A booking already holds the court: that occurrence is skipped, not forced.
      continue when court_has_overlapping_booking(v_batch.court_id, v_start, v_end);

      -- DO NOTHING without a target also swallows the court / coach exclusion constraints, so a
      -- clash with another session just leaves that day out.
      insert into coaching_sessions (
        facility_id, program_id, coach_id, court_id, start_at, end_at, capacity, status, batch_id
      ) values (
        prog.facility_id, prog.id, v_batch.coach_id, v_batch.court_id, v_start, v_end,
        least(greatest(v_batch.capacity, 1), 100), 'SCHEDULED', v_batch.id
      )
      on conflict do nothing;
      if found then
        v_created := v_created + 1;
      end if;
    end loop;
  end loop;

  -- Put every active student on the upcoming sessions of their batch (students without a batch join
  -- all of them). A student removed from a session stays removed: the unique key keeps that row.
  insert into coaching_session_students (session_id, enrollment_id, facility_id, status)
  select cs.id, e.id, prog.facility_id, 'ENROLLED'
  from coaching_sessions cs
  join coaching_enrollments e
    on e.program_id = cs.program_id
   and e.status = 'ACTIVE'
   and (e.batch_id = cs.batch_id or e.batch_id is null)
  where cs.program_id = prog.id
    and cs.batch_id is not null
    and cs.status in ('SCHEDULED', 'CONFIRMED')
    and cs.start_at >= now()
  on conflict (session_id, enrollment_id) do nothing;

  return v_created;
end;
$$;

-- Maintenance / trigger use only; clients never call it directly.
revoke all on function sync_coaching_program_sessions(uuid) from public, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Triggers — anything that can change what a program's sessions should be.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function _coaching_sync_after_program()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform sync_coaching_program_sessions(new.id);
  exception when others then
    raise warning 'coaching session sync failed for program %: %', new.id, sqlerrm;
  end;
  return null;
end;
$$;

create or replace function _coaching_sync_after_batch()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_program uuid;
begin
  if tg_op = 'DELETE' then
    v_program := old.program_id;
  else
    v_program := new.program_id;
  end if;
  begin
    perform sync_coaching_program_sessions(v_program);
  exception when others then
    raise warning 'coaching session sync failed for program %: %', v_program, sqlerrm;
  end;
  return null;
end;
$$;

create or replace function _coaching_sync_after_enrollment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform sync_coaching_program_sessions(new.program_id);
  exception when others then
    raise warning 'coaching session sync failed for program %: %', new.program_id, sqlerrm;
  end;
  return null;
end;
$$;

drop trigger if exists coaching_programs_sync_sessions on coaching_programs;
create trigger coaching_programs_sync_sessions
  after insert or update of start_date, end_date, status on coaching_programs
  for each row execute function _coaching_sync_after_program();

drop trigger if exists coaching_program_batches_sync_sessions on coaching_program_batches;
create trigger coaching_program_batches_sync_sessions
  after insert or update or delete on coaching_program_batches
  for each row execute function _coaching_sync_after_batch();

drop trigger if exists coaching_enrollments_sync_sessions on coaching_enrollments;
create trigger coaching_enrollments_sync_sessions
  after insert or update of status, batch_id on coaching_enrollments
  for each row execute function _coaching_sync_after_enrollment();


-- ─────────────────────────────────────────────────────────────────────────
-- The session list hides a program's sessions until the program has started and has an active
-- student (rules 2 and 3). Ad-hoc sessions (no program) are always shown.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists list_coaching_sessions(uuid, timestamptz, timestamptz, uuid, uuid, uuid, text, integer, integer);

create or replace function list_coaching_sessions(
  p_facility_id uuid,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_coach_id uuid default null,
  p_program_id uuid default null,
  p_court_id uuid default null,
  p_status text default null,
  p_limit integer default 200,
  p_offset integer default 0
)
returns table (
  id uuid,
  program_id uuid,
  program_name text,
  coach_id uuid,
  coach_name text,
  court_id uuid,
  court_name text,
  start_at timestamptz,
  end_at timestamptz,
  capacity integer,
  enrolled_count bigint,
  status text,
  session_type text,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date;
begin
  if not has_permission(p_facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  v_today := (now() at time zone coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata'))::date;
  return query
  select
    cs.id, cs.program_id, coalesce(cp.name, cs.title, 'Coaching Session'), cs.coach_id, pr.full_name, cs.court_id, c.name,
    cs.start_at, cs.end_at, cs.capacity,
    (select count(*) from coaching_session_students css where css.session_id = cs.id and css.status = 'ENROLLED')::bigint,
    cs.status, cs.session_type,
    count(*) over ()::bigint
  from coaching_sessions cs
  left join coaching_programs cp on cp.id = cs.program_id
  join coaches co on co.id = cs.coach_id
  join profiles pr on pr.id = co.user_id
  join courts c on c.id = cs.court_id
  where cs.facility_id = p_facility_id
    and (
      cs.program_id is null
      or (
        cp.start_date is not null
        and cp.start_date <= v_today
        and exists (select 1 from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')
      )
    )
    and (p_from is null or cs.end_at >= p_from)
    and (p_to is null or cs.start_at < p_to)
    and (p_coach_id is null or cs.coach_id = p_coach_id)
    and (p_program_id is null or cs.program_id = p_program_id)
    and (p_court_id is null or cs.court_id = p_court_id)
    and (p_status is null or cs.status = p_status)
  order by cs.start_at
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_coaching_sessions(uuid, timestamptz, timestamptz, uuid, uuid, uuid, text, integer, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- The overview: "Active Sessions" and the next two upcoming sessions. The existing overview function
-- is kept as the base (everything else on the page is unchanged) and wrapped.
-- ─────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_proc where proname = '_get_coaching_overview_base') then
    alter function get_coaching_overview(uuid) rename to _get_coaching_overview_base;
  end if;
end $$;

create or replace function get_coaching_overview(p_facility_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base jsonb;
  v_tz text;
  v_today date;
  v_day tstzrange;
  v_active integer;
  v_upcoming jsonb;
begin
  -- The base function does the permission check.
  v_base := _get_coaching_overview_base(p_facility_id);

  v_tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  v_today := (now() at time zone v_tz)::date;
  v_day := tstzrange(v_today::timestamp at time zone v_tz, (v_today + 1)::timestamp at time zone v_tz);

  -- Active sessions: today's sessions that are scheduled and in an active status.
  select count(*)::integer into v_active
  from coaching_sessions cs
  left join coaching_programs cp on cp.id = cs.program_id
  where cs.facility_id = p_facility_id
    and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS')
    and v_day @> cs.start_at
    and (
      cs.program_id is null
      or (
        cp.start_date is not null
        and cp.start_date <= v_today
        and exists (select 1 from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')
      )
    );

  -- The next two sessions still to happen, today or on a later day.
  select coalesce(jsonb_agg(r.row order by r.start_at), '[]'::jsonb) into v_upcoming
  from (
    select cs.start_at,
      jsonb_build_object(
        'id', cs.id,
        'startAt', cs.start_at,
        'endAt', cs.end_at,
        'programName', coalesce(cp.name, cs.title, 'Coaching Session'),
        'coachName', pr.full_name,
        'courtName', c.name,
        'enrolled', (select count(*) from coaching_session_students css where css.session_id = cs.id and css.status = 'ENROLLED'),
        'capacity', cs.capacity,
        'status', cs.status
      ) as row
    from coaching_sessions cs
    left join coaching_programs cp on cp.id = cs.program_id
    join coaches co on co.id = cs.coach_id
    join profiles pr on pr.id = co.user_id
    join courts c on c.id = cs.court_id
    where cs.facility_id = p_facility_id
      and cs.status in ('SCHEDULED', 'CONFIRMED')
      and cs.start_at >= now()
      and (
        cs.program_id is null
        or (
          cp.start_date is not null
          and cp.start_date <= v_today
          and exists (select 1 from coaching_enrollments e where e.program_id = cp.id and e.status = 'ACTIVE')
        )
      )
    order by cs.start_at
    limit 2
  ) r;

  return jsonb_set(
    jsonb_set(v_base, '{kpis,activeSessions}', to_jsonb(v_active), true),
    '{upcomingSessions}', v_upcoming, true
  );
end;
$$;

grant execute on function get_coaching_overview(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Backfill: existing programs that already have dates, a batch and a student get their sessions now.
-- ─────────────────────────────────────────────────────────────────────────
do $$
declare
  r record;
begin
  for r in select id from coaching_programs where start_date is not null and end_date is not null loop
    begin
      perform sync_coaching_program_sessions(r.id);
    exception when others then
      raise warning 'coaching session backfill failed for program %: %', r.id, sqlerrm;
    end;
  end loop;
end $$;
