-- ═══════════════════════════════════════════════════════════════════════════
-- Backfill Guest Players from existing bookings
--
-- 0011_guest_players.sql added the guest_players table and wired
-- find_or_create_guest into the booking flow going forward, but every guest
-- booking made BEFORE that (or before the mobile app actually started
-- calling it) still only has free-text guest_name/guest_phone on `bookings`
-- with guest_player_id left null — so Guest Players shows only the handful
-- of guests created there directly, not everyone who has ever booked.
--
-- This is a one-time catch-up: for every unlinked guest booking, find or
-- create the matching guest_players row and set guest_player_id, using the
-- exact same "digits-only phone, scoped per facility" identity rule as
-- find_or_create_guest and the guest_players_facility_phone_idx unique
-- index — two bookings with the same phone number (however it was typed)
-- collapse onto one guest, same as they would going forward.
--
-- A booking with NO phone at all (guest_phone blank) can't be matched that
-- way, so as a fallback those are grouped by facility + exact name instead.
-- This is weaker — two different "Rahul"s with no phone on file WILL merge
-- into one profile — but it is strictly better than leaving them all
-- invisible, and it only applies to the phone-less minority; anyone with a
-- phone number on the booking is matched by that alone.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── pass 1: bookings that have a phone number ──────────────────────────────

with unlinked as (
  select
    b.id as booking_id,
    b.facility_id,
    b.guest_name,
    b.start_time,
    regexp_replace(coalesce(b.guest_phone, ''), '\D', '', 'g') as norm_phone
  from bookings b
  where b.customer_type = 'GUEST'
    and b.guest_player_id is null
    and regexp_replace(coalesce(b.guest_phone, ''), '\D', '', 'g') <> ''
),
-- One canonical name per (facility, phone) — the most recent booking's
-- guest_name wins, since that's the freshest thing the owner actually typed
-- for this person.
canonical as (
  select distinct on (facility_id, norm_phone)
    facility_id, norm_phone, guest_name
  from unlinked
  order by facility_id, norm_phone, start_time desc
)
insert into guest_players (facility_id, name, phone)
select c.facility_id, c.guest_name, c.norm_phone
from canonical c
where not exists (
  select 1 from guest_players gp
  where gp.facility_id = c.facility_id
    and regexp_replace(coalesce(gp.phone, ''), '\D', '', 'g') = c.norm_phone
);

update bookings b
set guest_player_id = gp.id
from guest_players gp
where b.customer_type = 'GUEST'
  and b.guest_player_id is null
  and regexp_replace(coalesce(b.guest_phone, ''), '\D', '', 'g') <> ''
  and gp.facility_id = b.facility_id
  and regexp_replace(coalesce(gp.phone, ''), '\D', '', 'g')
      = regexp_replace(coalesce(b.guest_phone, ''), '\D', '', 'g');

-- ── pass 2: bookings with no phone at all — fall back to exact name ────────

with unlinked_noph as (
  select
    b.id as booking_id,
    b.facility_id,
    b.guest_name,
    b.start_time,
    lower(trim(b.guest_name)) as norm_name
  from bookings b
  where b.customer_type = 'GUEST'
    and b.guest_player_id is null
    and regexp_replace(coalesce(b.guest_phone, ''), '\D', '', 'g') = ''
    and trim(coalesce(b.guest_name, '')) <> ''
),
canonical_noph as (
  select distinct on (facility_id, norm_name)
    facility_id, norm_name, guest_name
  from unlinked_noph
  order by facility_id, norm_name, start_time desc
)
insert into guest_players (facility_id, name)
select c.facility_id, c.guest_name
from canonical_noph c
where not exists (
  select 1 from guest_players gp
  where gp.facility_id = c.facility_id
    and gp.phone is null
    and lower(trim(gp.name)) = c.norm_name
);

update bookings b
set guest_player_id = gp.id
from guest_players gp
where b.customer_type = 'GUEST'
  and b.guest_player_id is null
  and regexp_replace(coalesce(b.guest_phone, ''), '\D', '', 'g') = ''
  and trim(coalesce(b.guest_name, '')) <> ''
  and gp.facility_id = b.facility_id
  and gp.phone is null
  and lower(trim(gp.name)) = lower(trim(b.guest_name));
