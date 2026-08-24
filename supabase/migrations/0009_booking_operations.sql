-- ═══════════════════════════════════════════════════════════════════════════
-- Booking Operations — closes the two real gaps the redesigned
-- availability-first Booking UI needs that 0007_bookings.sql didn't cover:
-- a lightweight payment flag captured at booking time (the Quick Booking
-- flow's "Paid / Pending" toggle), and a reschedule path that revalidates
-- the new slot the same way creation does rather than trusting the client.
--
-- Everything else (courts, pricing, operating hours, the exclusion
-- constraint that prevents double-booking, RLS) is reused as-is.
-- ═══════════════════════════════════════════════════════════════════════════

alter table bookings
  add column payment_status text not null default 'PENDING' check (payment_status in ('PENDING', 'PAID', 'REFUNDED')),
  add column cancellation_reason text;

-- ─────────────────────────────────────────────────────────────────────────
-- create_booking: extended (replace, not a new function) to accept the
-- payment status captured at booking time. Same validation/pricing/
-- conflict-prevention as before.
-- ─────────────────────────────────────────────────────────────────────────
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
  p_payment_status text default 'PENDING'
) returns bookings
language plpgsql
as $$
declare
  result bookings;
  fac facilities;
  court courts;
  price integer;
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

  if not booking_window_fits_operating_hours(p_facility_id, p_court_id, p_start_time, p_end_time) then
    raise exception 'Selected time is outside this court''s operating hours.' using errcode = '23514';
  end if;

  price := resolve_booking_price(court.facility_sport_id, p_court_id, p_start_time, p_end_time, fac.timezone);

  insert into bookings (
    facility_id, court_id, member_id, start_time, end_time, status,
    customer_type, guest_name, guest_phone, amount_minor, currency, notes, created_by, payment_status
  ) values (
    p_facility_id, p_court_id, p_member_id, p_start_time, p_end_time, 'confirmed',
    coalesce(p_customer_type, 'MEMBER'), p_guest_name, p_guest_phone, price, fac.currency, p_notes, auth.uid(),
    coalesce(p_payment_status, 'PENDING')
  ) returning * into result;

  return result;
end;
$$;

grant execute on function create_booking(uuid, uuid, timestamptz, timestamptz, text, uuid, text, text, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- reschedule_booking: moves an existing (pending/confirmed) booking to a
-- new time on the same or a different court, re-running every check
-- create_booking would run — operating hours, and the exclusion constraint
-- (which fires on this UPDATE exactly as it would on an INSERT, since it's
-- a table-level constraint, not insert-only). Re-resolves price for the new
-- window rather than keeping the old amount. History is preserved: this
-- updates the existing row rather than cancel-and-recreate, so the booking
-- keeps its id/created_at/created_by.
-- ─────────────────────────────────────────────────────────────────────────
create function reschedule_booking(
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

grant execute on function reschedule_booking(uuid, uuid, timestamptz, timestamptz) to authenticated;