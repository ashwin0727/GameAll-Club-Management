-- ═══════════════════════════════════════════════════════════════════════════
-- Removing a court (or sport) from a facility, without losing or stranding anything.
--
--  * A court that still has upcoming work can't be removed or switched off: upcoming bookings, membership sessions with
--    members in them, coaching sessions, and coaching batches with students. The owner is told what is in the way and
--    moves or cancels it first.
--  * Past records are never touched. Removing a court only sets courts.archived, so every old booking, payment,
--    membership and coaching record keeps its court (and its name) — joins by court id keep working.
--  * Removing a SPORT removes its courts too (and brings them back if the sport is added again), so a court of a sport
--    the facility no longer offers can't linger in the pickers.
--  * New membership / coaching batches can't be created on a court that is removed, off, or whose sport is gone.
--  * Revenue by Court and Guest Bookings by Court keep a removed court in the periods it earned in; utilisation (which
--    is about the courts you have now) still lists only current courts.
-- ═══════════════════════════════════════════════════════════════════════════

alter table courts
  add column if not exists archived_reason text check (archived_reason in ('REMOVED', 'SPORT_REMOVED'));
update courts set archived_reason = 'REMOVED' where archived and archived_reason is null;

-- ─── What is still ahead on a court ────────────────────────────────────────
create or replace function court_upcoming_usage(p_court_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_facility uuid;
  n_bookings integer;
  n_batches integer;
  n_guest_slots integer;
  n_coaching_sessions integer;
  n_coaching_batches integer;
begin
  select facility_id into v_facility from courts where id = p_court_id;
  if v_facility is null then
    return jsonb_build_object('bookings', 0, 'membershipBatches', 0, 'membershipGuestSlots', 0,
                              'coachingSessions', 0, 'coachingBatches', 0, 'total', 0);
  end if;
  -- Called from the app (auth.uid() set) only for people who belong to the facility; the triggers below run it as the
  -- owner of the change.
  if auth.uid() is not null and not is_facility_member(v_facility) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  select count(*) into n_bookings from bookings
   where court_id = p_court_id and status in ('pending', 'confirmed') and end_time > now();

  select count(*) into n_batches from membership_batches mb
   where mb.court_id = p_court_id and mb.is_active
     and exists (select 1 from membership_batch_members m where m.batch_id = mb.id);

  select count(*) into n_guest_slots
    from membership_session_bookings sb
    join membership_sessions s on s.id = sb.session_id
   where s.court_id = p_court_id and s.session_date >= current_date
     and sb.status = 'CONFIRMED' and sb.participant_type = 'GUEST';

  select count(*) into n_coaching_sessions from coaching_sessions
   where court_id = p_court_id and status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS') and end_at > now();

  select count(*) into n_coaching_batches from coaching_program_batches cb
   where cb.court_id = p_court_id and cb.status = 'ACTIVE'
     and exists (select 1 from coaching_enrollments e where e.batch_id = cb.id and e.status = 'ACTIVE');

  return jsonb_build_object(
    'bookings', n_bookings,
    'membershipBatches', n_batches,
    'membershipGuestSlots', n_guest_slots,
    'coachingSessions', n_coaching_sessions,
    'coachingBatches', n_coaching_batches,
    'total', n_bookings + n_batches + n_guest_slots + n_coaching_sessions + n_coaching_batches
  );
end;
$$;
grant execute on function court_upcoming_usage(uuid) to authenticated;

-- "2 upcoming bookings, 1 membership batch …" — the sentence the owner sees when removal is blocked.
create or replace function _court_usage_sentence(u jsonb) returns text
language sql
immutable
as $$
  select array_to_string(array_remove(array[
    case when (u->>'bookings')::int > 0 then (u->>'bookings') || ' upcoming booking' || case when (u->>'bookings')::int = 1 then '' else 's' end end,
    case when (u->>'membershipBatches')::int > 0 then (u->>'membershipBatches') || ' membership session batch' || case when (u->>'membershipBatches')::int = 1 then '' else 'es' end end,
    case when (u->>'membershipGuestSlots')::int > 0 then (u->>'membershipGuestSlots') || ' guest slot' || case when (u->>'membershipGuestSlots')::int = 1 then '' else 's' end || ' in membership sessions' end,
    case when (u->>'coachingSessions')::int > 0 then (u->>'coachingSessions') || ' upcoming coaching session' || case when (u->>'coachingSessions')::int = 1 then '' else 's' end end,
    case when (u->>'coachingBatches')::int > 0 then (u->>'coachingBatches') || ' coaching batch' || case when (u->>'coachingBatches')::int = 1 then '' else 'es' end || ' with students' end
  ], null), ', ');
$$;

-- ─── Removing or switching off a court ─────────────────────────────────────
create or replace function guard_court_removal() returns trigger
language plpgsql
as $$
declare
  u jsonb;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if new.archived and not old.archived then
    new.archived_reason := coalesce(new.archived_reason, 'REMOVED');
  elsif not new.archived and old.archived then
    new.archived_reason := null;
  end if;

  if (new.archived and not old.archived) or (new.status = 'INACTIVE' and old.status is distinct from 'INACTIVE') then
    u := court_upcoming_usage(new.id);
    if (u->>'total')::int > 0 then
      raise exception '% has % — move or cancel % before removing or switching it off.',
        new.name, _court_usage_sentence(u), case when (u->>'total')::int = 1 then 'it' else 'them' end
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists courts_guard_removal on courts;
create trigger courts_guard_removal
  before update of archived, status on courts
  for each row execute function guard_court_removal();

-- ─── Removing (or re-adding) a sport takes its courts with it ──────────────
create or replace function sync_courts_with_facility_sport() returns trigger
language plpgsql
as $$
declare
  c record;
  u jsonb;
begin
  if tg_op <> 'UPDATE' or new.is_active is not distinct from old.is_active then
    return new;
  end if;

  if not new.is_active then
    for c in select id, name from courts where facility_sport_id = new.id and not archived loop
      u := court_upcoming_usage(c.id);
      if (u->>'total')::int > 0 then
        raise exception 'This sport can''t be removed yet: % has % — move or cancel % first.',
          c.name, _court_usage_sentence(u), case when (u->>'total')::int = 1 then 'it' else 'them' end
          using errcode = '23514';
      end if;
    end loop;
    update courts set archived = true, archived_reason = 'SPORT_REMOVED'
     where facility_sport_id = new.id and not archived;
  else
    -- Only the courts that went away with the sport come back; one the owner removed on purpose stays removed.
    update courts set archived = false, archived_reason = null
     where facility_sport_id = new.id and archived and archived_reason = 'SPORT_REMOVED';
  end if;
  return new;
end;
$$;

drop trigger if exists facility_sports_sync_courts on facility_sports;
create trigger facility_sports_sync_courts
  after update of is_active on facility_sports
  for each row execute function sync_courts_with_facility_sport();

-- ─── No new batches on a court that is gone ────────────────────────────────
create or replace function guard_batch_court() returns trigger
language plpgsql
as $$
declare
  c courts;
begin
  if tg_op = 'UPDATE' and new.court_id is not distinct from old.court_id then
    return new;
  end if;
  select * into c from courts where id = new.court_id;
  if c.id is null or c.archived or c.status <> 'ACTIVE' then
    raise exception 'That court is no longer available — choose another one.' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists membership_batches_guard_court on membership_batches;
create trigger membership_batches_guard_court
  before insert or update of court_id on membership_batches
  for each row execute function guard_batch_court();

drop trigger if exists coaching_program_batches_guard_court on coaching_program_batches;
create trigger coaching_program_batches_guard_court
  before insert or update of court_id on coaching_program_batches
  for each row execute function guard_batch_court();

-- ─── History keeps a removed court ─────────────────────────────────────────
drop function if exists get_revenue_by_court(uuid, text, date, date, uuid, uuid);

create or replace function get_revenue_by_court(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  revenue_minor bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with rev as (
    select
      coalesce(b.court_id, ms.court_id) as court_id,
      (p.amount_inr * 100)::bigint as amount_minor
    from payments p
    left join bookings b on b.id = p.booking_id
    left join membership_session_bookings msb on msb.id = p.membership_session_booking_id
    left join membership_sessions ms on ms.id = msb.session_id
    where p.facility_id = p_facility_id
      and p.status = 'paid'
      and range_ @> coalesce(p.paid_at, p.created_at)
      and coalesce(b.court_id, ms.court_id) is not null
  )
  select
    c.id,
    c.name,
    c.facility_sport_id,
    coalesce(fs.custom_sport_name, sp.name),
    coalesce(sum(rev.amount_minor), 0)::bigint
  from courts c
  join facility_sports fs on fs.id = c.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  left join rev on rev.court_id = c.id
  where c.facility_id = p_facility_id
    -- A removed court stays in the figures for the period it earned in, so the rows still add up to the total.
    and (not c.archived or exists (select 1 from rev h where h.court_id = c.id))
    and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or c.facility_sport_id = any (p_facility_sport_ids))
    and (p_court_id is null or c.id = p_court_id)
  group by c.id, c.name, c.facility_sport_id, coalesce(fs.custom_sport_name, sp.name)
  order by coalesce(sum(rev.amount_minor), 0) desc, c.name;
end;
$$;

grant execute on function get_revenue_by_court(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;

drop function if exists get_guest_bookings_by_court(uuid, text, date, date, uuid, uuid);

create or replace function get_guest_bookings_by_court(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  court_id uuid,
  court_name text,
  sport_name text,
  booking_count bigint,
  revenue_minor bigint
)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with gb as (
    select
      b.court_id,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p where p.booking_id = b.id and p.status = 'paid'
      ), 0)::bigint as collected_minor
    from bookings b
    where b.facility_id = p_facility_id
      and b.customer_type = 'GUEST'
      and range_ @> b.start_time
  )
  select
    c.id,
    c.name,
    coalesce(fs.custom_sport_name, sp.name),
    count(gb.court_id)::bigint,
    coalesce(sum(gb.collected_minor), 0)::bigint
  from courts c
  join facility_sports fs on fs.id = c.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  left join gb on gb.court_id = c.id
  where c.facility_id = p_facility_id
    -- A removed court stays in the figures for the period it earned in, so the rows still add up to the total.
    and (not c.archived or exists (select 1 from gb h where h.court_id = c.id))
    and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_facility_sport_ids is null or c.facility_sport_id = any (p_facility_sport_ids))
    and (p_court_id is null or c.id = p_court_id)
  group by c.id, c.name, coalesce(fs.custom_sport_name, sp.name)
  order by count(gb.court_id) desc, c.name;
end;
$$;

grant execute on function get_guest_bookings_by_court(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;
