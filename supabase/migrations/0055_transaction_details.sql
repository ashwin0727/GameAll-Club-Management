-- ═══════════════════════════════════════════════════════════════════════════
-- Transaction details, and the fields a receipt needs.
--
-- record_obligation_payment accepted p_reference and p_notes and then threw
-- them away: payments had nowhere to put them. So the UPI reference a staff
-- member carefully typed in vanished, and a receipt could never quote it.
-- That is fixed here, along with who recorded the payment — the two things
-- a receipt is asked to prove after the fact.
-- ═══════════════════════════════════════════════════════════════════════════

alter table payments
  add column if not exists reference text,
  add column if not exists notes text,
  add column if not exists recorded_by uuid references profiles (id) on delete set null;


-- Store what the caller was already sending.
create or replace function record_obligation_payment(
  p_source_type text,
  p_source_id uuid,
  p_amount_minor integer,
  p_method text,
  p_paid_on date default null,
  p_reference text default null,
  p_notes text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_facility uuid;
  v_total bigint;
  v_paid bigint;
  v_outstanding bigint;
  v_membership uuid;
  v_booking uuid;
  v_existing payments;
  v_paid_at timestamptz;
begin
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Enter an amount greater than zero.' using errcode = '23514';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from payments where idempotency_key = p_idempotency_key;
    if v_existing.id is not null then
      return jsonb_build_object('paymentId', v_existing.id, 'duplicate', true);
    end if;
  end if;

  if p_source_type in ('BOOKING', 'GUEST_BOOKING') then
    select b.facility_id, coalesce(b.amount_minor, 0)::bigint
      into v_facility, v_total
      from bookings b where b.id = p_source_id
      for update;
    v_booking := p_source_id;
  elsif p_source_type = 'MEMBERSHIP' then
    select ms.facility_id, (coalesce(ms.total_amount_inr, 0) * 100)::bigint
      into v_facility, v_total
      from memberships ms where ms.id = p_source_id
      for update;
    v_membership := p_source_id;
  else
    raise exception 'Unknown payment source.' using errcode = '22023';
  end if;

  if v_facility is null then
    raise exception 'That record no longer exists.' using errcode = 'P0002';
  end if;

  if not has_facility_role(v_facility, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  select coalesce(sum(p.amount_inr) * 100, 0)::bigint into v_paid
    from payments p
   where p.status = 'paid'
     and ((v_booking is not null and p.booking_id = v_booking)
       or (v_membership is not null and p.membership_id = v_membership));

  v_outstanding := v_total - v_paid;

  if v_outstanding <= 0 then
    raise exception 'This has already been paid in full.' using errcode = '23514';
  end if;

  if p_amount_minor > v_outstanding then
    raise exception 'Outstanding amount has changed. Only % remains.', (v_outstanding / 100.0)
      using errcode = '23514';
  end if;

  v_paid_at := case
    when p_paid_on is null or p_paid_on = current_date then now()
    else p_paid_on::timestamp + time '12:00'
  end;

  insert into payments (
    facility_id, member_id, booking_id, membership_id,
    amount_inr, status, payment_method, paid_at, idempotency_key,
    reference, notes, recorded_by
  ) values (
    v_facility, null, v_booking, v_membership,
    round(p_amount_minor / 100.0), 'paid'::payment_status,
    nullif(trim(p_method), ''), v_paid_at, p_idempotency_key,
    nullif(trim(p_reference), ''), nullif(trim(p_notes), ''), auth.uid()
  );

  if v_booking is not null and (v_paid + p_amount_minor) >= v_total then
    update bookings
       set payment_status = 'PAID',
           payment_method = coalesce(nullif(trim(p_method), ''), payment_method),
           updated_at = now()
     where id = v_booking;
  end if;

  return jsonb_build_object(
    'duplicate', false,
    'totalMinor', v_total,
    'paidMinor', v_paid + p_amount_minor,
    'outstandingMinor', v_total - (v_paid + p_amount_minor)
  );
end;
$$;

grant execute on function record_obligation_payment(text, uuid, integer, text, date, text, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- Everything the Transaction Details page and its receipt render.
--
-- Payment history is every payment against the same source, not just this
-- one: a part-paid booking's receipt is meaningless without the other
-- instalments beside it.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_transaction_details(p_transaction_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v finance_transactions_view;
  fac facilities;
  v_recorded_by text;
  v_booking_code text;
  v_description text;
begin
  select * into v from finance_transactions_view where id = p_transaction_id;
  if v.id is null then
    raise exception 'Transaction not found.' using errcode = 'P0002';
  end if;
  if not has_facility_role(v.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  select * into fac from facilities where id = v.facility_id;

  select pr.full_name into v_recorded_by
    from payments p left join profiles pr on pr.id = p.recorded_by
   where p.id = v.id;

  if v.booking_id is not null then
    select
      'BOOK-' || upper(substr(replace(b.id::text, '-', ''), 1, 6)),
      concat_ws(' ',
        case when b.customer_type = 'GUEST' then 'Guest booking' else 'Court booking' end,
        'payment for', c.name)
      into v_booking_code, v_description
      from bookings b
      left join courts c on c.id = b.court_id
     where b.id = v.booking_id;
  elsif v.membership_id is not null then
    select 'MEM-' || upper(substr(replace(ms.id::text, '-', ''), 1, 6)),
           concat_ws(' ', 'Membership payment —', coalesce(ms.name, mp.name, 'Membership'))
      into v_booking_code, v_description
      from memberships ms
      left join membership_plans mp on mp.id = ms.plan_id
     where ms.id = v.membership_id;
  end if;

  return jsonb_build_object(
    'id', v.id,
    'reference', v.reference,
    'sourceType', v.source_type,
    'category', case v.source_type
      when 'GUEST_BOOKING' then 'Guest Booking Revenue'
      when 'MEMBERSHIP' then 'Membership Revenue'
      when 'MEMBER_BOOKING' then 'Court Booking Revenue'
      else 'Other Revenue' end,
    'type', 'INCOME',
    'amountMinor', v.amount_minor,
    'currency', v.currency,
    'status', v.status,
    'paymentMethod', v.payment_method,
    'occurredAt', v.effective_at,
    'createdAt', v.created_at,
    'recordedBy', v_recorded_by,
    'description', coalesce(v_description, 'Payment'),
    'sourceReference', v_booking_code,
    'customerName', v.customer_name,
    'customerPhone', v.customer_phone,
    'facilityName', fac.name,
    'facilityId', v.facility_id,
    'bookingId', v.booking_id,
    'membershipId', v.membership_id,
    'refundedMinor', v.refunded_minor,
    'netMinor', v.net_minor,
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'paidAt', coalesce(p.paid_at, p.created_at),
        'amountMinor', (p.amount_inr * 100),
        'paymentMethod', p.payment_method,
        'reference', p.reference,
        'status', p.status::text,
        'isThisOne', p.id = v.id
      ) order by coalesce(p.paid_at, p.created_at))
      from payments p
      where p.status = 'paid'
        and ((v.booking_id is not null and p.booking_id = v.booking_id)
          or (v.membership_id is not null and p.membership_id = v.membership_id)
          or (v.booking_id is null and v.membership_id is null and p.id = v.id))
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function get_transaction_details(uuid) to authenticated;
