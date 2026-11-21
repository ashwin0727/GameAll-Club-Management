-- ═════════════════════════════════════════════════════════════════════
-- DEMO VENUES: PUT BOOKINGS BACK (undo demo_venues_bookings_off.sql)
--
-- Run by hand in the Supabase SQL editor. NOT a migration.
-- Restores every court to the "booking enabled" value it had before demo_venues_bookings_off.sql ran, then clears the saved list.
-- Use it when you need the demo venues visible again, for example before you take new screenshots or if Google re-reviews the app.
-- Safe to run more than once. If demo_booking_hold does not exist, the "off" script was never run and nothing happens.
-- ═════════════════════════════════════════════════════════════════════

drop trigger if exists demo_booking_block_trg on bookings;
drop function if exists demo_booking_block();
drop trigger if exists demo_payment_block_trg on payment_orders;
drop function if exists demo_payment_block();

do $on$
declare
  v_n integer;
begin
  if to_regclass('demo_booking_hold') is null then
    raise notice 'demo_booking_hold does not exist, so nothing was switched off earlier. Nothing to do.';
    return;
  end if;

  update courts c set booking_enabled = h.was_enabled
    from demo_booking_hold h
   where c.id = h.court_id and c.booking_enabled is distinct from h.was_enabled;
  get diagnostics v_n = row_count;

  delete from demo_booking_hold where court_id in (select id from courts);
  raise notice 'Booking restored on % court(s).', v_n;
end
$on$;
