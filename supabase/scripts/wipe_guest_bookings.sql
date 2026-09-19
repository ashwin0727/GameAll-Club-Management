-- ═══════════════════════════════════════════════════════════════════════════
-- ONE-TIME data wipe: every Guest Booking (bookings.customer_type = 'GUEST')
-- for YOUR facility, plus everything that hangs off it. Not a schema
-- migration — run this once, by hand, in the Supabase SQL editor.
--
-- Resolves your facility automatically from your account email (facilities
-- .owner_id → profiles.email) — no id to look up or paste. Just change
-- 'ashwinv277@gmail.com' below if that isn't the account, then run the
-- whole block.
--
-- Deletes: bookings.customer_type = 'GUEST' rows, and their `payments`
-- (which don't cascade on their own — deleting the booking would only
-- orphan them). payment_orders and refunds cascade automatically off the
-- booking delete, so nothing to do for those.
-- Leaves alone: guest_players profiles, and membership-session guest slots
-- (a different feature) — see the commented block at the bottom if you
-- want the guest profiles gone too.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

delete from payments p
using bookings b, facilities f, profiles pr
where p.booking_id = b.id
  and b.facility_id = f.id
  and f.owner_id = pr.id
  and pr.email = 'ashwinv277@gmail.com'
  and b.customer_type = 'GUEST';

delete from bookings b
using facilities f, profiles pr
where b.facility_id = f.id
  and f.owner_id = pr.id
  and pr.email = 'ashwinv277@gmail.com'
  and b.customer_type = 'GUEST';

commit;

-- OPTIONAL — also wipe the guest profiles themselves (Guest Players list
-- goes empty too, not just booking history). Run separately, after
-- confirming the delete above worked:
--
-- begin;
-- delete from guest_players gp
-- using facilities f, profiles pr
-- where gp.facility_id = f.id
--   and f.owner_id = pr.id
--   and pr.email = 'ashwinv277@gmail.com';
-- commit;
