-- ═══════════════════════════════════════════════════════════════════════════
-- Membership sessions: lifecycle, conflicts, eligibility — and the blocked
-- date the public booking page was ignoring.
--
-- Most of this module already exists and is left alone. membership_batches
-- is the recurring definition, membership_sessions the per-date occurrence,
-- membership_batch_members the roster, and release/restore_membership_capacity
-- already guard the release rules under row locks. What follows fills the
-- four gaps against the spec rather than restating any of that.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 1. Lifecycle. is_active was a boolean, which cannot distinguish a session
--    paused for a fortnight from one that has run its course. Sessions also
--    had no date window, so "runs until the end of March" had to be
--    remembered by a person.
--
--    is_active stays, kept in step by a trigger, so every existing query
--    that reads it keeps working unchanged.
-- ─────────────────────────────────────────────────────────────────────────
alter table membership_batches
  add column if not exists status text not null default 'ACTIVE'
    check (status in ('ACTIVE', 'PAUSED', 'EXPIRED', 'CANCELLED')),
  add column if not exists start_date date not null default current_date,
  -- NULL means no expiry, which is the common case for an open-ended session.
  add column if not exists end_date date,
  add constraint membership_batches_date_window
    check (end_date is null or end_date >= start_date);

update membership_batches set status = case when is_active then 'ACTIVE' else 'PAUSED' end
where status = 'ACTIVE' and not is_active;

create or replace function sync_membership_batch_active()
returns trigger
language plpgsql
as $$
begin
  -- One source of truth: status. is_active is the derived view of it that
  -- the rest of the schema already reads.
  if new.end_date is not null and new.end_date < current_date and new.status = 'ACTIVE' then
    new.status := 'EXPIRED';
  end if;
  new.is_active := (new.status = 'ACTIVE');
  return new;
end;
$$;

drop trigger if exists membership_batches_sync_active on membership_batches;
create trigger membership_batches_sync_active
  before insert or update on membership_batches
  for each row execute function sync_membership_batch_active();


-- ─────────────────────────────────────────────────────────────────────────
-- 2. Two sessions must not claim the same court at the same time on the
--    same day. Enforced by trigger rather than inside create/update, so
--    every path — including a direct update — is covered.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function check_membership_batch_conflict()
returns trigger
language plpgsql
as $$
declare
  clash membership_batches;
begin
  if new.status <> 'ACTIVE' then
    return new;
  end if;

  select mb.* into clash
  from membership_batches mb
  where mb.court_id = new.court_id
    and mb.id <> new.id
    and mb.status = 'ACTIVE'
    -- Overlapping clock times…
    and mb.start_time < new.end_time
    and mb.end_time > new.start_time
    -- …on a shared weekday…
    and mb.days_of_week && new.days_of_week
    -- …within overlapping date windows. A null end_date runs forever.
    and (new.end_date is null or mb.start_date <= new.end_date)
    and (mb.end_date is null or mb.end_date >= new.start_date)
  limit 1;

  if clash.id is not null then
    raise exception 'This court is already reserved by "%" at an overlapping time on one of these days.', clash.name
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists membership_batches_no_conflict on membership_batches;
create trigger membership_batches_no_conflict
  before insert or update on membership_batches
  for each row execute function check_membership_batch_conflict();


-- ─────────────────────────────────────────────────────────────────────────
-- 3. Member eligibility. Assignment already checked that the member belongs
--    to the facility and that the roster has room; it did not check whether
--    they hold a membership that is current. A trigger covers every path
--    into the roster, and says which rule failed rather than "not eligible".
-- ─────────────────────────────────────────────────────────────────────────
create or replace function check_membership_batch_member_eligible()
returns trigger
language plpgsql
as $$
declare
  batch membership_batches;
  has_any boolean;
  has_current boolean;
