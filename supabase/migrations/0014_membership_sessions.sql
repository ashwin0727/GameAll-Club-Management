-- ═══════════════════════════════════════════════════════════════════════════
-- Membership Batches / Sessions — recurring membership court allocation with
-- releasable guest capacity.
--
--   membership_plans (existing, reused — the priced product a member buys)
--         │
--         ▼
--   membership_batches — the recurring template: which court, which sport,
--   which days of week, what time window, how many players (capacity).
--         │
--         ├── membership_batch_members — which members are eligible to book
--         │   this batch's sessions (assignment, not attendance).
--         │
--         ▼
--   membership_sessions — one row per ACTUAL calendar occurrence of a batch
--   (e.g. "Evening Badminton, 2026-08-24"), created lazily the first time
--   anyone books/releases/restores against that date — never pre-generated
--   for every future date. A snapshot of court/sport/capacity at creation
--   time, so changing the batch later never rewrites past occurrences
--   (spec §24/§34).
--         │
--         ▼
--   membership_session_bookings — the actual capacity consumption: one row
--   per member or guest occupying one of the session's slots. This is
--   deliberately NOT a `bookings` row — `bookings` has a court/time
--   exclusion constraint that models one exclusive booking per court per
--   time range, which cannot represent 5 concurrent players sharing one
--   slot. member_id/guest_player_id reference the existing members/
--   guest_players tables — no new Member or Guest model is introduced.
--
-- Capacity math is never trusted from the client: every write goes through
-- an RPC that locks the session row (`select ... for update`) before
-- reading current counts, so two concurrent requests for the last slot can
-- never both succeed (spec §32/§52).
--
-- Guest capacity is layered strictly on top of membership capacity —
-- `released_capacity` is an explicit owner decision stored per occurrence
-- (never inferred from non-attendance, spec §20), and a regular ad-hoc
-- booking (create_booking) is blocked outright during an active batch's
-- window so the ONLY way to book a guest into that court/time is through
-- book_guest_slot, which can only ever consume released capacity.
-- ═══════════════════════════════════════════════════════════════════════════

-- Required before membership_batches' composite FK below can reference
-- (facility_id, id) on membership_plans — id alone is already the primary
-- key, but Postgres still requires an explicit unique constraint naming
-- exactly the referenced column set for a composite foreign key.
alter table membership_plans add constraint membership_plans_facility_id_unique unique (facility_id, id);

