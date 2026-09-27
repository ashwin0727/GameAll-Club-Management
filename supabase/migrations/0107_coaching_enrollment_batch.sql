-- ═══════════════════════════════════════════════════════════════════════════
-- Manage Students / Add Student — enrollment becomes batch-scoped.
--
-- Until now coaching_enrollments only recorded (member, program) — a batch
-- is the program's actual day/time/court/coach schedule (0100), and nothing
-- tied a specific enrollment to a specific batch, so "batch capacity" could
-- never be enforced and list_coaching_program_batches' own enrolled_count
-- was a placeholder (every batch under a program showed the same
-- program-wide count). Add student now enrolls into an existing Program +
-- Batch — no new session/booking/finance engine, reusing
-- create_coaching_enrollment and the existing Pending Payments obligation
-- model (payments.coaching_enrollment_id + record_obligation_payment's
-- 'COACHING_ENROLLMENT' branch, both already in place since 0085).
-- ═══════════════════════════════════════════════════════════════════════════

alter table coaching_enrollments add column if not exists batch_id uuid references coaching_program_batches (id) on delete set null;
create index if not exists coaching_enrollments_batch_idx on coaching_enrollments (batch_id) where batch_id is not null;

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
  p_notes text default null,
  p_batch_id uuid default null
) returns coaching_enrollments
language plpgsql
security definer
set search_path = public
as $$
declare
  result coaching_enrollments;
  v_program coaching_programs;
  v_batch coaching_program_batches;
  v_price integer;
  v_pricing text;
  v_batch_enrolled integer;
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

  if p_batch_id is not null then
    select * into v_batch from coaching_program_batches where id = p_batch_id and program_id = p_program_id;
    if v_batch.id is null then
      raise exception 'That batch does not belong to this program.' using errcode = '23503';
    end if;
    if v_batch.status <> 'ACTIVE' then
      raise exception 'That batch is not active.' using errcode = '23514';
    end if;
    -- Lock the batch row for the duration of this transaction so two
    -- concurrent enrollments can't both slip past a one-seat-left check.
    perform 1 from coaching_program_batches where id = p_batch_id for update;
    select count(*) into v_batch_enrolled from coaching_enrollments
      where batch_id = p_batch_id and status in ('ACTIVE', 'PAUSED');
    if v_batch_enrolled >= v_batch.capacity then
      raise exception 'This batch is full.' using errcode = '23514';
    end if;
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
      sessions_total, price_minor, pricing_type, notes, created_by, batch_id
    ) values (
      p_facility_id, p_member_id, p_program_id, p_coach_id,
      coalesce(p_start_date, current_date), p_end_date,
      coalesce(p_sessions_total, v_program.session_count),
      greatest(v_price, 0), v_pricing,
      nullif(trim(coalesce(p_notes, '')), ''), auth.uid(), p_batch_id
    ) returning * into result;
  exception when unique_violation then
    raise exception 'This member already has an active enrollment in this program.' using errcode = '23505';
  end;

  perform log_coaching_event(p_facility_id, 'ENROLLMENT_CREATED', 'Member enrolled in ' || v_program.name,
    p_coach_id, p_program_id, null, result.id,
    jsonb_build_object('memberId', p_member_id, 'priceMinor', result.price_minor, 'batchId', p_batch_id));
  return result;
end;
$$;

grant execute on function create_coaching_enrollment(uuid, uuid, uuid, uuid, date, date, integer, integer, text, text, uuid) to authenticated;

-- list_coaching_enrollments' output gains batch_id/batch_name.
drop function if exists list_coaching_enrollments(uuid, text, uuid, text, integer, integer);

