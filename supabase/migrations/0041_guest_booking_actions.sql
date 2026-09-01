-- ═══════════════════════════════════════════════════════════════════════════
-- Guest Bookings — row actions from the dashboard:
--   • update_guest_booking          — Edit page (guest fields)
--   • complete_guest_booking        — "Mark as Completed"
--   • record_guest_booking_payment  — settle an offline booking payment
--   • duplicate_guest_booking       — "Duplicate Booking"
--   • delete_guest_booking          — "Delete Booking"
-- Cancel + refund reuses the existing refundService.cancelBooking path.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function update_guest_booking(
  p_booking_id uuid,
  p_guest_name text,
  p_guest_phone text,
  p_party_size integer,
  p_notes text
) returns bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  b bookings;
begin
  select * into b from bookings where id = p_booking_id;
  if b.id is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if b.customer_type <> 'GUEST' then
    raise exception 'Not a guest booking.' using errcode = '23514';
  end if;
  if not has_facility_role(b.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized.' using errcode = '42501';
  end if;
  if trim(coalesce(p_guest_name, '')) = '' then
    raise exception 'Guest name is required.' using errcode = '23514';
  end if;

  update bookings set
    guest_name = trim(p_guest_name),
    guest_phone = nullif(trim(p_guest_phone), ''),
    party_size = greatest(coalesce(p_party_size, 1), 1),
    notes = nullif(trim(p_notes), ''),
    updated_at = now()
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;
grant execute on function update_guest_booking(uuid, text, text, integer, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
create or replace function complete_guest_booking(p_booking_id uuid)
returns bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  b bookings;
begin
  select * into b from bookings where id = p_booking_id;
  if b.id is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(b.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized.' using errcode = '42501';
  end if;
  if b.status = 'cancelled' then
    raise exception 'A cancelled booking cannot be completed.' using errcode = '23514';
  end if;

  update bookings set status = 'completed', updated_at = now()
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;
grant execute on function complete_guest_booking(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- record_guest_booking_payment — the owner collected the money offline;
-- record a settled payment and flip the booking to PAID.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function record_guest_booking_payment(
  p_booking_id uuid,
  p_method text,
  p_amount_minor integer
) returns bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  b bookings;
  amt integer;
begin
  select * into b from bookings where id = p_booking_id;
  if b.id is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(b.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized.' using errcode = '42501';
  end if;
  if b.payment_status = 'PAID' then
    raise exception 'This booking is already paid.' using errcode = '23514';
  end if;

  amt := greatest(coalesce(nullif(p_amount_minor, 0), b.amount_minor, 0), 0);

  insert into payments (facility_id, member_id, booking_id, amount_inr, status, payment_method, paid_at)
  values (b.facility_id, null, b.id, round(amt / 100.0), 'paid'::payment_status, nullif(trim(p_method), ''), now());

  update bookings set payment_status = 'PAID', payment_method = coalesce(nullif(trim(p_method), ''), payment_method), updated_at = now()
  where id = p_booking_id
  returning * into b;
  return b;
end;
$$;
grant execute on function record_guest_booking_payment(uuid, text, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- duplicate_guest_booking — clone to a new time. Price is re-resolved for
-- the new window; the new booking is always PENDING (payment is a fresh
-- decision).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function duplicate_guest_booking(
  p_booking_id uuid,
  p_new_start timestamptz,
  p_new_end timestamptz
) returns bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  src bookings;
  fac facilities;
  court courts;
  price integer;
  result bookings;
begin
  select * into src from bookings where id = p_booking_id;
  if src.id is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(src.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized.' using errcode = '42501';
  end if;
  if p_new_end <= p_new_start then
    raise exception 'End time must be after start time.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = src.facility_id;
  select * into court from courts where id = src.court_id;

  if not booking_window_fits_operating_hours(src.facility_id, src.court_id, p_new_start, p_new_end) then
    raise exception 'Selected time is outside this court''s operating hours.' using errcode = '23514';
  end if;
  if court_has_active_membership_window(src.court_id, p_new_start, p_new_end, fac.timezone) then
    raise exception 'This time is reserved for a membership session.' using errcode = '23514';
  end if;

  price := resolve_booking_price(court.facility_sport_id, src.court_id, p_new_start, p_new_end, fac.timezone);

  insert into bookings (
    facility_id, court_id, member_id, start_time, end_time, status,
    customer_type, guest_name, guest_phone, guest_player_id,
    amount_minor, currency, notes, created_by, payment_status,
    party_size, payment_method
  ) values (
    src.facility_id, src.court_id, null, p_new_start, p_new_end, 'confirmed',
    'GUEST', src.guest_name, src.guest_phone, src.guest_player_id,
    price, fac.currency, src.notes, auth.uid(), 'PENDING',
    src.party_size, null
  ) returning * into result;

  return result;
end;
$$;
grant execute on function duplicate_guest_booking(uuid, timestamptz, timestamptz) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
create or replace function delete_guest_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b bookings;
begin
  select * into b from bookings where id = p_booking_id;
  if b.id is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  if b.customer_type <> 'GUEST' then
    raise exception 'Not a guest booking.' using errcode = '23514';
  end if;
  if not has_facility_role(b.facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized.' using errcode = '42501';
  end if;
  if b.payment_status = 'PAID' or exists (
    select 1 from payments p where p.booking_id = b.id and p.status in ('paid', 'refunded')
  ) then
    raise exception 'This booking has a settled payment. Cancel and refund it instead of deleting.' using errcode = '23514';
  end if;

  delete from bookings where id = p_booking_id;
end;
$$;
grant execute on function delete_guest_booking(uuid) to authenticated;
