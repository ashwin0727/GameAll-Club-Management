-- ═══════════════════════════════════════════════════════════════════════════
-- Guest Player Management
--
--   facilities → guest_players → bookings (guest_player_id)
--
-- Bookings already had guest_name/guest_phone free-text columns (0007) for
-- a walk-in customer with no account. This migration adds a real,
-- de-duplicated Guest Player entity per facility (matched by phone number)
-- so the same person's repeat visits accumulate against one profile instead
-- of a new free-text row every time — and links bookings to it via
-- guest_player_id. guest_name/guest_phone stay on bookings as the
-- point-in-time snapshot (what the booking actually says), matching this
-- project's established denormalization convention (courts.facility_id,
-- pricing_rules.facility_id, etc.) — Guest Player itself never duplicates
-- court/sport/time/price, only bookings does.
-- ═══════════════════════════════════════════════════════════════════════════

create table guest_players (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  name text not null,
  phone text,
  email text,
  notes text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index guest_players_facility_id_idx on guest_players (facility_id);
create index guest_players_facility_status_idx on guest_players (facility_id, status);

-- Digits-only phone match, scoped per facility — "9876543210" and
-- "+91 98765 43210" collide on purpose so the same person can't get two
-- profiles just by how the number was typed. NULL phones never collide
-- (a guest with no phone can't be deduped by phone at all).
create unique index guest_players_facility_phone_idx
  on guest_players (facility_id, regexp_replace(phone, '\D', '', 'g'))
  where phone is not null and regexp_replace(phone, '\D', '', 'g') <> '';

alter table guest_players enable row level security;

create policy "guest_players_select_members" on guest_players for select
  using (is_facility_member(facility_id));
create policy "guest_players_write_managers" on guest_players for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

alter table bookings
  add column guest_player_id uuid references guest_players (id) on delete set null;
create index bookings_guest_player_id_idx on bookings (guest_player_id);

-- ─────────────────────────────────────────────────────────────────────────
-- find_or_create_guest: the single write path for both "search existing"
-- and "create new" in the Booking → Guest flow. Matches by normalized
-- phone within the facility; if found, returns the existing row untouched
-- (never overwrites a name typed slightly differently) — the caller decides
-- whether to separately call update_guest for a deliberate edit.
-- ─────────────────────────────────────────────────────────────────────────
create function find_or_create_guest(
  p_facility_id uuid,
  p_name text,
  p_phone text,
  p_email text default null,
  p_notes text default null
) returns guest_players
language plpgsql
as $$
declare
  result guest_players;
  normalized_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), '');
begin
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Guest name is required.' using errcode = '23514';
  end if;

  if normalized_phone is not null then
    select * into result from guest_players
      where facility_id = p_facility_id
        and regexp_replace(coalesce(phone, ''), '\D', '', 'g') = normalized_phone;
    if result.id is not null then
      return result;
    end if;
  end if;

  insert into guest_players (facility_id, name, phone, email, notes)
  values (p_facility_id, trim(p_name), p_phone, p_email, p_notes)
  returning * into result;

  return result;
end;
$$;

grant execute on function find_or_create_guest(uuid, text, text, text, text) to authenticated;

create function update_guest(
  p_guest_id uuid,
  p_name text,
  p_phone text,
  p_email text,
  p_notes text,
  p_status text
) returns guest_players
language plpgsql
as $$
declare
  result guest_players;
begin
  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Guest name is required.' using errcode = '23514';
  end if;

  update guest_players
  set name = trim(p_name),
      phone = p_phone,
      email = p_email,
      notes = p_notes,
      status = coalesce(p_status, status),
      updated_at = now()
  where id = p_guest_id
  returning * into result;

  if result.id is null then
    raise exception 'Guest not found' using errcode = 'P0002';
  end if;

  return result;
end;
$$;

grant execute on function update_guest(uuid, text, text, text, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_guest_stats: every number on the Guest Profile screen, derived live
-- from real bookings — never a duplicated/maintained counter. "Visits" =
-- confirmed or completed bookings only (a cancelled booking was never an
-- actual visit; a pending one hasn't happened yet).
-- ─────────────────────────────────────────────────────────────────────────
create function get_guest_stats(p_guest_id uuid) returns table (
  total_visits bigint,
  total_bookings bigint,
  last_visit timestamptz,
  total_amount_minor bigint,
  pending_amount_minor bigint,
  sports jsonb
)
language sql
stable
as $$
  select
    count(*) filter (where b.status in ('confirmed', 'completed')) as total_visits,
    count(*) as total_bookings,
    max(b.start_time) filter (where b.status in ('confirmed', 'completed')) as last_visit,
    coalesce(sum(b.amount_minor) filter (where b.status in ('confirmed', 'completed')), 0) as total_amount_minor,
    coalesce(
      sum(b.amount_minor) filter (
        where b.status in ('confirmed', 'completed') and b.payment_status = 'PENDING'
      ), 0
    ) as pending_amount_minor,
    coalesce(
      jsonb_agg(distinct jsonb_build_object('sportId', s.id, 'sportName', s.name))
        filter (where s.id is not null),
      '[]'::jsonb
    ) as sports
  from bookings b
  left join facility_sports fs on fs.id = b.facility_sport_id
  left join sports s on s.id = fs.sport_id
  where b.guest_player_id = p_guest_id;
$$;

grant execute on function get_guest_stats(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- create_booking: extended to accept an optional guest_player_id. Adding a
-- parameter changes the function's argument-type signature, so `create or
-- replace` would not replace the 0009 version in place — it would sit
-- alongside it as an overload and every existing call (which passes only
-- 10 args) would then be ambiguous. Drop the old signature explicitly
-- first, then create the new one.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists create_booking(uuid, uuid, timestamptz, timestamptz, text, uuid, text, text, text, text);

create function create_booking(
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

grant execute on function create_booking(uuid, uuid, timestamptz, timestamptz, text, uuid, text, text, text, text, uuid) to authenticated;