create or replace function list_coaching_enrollments(
  p_facility_id uuid,
  p_search text default null,
  p_program_id uuid default null,
  p_status text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  member_id uuid,
  student_name text,
  student_phone text,
  program_id uuid,
  program_name text,
  coach_name text,
  start_date date,
  end_date date,
  sessions_total integer,
  price_minor integer,
  paid_minor bigint,
  status text,
  payment_status text,
  batch_id uuid,
  batch_name text,
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
  with rows as (
    select
      e.id, e.member_id, m.full_name as student_name, m.phone as student_phone,
      e.program_id, cp.name as program_name, pr.full_name as coach_name,
      e.start_date, e.end_date, e.sessions_total, e.price_minor,
      coalesce((select sum(p.amount_inr) * 100 from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid'), 0)::bigint as paid_minor,
      e.status, e.batch_id, b.name as batch_name
    from coaching_enrollments e
    join members m on m.id = e.member_id
    join coaching_programs cp on cp.id = e.program_id
    left join coaches co on co.id = e.coach_id
    left join profiles pr on pr.id = co.user_id
    left join coaching_program_batches b on b.id = e.batch_id
    where e.facility_id = p_facility_id
      and (p_program_id is null or e.program_id = p_program_id)
      and (p_status is null or e.status = p_status)
      and (
        p_search is null or trim(p_search) = ''
        or m.full_name ilike '%' || trim(p_search) || '%'
        or m.phone ilike '%' || trim(p_search) || '%'
      )
  )
  select
    r.id, r.member_id, r.student_name, r.student_phone, r.program_id, r.program_name, r.coach_name,
    r.start_date, r.end_date, r.sessions_total, r.price_minor, r.paid_minor, r.status,
    case
      when r.price_minor = 0 then 'INCLUDED'
      when r.paid_minor >= r.price_minor then 'PAID'
      when r.paid_minor > 0 then 'PARTIAL'
      else 'PENDING'
    end as payment_status,
    r.batch_id, r.batch_name,
    count(*) over ()::bigint as total_count
  from rows r
  order by r.start_date desc, r.student_name
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_coaching_enrollments(uuid, text, uuid, text, integer, integer) to authenticated;

create or replace function get_coaching_enrollment(p_enrollment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  e coaching_enrollments;
  v_can_progress boolean;
  v_paid bigint;
begin
  select * into e from coaching_enrollments where id = p_enrollment_id;
  if e.id is null then
    raise exception 'Enrollment not found.' using errcode = 'P0002';
  end if;
  if not has_permission(e.facility_id, 'COACHING_VIEW') then
    raise exception 'You don''t have permission to view coaching.' using errcode = '42501';
  end if;
  v_can_progress := has_permission(e.facility_id, 'COACHING_VIEW_PROGRESS');
  select coalesce(sum(p.amount_inr) * 100, 0)::bigint into v_paid
    from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid';

  return (
      jsonb_build_object(
      'id', e.id,
      'facilityId', e.facility_id,
      'memberId', e.member_id,
      'studentName', (select full_name from members where id = e.member_id),
      'studentPhone', (select phone from members where id = e.member_id),
      'studentEmail', (select email from members where id = e.member_id),
      'programId', e.program_id,
      'programName', (select name from coaching_programs where id = e.program_id),
      'programLevel', (select level from coaching_programs where id = e.program_id),
      'coachId', e.coach_id,
      'coachName', (select pr.full_name from coaches co join profiles pr on pr.id = co.user_id where co.id = e.coach_id),
      'batchId', e.batch_id,
      'batchName', (select name from coaching_program_batches where id = e.batch_id),
      'startDate', e.start_date,
      'endDate', e.end_date,
      'sessionsTotal', e.sessions_total,
      'priceMinor', e.price_minor,
      'paidMinor', v_paid,
      'outstandingMinor', greatest(e.price_minor - v_paid, 0),
      'pricingType', e.pricing_type,
      'status', e.status,
      'notes', e.notes,
      'cancelReason', e.cancel_reason,
      'createdAt', e.created_at,
      'sessions', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', cs.id, 'startAt', cs.start_at, 'endAt', cs.end_at,
          'programName', cp2.name, 'courtName', c.name, 'status', cs.status
        ) order by cs.start_at desc)
        from coaching_session_students css
        join coaching_sessions cs on cs.id = css.session_id
        join coaching_programs cp2 on cp2.id = cs.program_id
        join courts c on c.id = cs.court_id
        where css.enrollment_id = e.id and css.status = 'ENROLLED'
      ), '[]'::jsonb),
      'payments', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', p.id, 'amountMinor', (p.amount_inr * 100), 'paidAt', coalesce(p.paid_at, p.created_at),
          'method', p.payment_method, 'reference', p.reference
        ) order by coalesce(p.paid_at, p.created_at) desc)
        from payments p where p.coaching_enrollment_id = e.id and p.status = 'paid'
      ), '[]'::jsonb),
      'progressNotes', case when v_can_progress then coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', spn.id, 'skillOrGoal', spn.skill_or_goal, 'note', spn.note,
          'progressStatus', spn.progress_status, 'coachName', cpr.full_name,
          'sessionId', spn.session_id, 'createdAt', spn.created_at
        ) order by spn.created_at desc)
        from student_progress_notes spn
        left join coaches sco on sco.id = spn.coach_id
        left join profiles cpr on cpr.id = sco.user_id
        where spn.enrollment_id = e.id
      ), '[]'::jsonb) else null end
    )
  );
end;
$$;

-- list_coaching_program_batches' enrolled_count now reflects real per-batch
-- enrollment instead of the whole program's active-enrollment count.
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
    (select count(*) from coaching_enrollments e where e.batch_id = b.id and e.status in ('ACTIVE', 'PAUSED'))::bigint,
    b.status
  from coaching_program_batches b
  join courts c on c.id = b.court_id
  left join coaches co on co.id = b.coach_id
  left join profiles pr on pr.id = co.user_id
  where b.program_id = p_program_id
  order by b.created_at;
end;
$$;
