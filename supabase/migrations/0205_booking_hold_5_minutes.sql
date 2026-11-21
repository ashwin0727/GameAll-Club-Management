-- 0205: a court held for an unpaid booking is held for 5 MINUTES, not 30.
--
-- A booking that needs a payment first (the 50% advance, or the full amount) is a PENDING hold on the court. Until now that hold lapsed
-- after 30 minutes (release_expired_booking_holds), which kept a court blocked for half an hour for a player who had walked away.
--
-- The hold time is set inside public_create_guest_booking, which has been re-created in several migrations (0131, 0132, 0188, 0189).
-- Rather than copy that large function again, this trigger caps hold_expires_at whenever a booking becomes a hold, so every path that
-- creates one (Player app, public booking page, any later version of the function) gets the same 5-minute limit.
--
-- The release itself is unchanged: release_expired_booking_holds() cancels an unpaid hold once its time is up, and it is already called
-- before availability is read, so the court shows as free again by itself. A hold with a payment that has been verified is never released.

create or replace function cap_booking_hold() returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'pending'
     and new.hold_expires_at is not null
     and (tg_op = 'INSERT'
          or old.hold_expires_at is distinct from new.hold_expires_at
          or old.status is distinct from new.status) then
    new.hold_expires_at := least(new.hold_expires_at, now() + interval '5 minutes');
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_cap_hold on bookings;
create trigger bookings_cap_hold
  before insert or update of status, hold_expires_at on bookings
  for each row execute function cap_booking_hold();

-- Holds that already exist keep a deadline of at most 5 minutes from now (the trigger applies the cap on this update).
update bookings
   set hold_expires_at = hold_expires_at
 where status = 'pending' and hold_expires_at is not null and hold_expires_at > now() + interval '5 minutes';
