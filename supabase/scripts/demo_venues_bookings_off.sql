-- ═════════════════════════════════════════════════════════════════════
-- DEMO VENUES: KEEP THEM VISIBLE, BUT NEVER TAKE REAL MONEY
--
-- Run by hand in the Supabase SQL editor. NOT a migration. Undo it with demo_venues_bookings_on.sql.
--
-- WHAT IT DOES
--   The demo venues (Smash Arena Sports Hub and the 8 extra Chennai venues) stay in the Player app exactly as they are: listed, with their
--   photos, courts, prices and free slots, so a reviewer can walk through the whole booking flow. What changes is the payment step:
--   a trigger refuses to create ANY payment order at those venues (a booking, the balance of a booking, a membership, a coaching
--   enrolment, Auto Pay). No Razorpay sheet or payment link is ever made, so no real money can be taken. Real venues are untouched.
--   Orders that already exist are not touched.
--
--   A booking that is started at a demo venue and then cannot be paid is only a short hold: it is released by itself after 5 minutes
--   (migration 0205) and nothing is charged.
--
-- IF YOU RAN AN EARLIER VERSION OF THIS SCRIPT
--   The earlier version also switched court booking OFF, which hid the venues. Running this file again puts every court back to the
--   value it had before and removes that old booking block.
--
-- Safe to run more than once.
-- ═════════════════════════════════════════════════════════════════════

-- the list of demo courts (its presence is what marks a venue as a demo venue)
create table if not exists demo_booking_hold (
  court_id    uuid primary key,
  was_enabled boolean not null
);
alter table demo_booking_hold enable row level security;   -- no policies: not readable through the API

-- the older "block bookings" trigger is no longer used
drop trigger if exists demo_booking_block_trg on bookings;
drop function if exists demo_booking_block();

-- The payment block: refuses to create a payment order for a demo venue.
create or replace function demo_payment_block() returns trigger
language plpgsql security definer set search_path = public as $f$
begin
  if exists (select 1 from courts c join demo_booking_hold h on h.court_id = c.id where c.facility_id = new.facility_id) then
    raise exception 'Payments are switched off at this venue.' using errcode = '23514';
  end if;
  return new;
end
$f$;

drop trigger if exists demo_payment_block_trg on payment_orders;
create trigger demo_payment_block_trg before insert on payment_orders for each row execute function demo_payment_block();

do $off$
declare
  v_ids uuid[] := '{}';
  v_more uuid[];
  v_n integer;
  v_restored integer;
begin
  -- the main demo venue, by name (seed2y_log does not always hold it)
  select coalesce(array_agg(id), '{}'::uuid[]) into v_more from facilities where name = 'Smash Arena Sports Hub';
  v_ids := v_ids || v_more;
  if to_regclass('seed2y_log') is not null then
    execute 'select coalesce(array_agg(id), ''{}''::uuid[]) from seed2y_log where tbl = ''facility''' into v_more;
    v_ids := v_ids || v_more;
  end if;
  -- the extra Chennai venues
  if to_regclass('seedvenues_log') is not null then
    execute 'select coalesce(array_agg(id), ''{}''::uuid[]) from seedvenues_log where tbl = ''facilities''' into v_more;
    v_ids := v_ids || v_more;
  end if;

  if coalesce(array_length(v_ids, 1), 0) = 0 then
    raise notice 'No demo venues found, so nothing was changed.';
    return;
  end if;

  -- mark every court of these venues as a demo court (the current setting is kept so the other script can restore it)
  insert into demo_booking_hold (court_id, was_enabled)
  select c.id, c.booking_enabled from courts c where c.facility_id = any (v_ids)
  on conflict (court_id) do nothing;
  get diagnostics v_n = row_count;

  -- an earlier version of this script switched booking off: put those courts back, so the venues are visible again
  update courts c set booking_enabled = h.was_enabled
    from demo_booking_hold h
   where c.id = h.court_id and c.facility_id = any (v_ids) and c.booking_enabled is distinct from h.was_enabled;
  get diagnostics v_restored = row_count;

  raise notice 'Payments are switched OFF at % demo venue(s): % court(s) newly marked, % court(s) put back to bookable. The venues stay visible.',
    (select count(distinct facility_id) from courts where id in (select court_id from demo_booking_hold)), v_n, v_restored;
end
$off$;