create table membership_batches (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  plan_id uuid not null references membership_plans (id) on delete cascade,
  facility_sport_id uuid not null references facility_sports (id) on delete cascade,
  court_id uuid not null references courts (id) on delete restrict,
  name text not null,
  -- 0=Sunday..6=Saturday, matching extract(dow from timestamp).
  days_of_week smallint[] not null,
  start_time time not null,
  end_time time not null,
  capacity integer not null check (capacity > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint membership_batches_time_check check (end_time > start_time),
  constraint membership_batches_days_check check (
    coalesce(array_length(days_of_week, 1), 0) > 0
    and days_of_week <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
  ),
  -- The batch's plan, sport, and court must all belong to the same facility
  -- — mirrors the facility_sports/courts composite-FK pattern from 0001/0002.
  foreign key (facility_id, plan_id) references membership_plans (facility_id, id) on delete cascade
);
create index membership_batches_facility_id_idx on membership_batches (facility_id);
create index membership_batches_court_id_idx on membership_batches (court_id);

create table membership_batch_members (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references membership_batches (id) on delete cascade,
  member_id uuid not null references members (id) on delete cascade,
  membership_id uuid references memberships (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (batch_id, member_id)
);
create index membership_batch_members_batch_id_idx on membership_batch_members (batch_id);
create index membership_batch_members_member_id_idx on membership_batch_members (member_id);

create table membership_sessions (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references membership_batches (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  court_id uuid not null references courts (id) on delete restrict,
  facility_sport_id uuid not null references facility_sports (id) on delete restrict,
  session_date date not null,
  start_time time not null,
  end_time time not null,
  capacity integer not null check (capacity > 0),
  released_capacity integer not null default 0 check (released_capacity >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (batch_id, session_date),
  constraint membership_sessions_released_lte_capacity check (released_capacity <= capacity)
);
create index membership_sessions_facility_date_idx on membership_sessions (facility_id, session_date);
create index membership_sessions_court_date_idx on membership_sessions (court_id, session_date);

create table membership_session_bookings (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references membership_sessions (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  participant_type text not null check (participant_type in ('MEMBER', 'GUEST')),
  member_id uuid references members (id) on delete cascade,
  guest_player_id uuid references guest_players (id) on delete cascade,
  status text not null default 'CONFIRMED' check (status in ('CONFIRMED', 'CANCELLED')),
  slot_source text not null check (slot_source in ('MEMBERSHIP', 'RELEASED')),
  amount_minor integer check (amount_minor is null or amount_minor >= 0),
  currency text not null default 'INR',
  created_by uuid not null references profiles (id),
  created_at timestamptz not null default now(),
  constraint membership_session_bookings_participant_check check (
    (participant_type = 'MEMBER' and member_id is not null and guest_player_id is null and slot_source = 'MEMBERSHIP')
    or (participant_type = 'GUEST' and guest_player_id is not null and member_id is null and slot_source = 'RELEASED')
  )
);
create index membership_session_bookings_session_id_idx on membership_session_bookings (session_id);
-- A member can only hold one confirmed slot per session (no double-booking themselves into their own batch).
create unique index membership_session_bookings_member_unique
  on membership_session_bookings (session_id, member_id)
  where status = 'CONFIRMED' and member_id is not null;

alter table membership_batches enable row level security;
alter table membership_batch_members enable row level security;
alter table membership_sessions enable row level security;
alter table membership_session_bookings enable row level security;

create policy "membership_batches_select_members" on membership_batches for select
  using (is_facility_member(facility_id));
create policy "membership_batches_write_managers" on membership_batches for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

create policy "membership_batch_members_select_members" on membership_batch_members for select
  using (exists (select 1 from membership_batches b where b.id = batch_id and is_facility_member(b.facility_id)));
create policy "membership_batch_members_write_staff" on membership_batch_members for all
  using (exists (select 1 from membership_batches b where b.id = batch_id and has_facility_role(b.facility_id, array['owner', 'manager', 'staff']::facility_role[])))
  with check (exists (select 1 from membership_batches b where b.id = batch_id and has_facility_role(b.facility_id, array['owner', 'manager', 'staff']::facility_role[])));

create policy "membership_sessions_select_members" on membership_sessions for select
  using (is_facility_member(facility_id));
create policy "membership_sessions_write_staff" on membership_sessions for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

create policy "membership_session_bookings_select_members" on membership_session_bookings for select
  using (is_facility_member(facility_id));
create policy "membership_session_bookings_write_staff" on membership_session_bookings for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

-- ─────────────────────────────────────────────────────────────────────────
-- create_membership_batch / update_membership_batch
-- ─────────────────────────────────────────────────────────────────────────
create function create_membership_batch(
  p_facility_id uuid,
  p_plan_id uuid,
  p_facility_sport_id uuid,
  p_court_id uuid,
  p_name text,
  p_days_of_week smallint[],
  p_start_time time,
  p_end_time time,
  p_capacity integer
) returns membership_batches
language plpgsql
as $$
declare
  result membership_batches;
  court courts;
begin
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Batch name is required.' using errcode = '23514';
  end if;

  select * into court from courts where id = p_court_id and facility_id = p_facility_id and facility_sport_id = p_facility_sport_id;
  if court.id is null then
    raise exception 'That court does not belong to this facility/sport.' using errcode = '23503';
  end if;

  insert into membership_batches (
    facility_id, plan_id, facility_sport_id, court_id, name, days_of_week, start_time, end_time, capacity
  ) values (
    p_facility_id, p_plan_id, p_facility_sport_id, p_court_id, trim(p_name), p_days_of_week, p_start_time, p_end_time, p_capacity
  ) returning * into result;

  return result;
end;
$$;

grant execute on function create_membership_batch(uuid, uuid, uuid, uuid, text, smallint[], time, time, integer) to authenticated;

create function update_membership_batch(
  p_batch_id uuid,
  p_name text,
  p_court_id uuid,
  p_days_of_week smallint[],
  p_start_time time,
  p_end_time time,
  p_capacity integer,
  p_is_active boolean default null
) returns membership_batches
language plpgsql
as $$
declare
  existing membership_batches;
  result membership_batches;
  court courts;
begin
  select * into existing from membership_batches where id = p_batch_id;
  if existing.id is null then
    raise exception 'Membership batch not found' using errcode = 'P0002';
  end if;

  select * into court from courts where id = p_court_id and facility_id = existing.facility_id and facility_sport_id = existing.facility_sport_id;
  if court.id is null then
    raise exception 'That court does not belong to this facility/sport.' using errcode = '23503';
  end if;

  update membership_batches
  set name = trim(p_name),
      court_id = p_court_id,
      days_of_week = p_days_of_week,
      start_time = p_start_time,
      end_time = p_end_time,
      capacity = p_capacity,
      is_active = coalesce(p_is_active, is_active),
      updated_at = now()
  where id = p_batch_id
  returning * into result;

  return result;
end;
$$;

grant execute on function update_membership_batch(uuid, text, uuid, smallint[], time, time, integer, boolean) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- assign_batch_member / remove_batch_member
-- ─────────────────────────────────────────────────────────────────────────
create function assign_batch_member(p_batch_id uuid, p_member_id uuid, p_membership_id uuid default null)
returns membership_batch_members
language plpgsql
as $$
declare
  batch membership_batches;
  member members;
  result membership_batch_members;
begin
  select * into batch from membership_batches where id = p_batch_id;
  if batch.id is null then
    raise exception 'Membership batch not found' using errcode = 'P0002';
  end if;

  select * into member from members where id = p_member_id and facility_id = batch.facility_id;
  if member.id is null then
    raise exception 'That member does not belong to this facility.' using errcode = '23503';
  end if;

  insert into membership_batch_members (batch_id, member_id, membership_id)
  values (p_batch_id, p_member_id, p_membership_id)
  returning * into result;

  return result;
end;
$$;

grant execute on function assign_batch_member(uuid, uuid, uuid) to authenticated;

create function remove_batch_member(p_batch_id uuid, p_member_id uuid) returns void
language sql
as $$
  delete from membership_batch_members where batch_id = p_batch_id and member_id = p_member_id;
$$;

grant execute on function remove_batch_member(uuid, uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_or_create_membership_session: atomic upsert (no explicit lock needed
-- — the unique(batch_id, session_date) constraint plus ON CONFLICT makes
-- this race-safe on its own) so a session occurrence is only ever
-- materialized the first time something actually happens against that date.
-- ─────────────────────────────────────────────────────────────────────────
create function get_or_create_membership_session(p_batch_id uuid, p_session_date date)
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
  if not batch.is_active then
    raise exception 'This membership batch is no longer active.' using errcode = '23514';
  end if;

  dow := extract(dow from p_session_date);
  if not (dow = any(batch.days_of_week)) then
    raise exception 'This date is not a scheduled day for this membership batch.' using errcode = '23514';
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

grant execute on function get_or_create_membership_session(uuid, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_membership_session_capacity: the single authoritative capacity read —
-- every count the UI needs, derived live, never a maintained counter.
-- ─────────────────────────────────────────────────────────────────────────
create function get_membership_session_capacity(p_session_id uuid) returns table (
  capacity integer,
  released_capacity integer,
  member_booked_count integer,
  guest_booked_count integer,
  unused_capacity integer,
  guest_available_capacity integer
)
language sql
stable
as $$
  select
    s.capacity,
    s.released_capacity,
    coalesce((select count(*) from membership_session_bookings b where b.session_id = s.id and b.participant_type = 'MEMBER' and b.status = 'CONFIRMED'), 0)::integer as member_booked_count,
    coalesce((select count(*) from membership_session_bookings b where b.session_id = s.id and b.participant_type = 'GUEST' and b.status = 'CONFIRMED'), 0)::integer as guest_booked_count,
    (s.capacity - coalesce((select count(*) from membership_session_bookings b where b.session_id = s.id and b.participant_type = 'MEMBER' and b.status = 'CONFIRMED'), 0))::integer as unused_capacity,
    (s.released_capacity - coalesce((select count(*) from membership_session_bookings b where b.session_id = s.id and b.participant_type = 'GUEST' and b.status = 'CONFIRMED'), 0))::integer as guest_available_capacity
  from membership_sessions s
  where s.id = p_session_id;
$$;

grant execute on function get_membership_session_capacity(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- book_membership_slot: a member consumes one of their batch's protected
-- slots. Locks the session row first so two concurrent requests for the
-- last slot can never both succeed.
-- ─────────────────────────────────────────────────────────────────────────
create function book_membership_slot(p_batch_id uuid, p_session_date date, p_member_id uuid)
returns membership_session_bookings
language plpgsql
as $$
declare
  session membership_sessions;
  member_booked_count integer;
  result membership_session_bookings;
begin
  if not exists (select 1 from membership_batch_members where batch_id = p_batch_id and member_id = p_member_id) then
    raise exception 'This member is not assigned to this membership batch.' using errcode = '23514';
  end if;

  session := get_or_create_membership_session(p_batch_id, p_session_date);
  select * into session from membership_sessions where id = session.id for update;

  select count(*) into member_booked_count from membership_session_bookings
    where session_id = session.id and participant_type = 'MEMBER' and status = 'CONFIRMED';

  if member_booked_count >= session.capacity then
    raise exception 'Membership capacity is full for this session.' using errcode = '23514';
  end if;

  insert into membership_session_bookings (session_id, facility_id, participant_type, member_id, status, slot_source, created_by)
  values (session.id, session.facility_id, 'MEMBER', p_member_id, 'CONFIRMED', 'MEMBERSHIP', auth.uid())
  returning * into result;

  return result;
end;
$$;

grant execute on function book_membership_slot(uuid, date, uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- release_membership_capacity / restore_membership_capacity: the owner's
-- explicit, per-occurrence decision — never inferred from non-attendance.
-- ─────────────────────────────────────────────────────────────────────────
create function release_membership_capacity(p_session_id uuid, p_count integer) returns membership_sessions
language plpgsql
as $$
declare
  session membership_sessions;
  member_booked_count integer;
  unused integer;
  result membership_sessions;
begin
  if p_count <= 0 then
    raise exception 'Release count must be positive.' using errcode = '23514';
  end if;

  select * into session from membership_sessions where id = p_session_id for update;
  if session.id is null then
    raise exception 'Membership session not found' using errcode = 'P0002';
  end if;

  select count(*) into member_booked_count from membership_session_bookings
    where session_id = session.id and participant_type = 'MEMBER' and status = 'CONFIRMED';
  unused := session.capacity - member_booked_count;

  if session.released_capacity + p_count > unused then
    raise exception 'Cannot release more than the unused membership capacity.' using errcode = '23514';
  end if;

  update membership_sessions set released_capacity = released_capacity + p_count, updated_at = now()
  where id = p_session_id
  returning * into result;

  return result;
end;
$$;

grant execute on function release_membership_capacity(uuid, integer) to authenticated;

create function restore_membership_capacity(p_session_id uuid, p_count integer) returns membership_sessions
language plpgsql
as $$
declare
  session membership_sessions;
  guest_booked_count integer;
  restorable integer;
  result membership_sessions;
begin
  if p_count <= 0 then
    raise exception 'Restore count must be positive.' using errcode = '23514';
  end if;

  select * into session from membership_sessions where id = p_session_id for update;
  if session.id is null then
    raise exception 'Membership session not found' using errcode = 'P0002';
  end if;

  select count(*) into guest_booked_count from membership_session_bookings
    where session_id = session.id and participant_type = 'GUEST' and status = 'CONFIRMED';
  restorable := session.released_capacity - guest_booked_count;

  if p_count > restorable then
    raise exception 'Cannot restore a released slot that is already booked by a guest.' using errcode = '23514';
  end if;

  update membership_sessions set released_capacity = released_capacity - p_count, updated_at = now()
  where id = p_session_id
  returning * into result;

  return result;
end;
$$;

grant execute on function restore_membership_capacity(uuid, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- book_guest_slot: a guest consumes ONLY released capacity. Reuses the
-- existing pricing engine (resolve_booking_price) exactly as create_booking
-- does — no second pricing engine.
-- ─────────────────────────────────────────────────────────────────────────
create function book_guest_slot(p_batch_id uuid, p_session_date date, p_guest_player_id uuid)
returns membership_session_bookings
language plpgsql
as $$
declare
  session membership_sessions;
  guest guest_players;
  fac facilities;
  guest_booked_count integer;
  price integer;
  session_start timestamptz;
  session_end timestamptz;
  result membership_session_bookings;
begin
  session := get_or_create_membership_session(p_batch_id, p_session_date);
  select * into session from membership_sessions where id = session.id for update;

  select * into fac from facilities where id = session.facility_id;
  select * into guest from guest_players where id = p_guest_player_id and facility_id = session.facility_id;
  if guest.id is null then
    raise exception 'That guest does not belong to this facility.' using errcode = '23503';
  end if;

  select count(*) into guest_booked_count from membership_session_bookings
    where session_id = session.id and participant_type = 'GUEST' and status = 'CONFIRMED';

  if guest_booked_count >= session.released_capacity then
    raise exception 'No guest slots are currently available for this session.' using errcode = '23514';
  end if;

  session_start := (p_session_date::text || ' ' || session.start_time::text)::timestamp at time zone coalesce(fac.timezone, 'Asia/Kolkata');
  session_end := (p_session_date::text || ' ' || session.end_time::text)::timestamp at time zone coalesce(fac.timezone, 'Asia/Kolkata');
  price := resolve_booking_price(session.facility_sport_id, session.court_id, session_start, session_end, fac.timezone);

  insert into membership_session_bookings (
    session_id, facility_id, participant_type, guest_player_id, status, slot_source, amount_minor, currency, created_by
  ) values (
    session.id, session.facility_id, 'GUEST', p_guest_player_id, 'CONFIRMED', 'RELEASED', price, fac.currency, auth.uid()
  ) returning * into result;

  return result;
end;
$$;

grant execute on function book_guest_slot(uuid, date, uuid) to authenticated;

create function cancel_membership_slot_booking(p_booking_id uuid) returns membership_session_bookings
language plpgsql
as $$
declare
  result membership_session_bookings;
begin
  update membership_session_bookings set status = 'CANCELLED' where id = p_booking_id and status = 'CONFIRMED'
  returning * into result;
  if result.id is null then
    raise exception 'Booking not found or already cancelled' using errcode = 'P0002';
  end if;
  return result;
end;
$$;

grant execute on function cancel_membership_slot_booking(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_membership_sessions_for_date: the Owner Availability View's single
-- read — one row per batch scheduled on this date, whether or not its
-- occurrence row has been materialized yet (unmaterialized = zero booked,
-- zero released, exactly as if nothing has happened for that date, because
-- nothing has).
-- ─────────────────────────────────────────────────────────────────────────
create function list_membership_sessions_for_date(p_facility_id uuid, p_date date) returns table (
  batch_id uuid,
  session_id uuid,
  batch_name text,
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  session_date date,
  start_time time,
  end_time time,
  capacity integer,
  released_capacity integer,
  member_booked_count integer,
  guest_booked_count integer
)
language sql
stable
as $$
  select
    b.id,
    s.id,
    b.name,
    b.court_id,
    c.name,
    b.facility_sport_id,
    coalesce(fs.custom_sport_name, sp.name),
    p_date,
    b.start_time,
    b.end_time,
    b.capacity,
    coalesce(s.released_capacity, 0),
    coalesce((select count(*) from membership_session_bookings mb where mb.session_id = s.id and mb.participant_type = 'MEMBER' and mb.status = 'CONFIRMED'), 0)::integer,
    coalesce((select count(*) from membership_session_bookings mb where mb.session_id = s.id and mb.participant_type = 'GUEST' and mb.status = 'CONFIRMED'), 0)::integer
  from membership_batches b
  join courts c on c.id = b.court_id
  join facility_sports fs on fs.id = b.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  left join membership_sessions s on s.batch_id = b.id and s.session_date = p_date
  where b.facility_id = p_facility_id
    and b.is_active
    and extract(dow from p_date)::smallint = any(b.days_of_week)
  order by b.start_time;
$$;

grant execute on function list_membership_sessions_for_date(uuid, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- court_has_active_membership_window / create_booking / reschedule_booking:
-- an ad-hoc booking (member OR guest) must never be created on top of a
-- court/time an active membership batch owns — the only path to a guest
-- occupying that window is book_guest_slot, which can only ever consume
-- explicitly released capacity. Same signatures as before, so `create or
-- replace` in place (no drop needed).
-- ─────────────────────────────────────────────────────────────────────────
create function court_has_active_membership_window(
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
begin
  if local_end::date <> local_start::date then
    return false;
  end if;
  dow := extract(dow from local_start);
  return exists (
    select 1 from membership_batches mb
    where mb.court_id = p_court_id
      and mb.is_active
      and dow = any(mb.days_of_week)
      and mb.start_time < local_end::time
      and mb.end_time > local_start::time
  );
end;
$$;

grant execute on function court_has_active_membership_window(uuid, timestamptz, timestamptz, text) to authenticated;

create or replace function create_booking(
  p_facility_id uuid,
  p_court_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_customer_type text,
  p_member_id uuid,
  p_guest_name text,
  p_guest_phone text,
  p_notes text,
  p_payment_status text default 'PENDING',
  p_guest_player_id uuid default null
) returns bookings
language plpgsql
as $$
declare
  result bookings;
  fac facilities;
  court courts;
  price integer;
  guest guest_players;
  v_guest_name text := p_guest_name;
  v_guest_phone text := p_guest_phone;
begin
  if p_end_time <= p_start_time then
    raise exception 'End time must be after start time.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    raise exception 'facility % does not exist', p_facility_id using errcode = '23503';
  end if;

  select * into court from courts where id = p_court_id and facility_id = p_facility_id;
  if court.id is null then
    raise exception 'court % does not exist for this facility', p_court_id using errcode = '23503';
  end if;

  if p_guest_player_id is not null then
    select * into guest from guest_players where id = p_guest_player_id and facility_id = p_facility_id;
    if guest.id is null then
      raise exception 'guest % does not exist for this facility', p_guest_player_id using errcode = '23503';
    end if;
    v_guest_name := guest.name;
    v_guest_phone := guest.phone;
  end if;

  if not booking_window_fits_operating_hours(p_facility_id, p_court_id, p_start_time, p_end_time) then
    raise exception 'Selected time is outside this court''s operating hours.' using errcode = '23514';
  end if;

  if court_has_active_membership_window(p_court_id, p_start_time, p_end_time, fac.timezone) then
    raise exception 'This time is reserved for a membership session. Use guest slot booking for this court/time instead.' using errcode = '23514';
  end if;

  price := resolve_booking_price(court.facility_sport_id, p_court_id, p_start_time, p_end_time, fac.timezone);

  insert into bookings (
    facility_id, court_id, member_id, start_time, end_time, status,
    customer_type, guest_name, guest_phone, guest_player_id,
    amount_minor, currency, notes, created_by, payment_status
  ) values (
    p_facility_id, p_court_id, p_member_id, p_start_time, p_end_time, 'confirmed',
    coalesce(p_customer_type, 'MEMBER'), v_guest_name, v_guest_phone, p_guest_player_id,
    price, fac.currency, p_notes, auth.uid(), coalesce(p_payment_status, 'PENDING')
  ) returning * into result;

  return result;
end;
$$;

create or replace function reschedule_booking(
  p_booking_id uuid,
  p_new_court_id uuid,
  p_new_start_time timestamptz,
  p_new_end_time timestamptz
) returns bookings
language plpgsql
as $$
declare
  result bookings;
  fac facilities;
  court courts;
  price integer;
begin
  if p_new_end_time <= p_new_start_time then
    raise exception 'End time must be after start time.' using errcode = '23514';
  end if;

  select * into result from bookings where id = p_booking_id;
  if result.id is null then
    raise exception 'booking % does not exist', p_booking_id using errcode = '23503';
  end if;
  if result.status not in ('pending', 'confirmed') then
    raise exception 'Only a pending or confirmed booking can be rescheduled.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = result.facility_id;
  select * into court from courts where id = p_new_court_id and facility_id = result.facility_id;
  if court.id is null then
    raise exception 'court % does not exist for this facility', p_new_court_id using errcode = '23503';
  end if;

  if not booking_window_fits_operating_hours(result.facility_id, p_new_court_id, p_new_start_time, p_new_end_time) then
    raise exception 'Selected time is outside this court''s operating hours.' using errcode = '23514';
  end if;

  if court_has_active_membership_window(p_new_court_id, p_new_start_time, p_new_end_time, fac.timezone) then
    raise exception 'This time is reserved for a membership session. Use guest slot booking for this court/time instead.' using errcode = '23514';
  end if;

  price := resolve_booking_price(court.facility_sport_id, p_new_court_id, p_new_start_time, p_new_end_time, fac.timezone);

  update bookings
  set court_id = p_new_court_id,
      start_time = p_new_start_time,
      end_time = p_new_end_time,
      amount_minor = price
  where id = p_booking_id
  returning * into result;

  return result;
end;
$$;