begin
  select * into batch from membership_batches where id = new.batch_id;
  if batch.id is null then
    raise exception 'Membership session not found' using errcode = 'P0002';
  end if;

  select
    count(*) > 0,
    count(*) filter (
      where m.status <> 'cancelled'
        and (m.end_date is null or m.end_date >= current_date)
    ) > 0
  into has_any, has_current
  from memberships m
  where m.member_id = new.member_id
    and m.facility_id = batch.facility_id;

  if not has_any then
    raise exception 'This member does not have a membership at this facility.' using errcode = '23514';
  end if;

  if not has_current then
    raise exception 'This member''s membership has expired.' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists membership_batch_members_eligible on membership_batch_members;
create trigger membership_batch_members_eligible
  before insert on membership_batch_members
  for each row execute function check_membership_batch_member_eligible();


-- ─────────────────────────────────────────────────────────────────────────
-- 4. Occurrences respect the lifecycle: a paused or cancelled session, and
--    a date outside the session's window, produce no occurrence.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_or_create_membership_session(p_batch_id uuid, p_session_date date)
returns membership_sessions
language plpgsql
as $$
declare
  batch membership_batches;
  result membership_sessions;
  dow smallint;
begin
  select * into batch from membership_batches where id = p_batch_id;
  if batch.id is null then
    raise exception 'Membership batch not found' using errcode = 'P0002';
  end if;

  if batch.status = 'PAUSED' then
    raise exception 'This session is paused.' using errcode = '23514';
  elsif batch.status = 'CANCELLED' then
    raise exception 'This session has been cancelled.' using errcode = '23514';
  elsif not batch.is_active then
    raise exception 'This membership batch is no longer active.' using errcode = '23514';
  end if;

  if p_session_date < batch.start_date then
    raise exception 'This session has not started yet.' using errcode = '23514';
  end if;
  if batch.end_date is not null and p_session_date > batch.end_date then
    raise exception 'This session has ended.' using errcode = '23514';
  end if;

  dow := extract(dow from p_session_date);
  if not (dow = any(batch.days_of_week)) then
    raise exception 'This date is not a scheduled day for this membership batch.' using errcode = '23514';
  end if;
  if exists (select 1 from membership_batch_blocked_dates where batch_id = p_batch_id and blocked_date = p_session_date) then
    raise exception 'This date is blocked for this session.' using errcode = '23514';
  end if;

  insert into membership_sessions (
    batch_id, facility_id, court_id, facility_sport_id, session_date, start_time, end_time, capacity
  ) values (
    batch.id, batch.facility_id, batch.court_id, batch.facility_sport_id, p_session_date, batch.start_time, batch.end_time, batch.capacity
  )
  on conflict (batch_id, session_date) do update set updated_at = now()
  returning * into result;

  return result;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- 5. "Is this court membership-protected right now?" is the question both
--    create_booking and the public availability page ask, so it is the right
--    place to teach the lifecycle rather than patching each caller.
--
--    It previously asked only whether an active batch covered the weekday
--    and clock time. A session that had ended, one paused, and a date the
--    owner had skipped all still reported as protected — which left the
--    court unbookable by anybody on days it was in fact free.
--
--    A skipped date means the session does not run: the court returns to
--    ordinary availability at its ordinary price, rather than becoming a
--    hole in the calendar nobody can use.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function court_has_active_membership_window(
  p_court_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_timezone text
) returns boolean
language plpgsql
stable
as $$
declare
  local_start timestamp := p_start_time at time zone coalesce(p_timezone, 'Asia/Kolkata');
  local_end timestamp := p_end_time at time zone coalesce(p_timezone, 'Asia/Kolkata');
  dow smallint;
  on_date date;
begin
  if local_end::date <> local_start::date then
    return false;
  end if;
  dow := extract(dow from local_start);
  on_date := local_start::date;

  return exists (
    select 1 from membership_batches mb
    where mb.court_id = p_court_id
      and mb.status = 'ACTIVE'
      and dow = any(mb.days_of_week)
      and mb.start_time < local_end::time
      and mb.end_time > local_start::time
      and mb.start_date <= on_date
      and (mb.end_date is null or mb.end_date >= on_date)
      and not exists (
        select 1 from membership_batch_blocked_dates bd
        where bd.batch_id = mb.id and bd.blocked_date = on_date
      )
  );
end;
$$;

grant execute on function court_has_active_membership_window(uuid, timestamptz, timestamptz, text) to anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 6. Public availability, matching that same definition when it looks up
--    how much of a protected window has been released.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_public_court_availability(
  p_facility_id uuid,
  p_facility_sport_id uuid,
  p_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  fac facilities;
  tz text;
  result jsonb := '[]'::jsonb;
  c record;
  h integer;
  slot_start timestamptz;
  slot_end timestamptz;
  slots jsonb;
  released integer;
  guest_booked integer;
  is_available boolean;
  price integer;
begin
  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    return '[]'::jsonb;
  end if;
  tz := coalesce(fac.timezone, 'Asia/Kolkata');

  for c in
    select ct.id, ct.name
    from courts ct
    where ct.facility_id = p_facility_id
      and ct.facility_sport_id = p_facility_sport_id
      and not ct.archived
    order by ct.display_order, ct.name
  loop
    slots := '[]'::jsonb;

    for h in 0..23 loop
      slot_start := (p_date::text || ' ' || lpad(h::text, 2, '0') || ':00:00')::timestamp at time zone tz;
      slot_end := slot_start + interval '1 hour';

      continue when slot_end <= now();
      continue when not booking_window_fits_operating_hours(p_facility_id, c.id, slot_start, slot_end);

      is_available := not exists (
        select 1
        from bookings b
        where b.court_id = c.id
          and b.status in ('pending', 'confirmed')
          and tstzrange(b.start_time, b.end_time) && tstzrange(slot_start, slot_end)
      );

      if is_available and court_has_active_membership_window(c.id, slot_start, slot_end, tz) then
        select
          coalesce(ms.released_capacity, 0),
          coalesce((
            select count(*)
            from membership_session_bookings msb
            where msb.session_id = ms.id
              and msb.participant_type = 'GUEST'
              and msb.status = 'CONFIRMED'
          ), 0)
        into released, guest_booked
        from membership_batches mb
        left join membership_sessions ms
          on ms.batch_id = mb.id and ms.session_date = p_date
        where mb.court_id = c.id
          and mb.status = 'ACTIVE'
          and extract(dow from (slot_start at time zone tz)) = any(mb.days_of_week)
          and mb.start_time < (slot_end at time zone tz)::time
          and mb.end_time > (slot_start at time zone tz)::time
          -- Same conditions court_has_active_membership_window applies, so
          -- the batch found here is the one that made the slot protected.
          and mb.start_date <= p_date
          and (mb.end_date is null or mb.end_date >= p_date)
          and not exists (
            select 1 from membership_batch_blocked_dates bd
            where bd.batch_id = mb.id and bd.blocked_date = p_date
          )
        limit 1;

        -- Protected membership time: bookable only up to what the owner
        -- released and has not already sold.
        is_available := coalesce(released, 0) > coalesce(guest_booked, 0);
      end if;

      price := resolve_booking_price(p_facility_sport_id, c.id, slot_start, slot_end, tz);

      slots := slots || jsonb_build_object(
        'startTime', slot_start,
        'endTime', slot_end,
        'available', is_available,
        'priceMinor', coalesce(price, 0)
      );
    end loop;

    if jsonb_array_length(slots) > 0 then
      result := result || jsonb_build_object(
        'courtId', c.id,
        'courtName', c.name,
        'slots', slots
      );
    end if;
  end loop;

  return result;
end;
$$;

grant execute on function get_public_court_availability(uuid, uuid, date) to anon, authenticated;
