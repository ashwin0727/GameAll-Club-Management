-- ═══════════════════════════════════════════════════════════════════════════
-- Guest court bookings: the "Pay 50% now / Pay in full" choice, and the cancellation + refund rules.
--
--   PAYMENT CHOICE
--     bookings.payment_option         'ADVANCE' (50% now, the rest later) | 'FULL' | null (a booking made before this: the old rule,
--                                     50% when longer than one hour, otherwise full)
--     booking_due_now_minor(b)        what the first online payment of a booking is
--     public_create_guest_booking     takes the choice; every booking made with a choice is held PENDING for 30 minutes until that
--                                     first payment arrives (before: only bookings longer than an hour)
--     create_payment_order / create_public_payment_order    charge booking_due_now_minor
--     set_booking_payment_option      staff records the choice on a booking they made at the club
--
--   CANCELLATION (one fixed schedule for every club; replaces the per-club 24h / 2h policy for court bookings)
--     cancellation_deduction_percent(hours)   5% with 12 h or more left ... 100% under 1 h or after the start
--     booking_cancellation_quote(booking)     what a cancellation right now would do: paid, % deducted, refund, how it is returned
--     cancel_booking                          rewritten: a booking that is only part-paid (the 50% advance) gets NO refund unless the
--                                             owner overrides; a fully paid one gets the schedule; the refund is spread over every
--                                             online payment of the booking; money taken in cash is reported as "refund due at the club"
--     staff_booking_cancellation_quote / get_my_booking_cancellation_quote / public_booking_cancellation_quote   the preview
--     player_cancel_booking / public_cancel_booking          the player's own cancellation (the app / the public page)
--     booking_cancellations                   one audit row per cancellation: the hours left, the % and the amounts
--
--   Razorpay is only ever called by the edge functions (they submit the REQUESTED refund rows this creates).
--   Re-runnable.
-- ═══════════════════════════════════════════════════════════════════════════

alter table bookings add column if not exists payment_option text;
alter table bookings drop constraint if exists bookings_payment_option_check;
alter table bookings add constraint bookings_payment_option_check check (payment_option is null or payment_option in ('ADVANCE', 'FULL'));

-- ── what the first online payment is ─────────────────────────────────────
create or replace function booking_due_now_minor(b bookings) returns integer
language sql
immutable
as $$
  select case b.payment_option
    when 'FULL' then coalesce(b.amount_minor, 0)
    when 'ADVANCE' then ceil(coalesce(b.amount_minor, 0) * 0.5)::integer
    else guest_booking_advance_minor(coalesce(b.amount_minor, 0), b.start_time, b.end_time)
  end
$$;
grant execute on function booking_due_now_minor(bookings) to authenticated, anon;

-- ── the schedule ─────────────────────────────────────────────────────────
-- Time left is measured from the moment of cancelling to the booking's start. A boundary hour (exactly 11 h left) belongs to the band
-- with the smaller deduction (10%).
create or replace function cancellation_deduction_percent(p_hours_until numeric) returns integer
language sql
immutable
as $$
  select case
    when p_hours_until >= 12 then 5
    when p_hours_until >= 11 then 10
    when p_hours_until >= 10 then 15
    when p_hours_until >= 9 then 20
    when p_hours_until >= 8 then 30
    when p_hours_until >= 7 then 40
    when p_hours_until >= 6 then 45
    when p_hours_until >= 5 then 50
    when p_hours_until >= 4 then 70
    when p_hours_until >= 3 then 75
    when p_hours_until >= 2 then 80
    when p_hours_until >= 1 then 90
    else 100
  end
$$;
grant execute on function cancellation_deduction_percent(numeric) to authenticated, anon;

-- ── the audit trail ──────────────────────────────────────────────────────
create table if not exists booking_cancellations (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  cancelled_by uuid,
  channel text not null default 'CLUB',           -- CLUB | PLAYER_APP | PUBLIC_PAGE
  hours_until_start numeric not null,
  rule text not null,                              -- UNPAID | ADVANCE_ONLY | FULL | STARTED
  deduction_percent integer not null,
  refund_percent integer not null,                 -- of what was paid (after an owner override)
  is_override boolean not null default false,
  override_reason text,
  total_minor integer not null default 0,
  paid_minor integer not null default 0,
  refund_minor integer not null default 0,
  online_refund_minor integer not null default 0,
  offline_refund_due_minor integer not null default 0,
  offline_refund_settled_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists booking_cancellations_booking_idx on booking_cancellations (booking_id);
create index if not exists booking_cancellations_facility_idx on booking_cancellations (facility_id, created_at desc);

alter table booking_cancellations enable row level security;
drop policy if exists "booking_cancellations_select_members" on booking_cancellations;
create policy "booking_cancellations_select_members" on booking_cancellations for select using (is_facility_member(facility_id));

-- ── what a booking has paid, and how much of that Razorpay can still give back ──
-- online: the captured Razorpay payments (a payment covering several bookings counts only this booking's share);
-- offline: payments staff recorded at the desk (no Razorpay payment behind them).
create or replace function booking_money_position(p_booking_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_online integer := 0;
  v_capacity integer := 0;
  v_offline integer := 0;
  r record;
  v_share integer;
  v_used integer;
begin
  for r in
    select po.id, po.amount_minor
      from payment_orders po
     where po.status in ('COMPLETED', 'SETTLEMENT_EXCEPTION', 'PARTIALLY_REFUNDED')
       and po.razorpay_payment_id is not null
       and (po.booking_id = p_booking_id or exists (select 1 from payment_order_bookings x where x.payment_order_id = po.id and x.booking_id = p_booking_id))
  loop
    select coalesce(x.amount_minor, r.amount_minor) into v_share
      from (select 1) d left join payment_order_bookings x on x.payment_order_id = r.id and x.booking_id = p_booking_id;
    select coalesce(sum(rf.amount_minor), 0) into v_used
      from refunds rf where rf.payment_order_id = r.id and rf.source_id = p_booking_id and rf.status in ('REQUESTED', 'PROCESSING', 'PENDING', 'PROCESSED');
    v_online := v_online + v_share;
    v_capacity := v_capacity + greatest(0, least(v_share - v_used, refundable_amount(r.id)));
  end loop;
  select coalesce(sum(py.amount_inr), 0) * 100 into v_offline
    from payments py where py.booking_id = p_booking_id and py.status = 'paid' and py.payment_order_id is null;
  return jsonb_build_object('onlinePaidMinor', v_online, 'onlineRefundableMinor', v_capacity, 'offlinePaidMinor', v_offline);
end;
$$;
revoke all on function booking_money_position(uuid) from public, anon, authenticated;
grant execute on function booking_money_position(uuid) to service_role;

-- ── the quote ────────────────────────────────────────────────────────────
create or replace function booking_cancellation_quote(p_booking_id uuid, p_override_percent integer default null) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  b bookings;
  m jsonb;
  v_total integer;
  v_online integer;
  v_offline integer;
  v_capacity integer;
  v_paid integer;
  v_hours numeric;
  v_rule text;
  v_deduct integer;
  v_refund_pct integer;
  v_refund integer;
  v_online_refund integer;
  v_offline_due integer;
  v_msg text;
  v_left text;
  v_h integer;
  v_min integer;
begin
  select * into b from bookings where id = p_booking_id;
  if b.id is null then return null; end if;
  m := booking_money_position(b.id);
  v_total := coalesce(b.amount_minor, 0);
  v_online := (m ->> 'onlinePaidMinor')::integer;
  v_offline := (m ->> 'offlinePaidMinor')::integer;
  v_capacity := (m ->> 'onlineRefundableMinor')::integer;
  v_paid := v_online + v_offline;
  v_hours := round((extract(epoch from (b.start_time - now())) / 3600.0)::numeric, 2);

  if v_paid <= 0 then
    v_rule := 'UNPAID'; v_deduct := 0; v_refund_pct := 0;
  elsif v_paid < v_total then
    v_rule := 'ADVANCE_ONLY'; v_deduct := 100; v_refund_pct := 0;
  elsif v_hours <= 0 then
    v_rule := 'STARTED'; v_deduct := 100; v_refund_pct := 0;
  else
    v_rule := 'FULL'; v_deduct := cancellation_deduction_percent(v_hours); v_refund_pct := 100 - v_deduct;
  end if;

  if p_override_percent is not null then
    v_refund_pct := greatest(0, least(100, p_override_percent));
    v_deduct := 100 - v_refund_pct;
  end if;

  v_refund := floor(v_paid * v_refund_pct / 100.0)::integer;
  -- the online share of the refund goes back through Razorpay, the cash share is owed at the club
  v_online_refund := case when v_paid = 0 then 0 else least(v_capacity, round(v_refund * v_online::numeric / v_paid)::integer) end;
  v_offline_due := v_refund - v_online_refund;

  if v_hours > 0 then
    v_h := floor(v_hours)::integer;
    v_min := round((v_hours - v_h) * 60)::integer;
    if v_min = 60 then v_h := v_h + 1; v_min := 0; end if;
    v_left := case when v_h > 0 and v_min > 0 then v_h || ' h ' || v_min || ' min'
                   when v_h > 0 then v_h || ' h'
                   else v_min || ' min' end;
  end if;

  v_msg := case
    when v_rule = 'UNPAID' then 'Nothing has been paid for this booking, so there is nothing to refund.'
    when p_override_percent is not null then 'The club is refunding ' || v_refund_pct || '% of what was paid.'
    when v_rule = 'ADVANCE_ONLY' then 'Only the advance has been paid. The advance is not refundable when a booking is cancelled.'
    when v_rule = 'STARTED' then 'The game has already started, so the full amount is deducted and nothing is refunded.'
    else 'The game starts in ' || v_left || '. ' || v_deduct || '% is deducted, and ' || v_refund_pct || '% of what you paid is refunded.'
  end;

  return jsonb_build_object(
    'bookingId', b.id, 'status', b.status, 'startTime', b.start_time,
    'paymentOption', b.payment_option,
    'totalMinor', v_total, 'paidMinor', v_paid, 'onlinePaidMinor', v_online, 'offlinePaidMinor', v_offline,
    'hoursUntilStart', v_hours, 'rule', v_rule,
    'deductionPercent', v_deduct, 'refundPercent', v_refund_pct,
    'deductionMinor', v_paid - v_refund, 'refundMinor', v_refund,
    'onlineRefundMinor', v_online_refund, 'offlineRefundDueMinor', v_offline_due,
    'isOverride', p_override_percent is not null,
    'message', v_msg);
end;
$$;
revoke all on function booking_cancellation_quote(uuid, integer) from public, anon, authenticated;
grant execute on function booking_cancellation_quote(uuid, integer) to service_role;

-- ── request_refund: record who asked only when that person has a profile (a player or a guest has none) ──
create or replace function request_refund(
  p_payment_order_id uuid,
  p_amount_minor integer,
  p_reason refund_reason,
  p_source_type payment_source_type,
  p_source_id uuid,
  p_is_override boolean default false,
  p_override_reason text default null,
  p_policy_percent_applied integer default null
) returns refunds
language plpgsql
security definer
set search_path = public
as $$
declare
  po payment_orders;
  txn payments;
  max_refundable integer;
  result refunds;
begin
  select * into po from payment_orders where id = p_payment_order_id for update;
  if po.id is null then
    raise exception 'Payment order not found.' using errcode = 'P0002';
  end if;
  if po.status not in ('COMPLETED', 'SETTLEMENT_EXCEPTION', 'PARTIALLY_REFUNDED') then
    raise exception 'This payment is not eligible for a refund.' using errcode = '23514';
  end if;
  if po.razorpay_payment_id is null then
    raise exception 'This payment has no captured Razorpay payment to refund.' using errcode = '23514';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Refund amount must be positive.' using errcode = '23514';
  end if;

  max_refundable := refundable_amount(po.id);
  if p_amount_minor > max_refundable then
    raise exception 'The maximum refundable amount is %.', max_refundable using errcode = '23514';
  end if;

  select id into txn from payments where payment_order_id = po.id order by created_at desc limit 1;

  begin
    insert into refunds (
      facility_id, payment_order_id, transaction_id, source_type, source_id,
      razorpay_payment_id, amount_minor, currency, reason, status,
      initiated_by, is_override, override_reason, policy_percent_applied
    ) values (
      po.facility_id, po.id, txn.id, p_source_type, p_source_id,
      po.razorpay_payment_id, p_amount_minor, po.currency, p_reason, 'REQUESTED',
      (select pr.id from profiles pr where pr.id = auth.uid()), p_is_override, p_override_reason, p_policy_percent_applied
    ) returning * into result;
  exception when unique_violation then
    select * into result from refunds
      where payment_order_id = po.id and status in ('REQUESTED', 'PROCESSING', 'PENDING')
      order by created_at desc limit 1;
    return result;
  end;

  return result;
end;
$$;
grant execute on function request_refund(uuid, integer, refund_reason, payment_source_type, uuid, boolean, text, integer) to authenticated;

-- ── the one place a booking is cancelled and its money decided ────────────
create or replace function booking_cancel_apply(
  p_booking_id uuid,
  p_reason text,
  p_override_percent integer,
  p_override_reason text,
  p_channel text,
  p_cancelled_by uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b bookings;
  q jsonb;
  m jsonb;
  v_pct integer;
  v_online_refund integer;
  v_remaining integer;
  v_total_capacity integer := 0;
  v_cap integer;
  v_amt integer;
  v_left_cap integer;
  r record;
  v_share integer;
  v_used integer;
  caps jsonb := '[]'::jsonb;
  e jsonb;
  v_refund_ids uuid[] := '{}';
  rf refunds;
begin
  select * into b from bookings where id = p_booking_id for update;
  if b.id is null then
    raise exception 'Booking not found.' using errcode = 'P0002';
  end if;
  if b.status not in ('pending', 'confirmed') then
    raise exception 'This booking cannot be cancelled.' using errcode = '23514';
  end if;

  q := booking_cancellation_quote(b.id, p_override_percent);
  v_pct := (q ->> 'refundPercent')::integer;
  v_online_refund := (q ->> 'onlineRefundMinor')::integer;

  update bookings set status = 'cancelled', cancellation_reason = p_reason where id = b.id returning * into b;

  -- spread the online refund over this booking's captured payments, each in proportion to what it can still give back
  if v_online_refund > 0 then
    for r in
      select po.id, po.amount_minor, po.source_type
        from payment_orders po
       where po.status in ('COMPLETED', 'SETTLEMENT_EXCEPTION', 'PARTIALLY_REFUNDED')
         and po.razorpay_payment_id is not null
         and (po.booking_id = b.id or exists (select 1 from payment_order_bookings x where x.payment_order_id = po.id and x.booking_id = b.id))
       order by po.created_at
    loop
      select coalesce(x.amount_minor, r.amount_minor) into v_share
        from (select 1) d left join payment_order_bookings x on x.payment_order_id = r.id and x.booking_id = b.id;
      select coalesce(sum(rf2.amount_minor), 0) into v_used
        from refunds rf2 where rf2.payment_order_id = r.id and rf2.source_id = b.id and rf2.status in ('REQUESTED', 'PROCESSING', 'PENDING', 'PROCESSED');
      v_cap := greatest(0, least(v_share - v_used, refundable_amount(r.id)));
      if v_cap > 0 then
        caps := caps || jsonb_build_array(jsonb_build_object('id', r.id, 'cap', v_cap, 'source', r.source_type));
        v_total_capacity := v_total_capacity + v_cap;
      end if;
    end loop;

    v_remaining := v_online_refund;
    v_left_cap := v_total_capacity;
    for e in select * from jsonb_array_elements(caps) loop
      v_cap := (e ->> 'cap')::integer;
      -- the last payment takes what is left, so the parts add up to the refund exactly
      v_amt := case when v_left_cap = v_cap then least(v_remaining, v_cap) else least(v_cap, round(v_online_refund * v_cap::numeric / v_total_capacity)::integer, v_remaining) end;
      v_left_cap := v_left_cap - v_cap;
      if v_amt > 0 then
        rf := request_refund(
          (e ->> 'id')::uuid, v_amt,
          case when p_override_percent is not null then 'OWNER_OVERRIDE' else 'CUSTOMER_CANCELLATION' end::refund_reason,
          (e ->> 'source')::payment_source_type, b.id,
          p_override_percent is not null, p_override_reason, v_pct);
        v_refund_ids := v_refund_ids || rf.id;
        v_remaining := v_remaining - v_amt;
      end if;
    end loop;
  end if;

  insert into booking_cancellations (
    booking_id, facility_id, cancelled_by, channel, hours_until_start, rule, deduction_percent, refund_percent,
    is_override, override_reason, total_minor, paid_minor, refund_minor, online_refund_minor, offline_refund_due_minor
  ) values (
    b.id, b.facility_id, p_cancelled_by, coalesce(p_channel, 'CLUB'), (q ->> 'hoursUntilStart')::numeric, q ->> 'rule',
    (q ->> 'deductionPercent')::integer, v_pct, p_override_percent is not null, p_override_reason,
    (q ->> 'totalMinor')::integer, (q ->> 'paidMinor')::integer, (q ->> 'refundMinor')::integer,
    coalesce(v_online_refund, 0) - coalesce(v_remaining, 0), (q ->> 'offlineRefundDueMinor')::integer
  ) on conflict (booking_id) do nothing;

  return q || jsonb_build_object('refundIds', to_jsonb(v_refund_ids));
end;
$$;
revoke all on function booking_cancel_apply(uuid, text, integer, text, text, uuid) from public, anon, authenticated;
grant execute on function booking_cancel_apply(uuid, text, integer, text, text, uuid) to service_role;

-- ── the club's own cancel (same name and shape as before) ────────────────
create or replace function cancel_booking(
  p_booking_id uuid,
  p_reason text default null,
  p_refund_override_percent integer default null,
  p_override_reason text default null
) returns bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  b bookings;
begin
  perform require_page_access_any((select t.facility_id from bookings t where t.id = p_booking_id), array['BOOKINGS_CANCEL', 'GUEST_BOOKINGS_CANCEL', 'COACHING_CANCEL_SESSION', 'MEMBERSHIPS_CANCEL']);
  perform booking_cancel_apply(p_booking_id, p_reason, p_refund_override_percent, p_override_reason, 'CLUB', auth.uid());
  select * into b from bookings where id = p_booking_id;
  return b;
end;
$$;
grant execute on function cancel_booking(uuid, text, integer, text) to authenticated;

-- the club's preview: what cancelling this booking now would do (and what each override would refund)
create or replace function staff_booking_cancellation_quote(p_booking_id uuid, p_override_percent integer default null) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform require_page_access_any((select t.facility_id from bookings t where t.id = p_booking_id), array['BOOKINGS_CANCEL', 'GUEST_BOOKINGS_CANCEL', 'BOOKINGS_VIEW', 'GUEST_BOOKINGS_VIEW', 'COACHING_CANCEL_SESSION', 'MEMBERSHIPS_CANCEL']);
  return booking_cancellation_quote(p_booking_id, p_override_percent);
end;
$$;
grant execute on function staff_booking_cancellation_quote(uuid, integer) to authenticated;

-- staff set the choice on a booking they made at the club
create or replace function set_booking_payment_option(p_booking_id uuid, p_option text) returns bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  b bookings;
begin
  perform require_page_access_any((select t.facility_id from bookings t where t.id = p_booking_id), array['BOOKINGS_CREATE', 'GUEST_BOOKINGS_CREATE', 'BOOKINGS_EDIT', 'GUEST_BOOKINGS_EDIT']);
  if p_option is not null and p_option not in ('ADVANCE', 'FULL') then
    raise exception 'Choose 50%% now or the full amount.' using errcode = '22023';
  end if;
  update bookings set payment_option = p_option where id = p_booking_id and status in ('pending', 'confirmed') returning * into b;
  if b.id is null then raise exception 'Booking not found.' using errcode = 'P0002'; end if;
  return b;
end;
$$;
grant execute on function set_booking_payment_option(uuid, text) to authenticated;

-- ── the player's own booking: who is the caller? ─────────────────────────
create or replace function player_owns_booking(p_booking_id uuid) returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_phone text;
begin
  if v_uid is null then return false; end if;
  select pl.phone into v_phone from players pl where pl.id = v_uid;
  return exists (
    select 1 from bookings b
     where b.id = p_booking_id
       and (b.member_id in (select m.id from members m where (v_phone is not null and normalize_phone(m.phone) = v_phone) or m.user_id = v_uid union select v_uid)
            or b.guest_player_id in (select g.id from guest_players g where v_phone is not null and normalize_phone(g.phone) = v_phone)
            or (b.customer_type = 'GUEST' and v_phone is not null and normalize_phone(b.guest_phone) = v_phone)));
end;
$$;
revoke all on function player_owns_booking(uuid) from public, anon;
grant execute on function player_owns_booking(uuid) to authenticated;

create or replace function get_my_booking_cancellation_quote(p_booking_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not player_owns_booking(p_booking_id) then return null; end if;
  return booking_cancellation_quote(p_booking_id, null);
end;
$$;
revoke all on function get_my_booking_cancellation_quote(uuid) from public, anon;
grant execute on function get_my_booking_cancellation_quote(uuid) to authenticated;

-- the player cancels their own booking (before it starts). The edge function then submits the REQUESTED refunds to Razorpay.
create or replace function player_cancel_booking(p_booking_id uuid, p_reason text default null) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b bookings;
begin
  if not player_owns_booking(p_booking_id) then
    raise exception 'We could not find that booking.' using errcode = 'P0002';
  end if;
  select * into b from bookings where id = p_booking_id;
  if b.status not in ('pending', 'confirmed') then
    raise exception 'This booking cannot be cancelled.' using errcode = '23514';
  end if;
  if b.start_time <= now() then
    raise exception 'This booking has already started and cannot be cancelled online. Please contact the club.' using errcode = '23514';
  end if;
  return booking_cancel_apply(p_booking_id, coalesce(nullif(btrim(p_reason), ''), 'Cancelled by the player'), null, null, 'PLAYER_APP', auth.uid());
end;
$$;
revoke all on function player_cancel_booking(uuid, text) from public, anon;
grant execute on function player_cancel_booking(uuid, text) to authenticated;

-- ── the public booking page (a guest, identified by the booking id plus the phone number it was made with) ──
create or replace function public_booking_cancellation_quote(p_booking_id uuid, p_phone text) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_digits text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10);
begin
  if length(v_digits) < 10 then return null; end if;
  if not exists (
    select 1 from bookings b join guest_players g on g.id = b.guest_player_id
     where b.id = p_booking_id and b.customer_type = 'GUEST' and right(regexp_replace(coalesce(g.phone, ''), '\D', '', 'g'), 10) = v_digits) then
    return null;
  end if;
  return booking_cancellation_quote(p_booking_id, null);
end;
$$;
grant execute on function public_booking_cancellation_quote(uuid, text) to anon, authenticated;

-- callable only by the public-cancel-booking edge function (service role), which also submits the refunds
create or replace function public_cancel_booking(p_booking_id uuid, p_phone text) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10);
  b bookings;
begin
  if length(v_digits) < 10 or not exists (
    select 1 from bookings x join guest_players g on g.id = x.guest_player_id
     where x.id = p_booking_id and x.customer_type = 'GUEST' and right(regexp_replace(coalesce(g.phone, ''), '\D', '', 'g'), 10) = v_digits) then
    raise exception 'We could not find that booking.' using errcode = 'P0002';
  end if;
  select * into b from bookings where id = p_booking_id;
  if b.status not in ('pending', 'confirmed') then
    raise exception 'This booking cannot be cancelled.' using errcode = '23514';
  end if;
  if b.start_time <= now() then
    raise exception 'This booking has already started and cannot be cancelled online. Please contact the club.' using errcode = '23514';
  end if;
  return booking_cancel_apply(p_booking_id, 'Cancelled by the guest', null, null, 'PUBLIC_PAGE', null);
end;
$$;
revoke all on function public_cancel_booking(uuid, text) from public, anon, authenticated;
grant execute on function public_cancel_booking(uuid, text) to service_role;

-- the player's own list of "refunds still owed at the club", for the club's refunds page
create or replace function settle_offline_refund(p_booking_id uuid) returns booking_cancellations
language plpgsql
security definer
set search_path = public
as $$
declare
  c booking_cancellations;
begin
  perform require_page_access_any((select t.facility_id from bookings t where t.id = p_booking_id), array['BOOKINGS_CANCEL', 'GUEST_BOOKINGS_CANCEL', 'BOOKINGS_EDIT', 'GUEST_BOOKINGS_EDIT']);
  update booking_cancellations set offline_refund_settled_at = now()
   where booking_id = p_booking_id and offline_refund_due_minor > 0 and offline_refund_settled_at is null
   returning * into c;
  if c.id is null then raise exception 'There is no refund due at the club for this booking.' using errcode = 'P0002'; end if;
  return c;
end;
$$;
grant execute on function settle_offline_refund(uuid) to authenticated;


-- ── create_payment_order (was 0130): the first payment of a guest booking is booking_due_now_minor ──
create or replace function create_payment_order(
  p_facility_id uuid,
  p_source_type payment_source_type,
  p_booking_id uuid default null,
  p_membership_session_booking_id uuid default null,
  p_member_id uuid default null,
  p_plan_id uuid default null,
  p_advance boolean default false
) returns payment_orders
language plpgsql
as $$
declare
  result payment_orders;
  existing payment_orders;
  fac facilities;
  b bookings;
  msb membership_session_bookings;
  plan membership_plans;
  computed_amount integer;
  computed_member_id uuid;
begin
  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    raise exception 'Facility not found.' using errcode = '23503';
  end if;

  if p_source_type = 'MEMBERSHIP' then
    if p_member_id is null or p_plan_id is null then
      raise exception 'A member and a plan are required for a membership payment.' using errcode = '23514';
    end if;
    select * into plan from membership_plans where id = p_plan_id and facility_id = p_facility_id and is_active;
    if plan.id is null then
      raise exception 'That membership plan is not available for this facility.' using errcode = '23503';
    end if;
    if not exists (select 1 from members where id = p_member_id and facility_id = p_facility_id) then
      raise exception 'That member does not belong to this facility.' using errcode = '23503';
    end if;
    computed_amount := plan.price_inr * 100;
    computed_member_id := p_member_id;

  elsif p_source_type = 'MEMBER_BOOKING' then
    if p_booking_id is null then
      raise exception 'A booking is required for a member booking payment.' using errcode = '23514';
    end if;
    select * into b from bookings where id = p_booking_id and facility_id = p_facility_id;
    if b.id is null then
      raise exception 'That booking does not belong to this facility.' using errcode = '23503';
    end if;
    if b.customer_type <> 'MEMBER' or b.member_id is null then
      raise exception 'That booking is not a member booking.' using errcode = '23514';
    end if;
    if b.status not in ('pending', 'confirmed') then
      raise exception 'That booking is no longer active.' using errcode = '23514';
    end if;
    if b.amount_minor is null or b.amount_minor <= 0 then
      raise exception 'That booking has no payable amount.' using errcode = '23514';
    end if;
    computed_amount := b.amount_minor;
    computed_member_id := b.member_id;

  elsif p_source_type = 'GUEST_BOOKING' then
    if (p_booking_id is not null) = (p_membership_session_booking_id is not null) then
      raise exception 'Provide exactly one of a booking or a membership guest-slot booking.' using errcode = '23514';
    end if;

    if p_booking_id is not null then
      select * into b from bookings where id = p_booking_id and facility_id = p_facility_id;
      if b.id is null then
        raise exception 'That booking does not belong to this facility.' using errcode = '23503';
      end if;
      if b.customer_type <> 'GUEST' then
        raise exception 'That booking is not a guest booking.' using errcode = '23514';
      end if;
      if b.status not in ('pending', 'confirmed') then
        raise exception 'That booking is no longer active.' using errcode = '23514';
      end if;
      if b.amount_minor is null or b.amount_minor <= 0 then
        raise exception 'That booking has no payable amount.' using errcode = '23514';
      end if;
      computed_amount := b.amount_minor;
      -- Longer than an hour: only the advance is collected online.
      if p_advance then
        computed_amount := booking_due_now_minor(b);
      end if;
    else
      select * into msb from membership_session_bookings where id = p_membership_session_booking_id and facility_id = p_facility_id;
      if msb.id is null then
        raise exception 'That guest slot booking does not belong to this facility.' using errcode = '23503';
      end if;
      if msb.participant_type <> 'GUEST' or msb.status <> 'CONFIRMED' then
        raise exception 'That guest slot booking is not active.' using errcode = '23514';
      end if;
      if msb.amount_minor is null or msb.amount_minor <= 0 then
        raise exception 'That guest slot booking has no payable amount.' using errcode = '23514';
      end if;
      computed_amount := msb.amount_minor;
    end if;
  end if;

  select * into existing from payment_orders
    where facility_id = p_facility_id
      and source_type = p_source_type
      and status in ('CREATED', 'ORDER_CREATED', 'PAYMENT_ATTEMPTED', 'AUTHORIZED')
      and expires_at > now()
      and booking_id is not distinct from p_booking_id
      and membership_session_booking_id is not distinct from p_membership_session_booking_id
      and amount_minor = computed_amount
      and (p_source_type <> 'MEMBERSHIP' or (member_id = p_member_id and plan_id = p_plan_id))
    order by created_at desc
    limit 1;
  if existing.id is not null then
    return existing;
  end if;

  insert into payment_orders (
    facility_id, source_type, booking_id, membership_session_booking_id, member_id, plan_id,
    amount_minor, currency, status, receipt, expires_at, created_by
  ) values (
    p_facility_id, p_source_type, p_booking_id, p_membership_session_booking_id, computed_member_id, p_plan_id,
    computed_amount, coalesce(fac.currency, 'INR'), 'CREATED',
    'GAMEALL-' || replace(p_source_type::text, '_', '') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
    now() + interval '15 minutes', auth.uid()
  ) returning * into result;

  return result;
end;
$$;

grant execute on function create_payment_order(uuid, payment_source_type, uuid, uuid, uuid, uuid, boolean) to authenticated;

-- ── create_public_payment_order (was 0132) ──
create or replace function create_public_payment_order(p_booking_ids uuid[]) returns payment_orders
language plpgsql
as $$
declare
  ids uuid[];
  b bookings;
  first_b bookings;
  fac facilities;
  amounts integer[] := '{}';
  total integer := 0;
  n integer;
  i integer;
  existing payment_orders;
  result payment_orders;
begin
  select array_agg(x order by x) into ids from (select distinct unnest(p_booking_ids) as x) d;
  n := coalesce(array_length(ids, 1), 0);
  if n = 0 or n > 12 then
    raise exception 'Choose between 1 and 12 bookings to pay for.' using errcode = '23514';
  end if;

  for i in 1..n loop
    select * into b from bookings where id = ids[i] for update;
    if b.id is null or b.customer_type <> 'GUEST' then
      raise exception 'That booking could not be found.' using errcode = '23503';
    end if;
    if i = 1 then
      first_b := b;
    elsif b.facility_id <> first_b.facility_id or b.guest_player_id is distinct from first_b.guest_player_id then
      raise exception 'Those bookings do not belong together.' using errcode = '23514';
    end if;
    if b.status <> 'pending' or b.hold_expires_at is null or b.hold_expires_at <= now() then
      raise exception 'That booking is no longer being held for payment.' using errcode = '23514';
    end if;
    if (b.payment_option is null and b.end_time - b.start_time <= interval '1 hour') or coalesce(b.amount_minor, 0) <= 0 then
      raise exception 'That booking does not need an online advance.' using errcode = '23514';
    end if;
    amounts[i] := booking_due_now_minor(b);
    total := total + amounts[i];
  end loop;

  select * into fac from facilities where id = first_b.facility_id;

  -- The same bookings already have an open order for this exact amount: hand it back, never a second one.
  select po.* into existing
  from payment_orders po
  where po.booking_id = ids[1]
    and po.source_type = 'GUEST_BOOKING'
    and po.status in ('CREATED', 'ORDER_CREATED', 'PAYMENT_ATTEMPTED', 'AUTHORIZED')
    and po.expires_at > now()
    and po.amount_minor = total
    and (select count(*) from payment_order_bookings x where x.payment_order_id = po.id) = n
    and not exists (select 1 from payment_order_bookings x where x.payment_order_id = po.id and x.booking_id <> all (ids))
  order by po.created_at desc
  limit 1;
  if existing.id is not null then
    return existing;
  end if;

  insert into payment_orders (
    facility_id, source_type, booking_id, amount_minor, currency, status, receipt, expires_at, created_by
  ) values (
    first_b.facility_id, 'GUEST_BOOKING', ids[1], total, coalesce(fac.currency, 'INR'), 'CREATED',
    'GAMEALL-GUESTBOOKING-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
    now() + interval '15 minutes', null
  ) returning * into result;

  for i in 1..n loop
    insert into payment_order_bookings (payment_order_id, booking_id, amount_minor) values (result.id, ids[i], amounts[i]);
  end loop;

  return result;
end;
$$;

revoke all on function create_public_payment_order(uuid[]) from public, anon, authenticated;
grant execute on function create_public_payment_order(uuid[]) to service_role;

-- ── public_create_guest_booking (was 0131): the 50% / full choice ──
drop function if exists public_create_guest_booking(uuid, uuid, timestamptz, timestamptz, text, text, text, text, text, integer);
create or replace function public_create_guest_booking(
  p_facility_id uuid,
  p_court_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_name text,
  p_phone text,
  p_email text default null,
  p_purpose text default null,
  p_notes text default null,
  p_party_size integer default 1,
  p_payment_option text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  fac facilities;
  court courts;
  tz text;
  guest guest_players;
  digits text;
  booking bookings;
  session_booking membership_session_bookings;
  batch membership_batches;
  session_row membership_sessions;
  guest_booked integer;
  combined_notes text;
  booking_code text;
  amount integer;
  sport_name text;
  unpaid_pending integer;
  v_option text := nullif(upper(btrim(coalesce(p_payment_option, ''))), '');
begin
  if v_option is not null and v_option not in ('ADVANCE', 'FULL') then
    raise exception 'Choose 50%% now or the full amount.' using errcode = '23514';
  end if;
  -- Free any court time held for an advance that never arrived, so it can be booked again.
  perform release_expired_booking_holds();

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Please enter your name.' using errcode = '23514';
  end if;

  digits := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  if length(digits) < 10 or length(digits) > 15 then
    raise exception 'Please enter a valid mobile number.' using errcode = '23514';
  end if;

  select * into fac from facilities where id = p_facility_id;
  if fac.id is null then
    raise exception 'We could not find that venue.' using errcode = '23503';
  end if;
  tz := coalesce(fac.timezone, 'Asia/Kolkata');

  select * into court from courts
  where id = p_court_id and facility_id = p_facility_id and not archived;
  if court.id is null then
    raise exception 'We could not find that court.' using errcode = '23503';
  end if;

  if p_end_time <= p_start_time then
    raise exception 'Please choose a valid time.' using errcode = '23514';
  end if;
  if p_start_time <= now() then
    raise exception 'That time has already passed. Please choose another time.' using errcode = '23514';
  end if;

  select coalesce(fs.custom_sport_name, sp.name) into sport_name
  from facility_sports fs
  left join sports sp on sp.id = fs.sport_id
  where fs.id = court.facility_sport_id;

  combined_notes := nullif(trim(concat_ws(
    ' — ',
    nullif(trim(coalesce(p_purpose, '')), ''),
    nullif(trim(coalesce(p_notes, '')), '')
  )), '');

  guest := find_or_create_guest(p_facility_id, p_name, p_phone, nullif(trim(coalesce(p_email, '')), ''), null);

  -- Standing-capacity cap: no more than 4 unpaid, not-yet-started court
  -- bookings per guest per facility. Paid or past bookings never count.
  select count(*) into unpaid_pending
  from bookings b
  where b.guest_player_id = guest.id
    and b.customer_type = 'GUEST'
    and b.status in ('pending', 'confirmed')
    and b.payment_status = 'PENDING'
    and b.start_time > now();
  if unpaid_pending >= 4 then
    raise exception 'You have unpaid bookings still pending. Please complete or cancel them before booking again.'
      using errcode = '23514';
  end if;

  if court_has_active_membership_window(p_court_id, p_start_time, p_end_time, tz) then
    select mb.* into batch
    from membership_batches mb
    where mb.court_id = p_court_id
      and mb.is_active
      and extract(dow from (p_start_time at time zone tz)) = any(mb.days_of_week)
      and mb.start_time < (p_end_time at time zone tz)::time
      and mb.end_time > (p_start_time at time zone tz)::time
    limit 1;

    if batch.id is null then
      raise exception 'Sorry, this court is no longer available.' using errcode = '23514';
    end if;

    begin
      session_booking := book_guest_slot(batch.id, (p_start_time at time zone tz)::date, guest.id);
    exception
      when others then
        raise exception 'Sorry, this court is no longer available.' using errcode = '23514';
    end;

    select * into session_row from membership_sessions where id = session_booking.session_id;
    booking_code := 'GSB' || upper(substr(replace(session_booking.id::text, '-', ''), 1, 4));
    amount := session_booking.amount_minor;

    return jsonb_build_object(
      'bookingId', session_booking.id,
      'code', booking_code,
      'facilityName', fac.name,
      'sportName', coalesce(sport_name, 'Sport'),
      'courtName', court.name,
      'startTime', p_start_time,
      'endTime', p_end_time,
      'guestName', guest.name,
      'guestPhone', guest.phone,
      'amountMinor', coalesce(amount, 0),
      'currency', coalesce(fac.currency, 'INR'),
      'paymentStatus', 'PENDING',
      'bookingStatus', 'CONFIRMED'
    );
  end if;

  begin
    booking := create_booking(
      p_facility_id := p_facility_id,
      p_court_id := p_court_id,
      p_start_time := p_start_time,
      p_end_time := p_end_time,
      p_customer_type := 'GUEST',
      p_member_id := null,
      p_guest_name := null,
      p_guest_phone := null,
      p_notes := combined_notes,
      p_payment_status := 'PENDING',
      p_guest_player_id := guest.id,
      p_party_size := greatest(coalesce(p_party_size, 1), 1),
      p_payment_method := null
    );
  exception
    when exclusion_violation then
      raise exception 'Sorry, this court is no longer available.' using errcode = '23514';
    when check_violation then
      raise exception 'Sorry, this court is no longer available.' using errcode = '23514';
  end;

  -- A booking longer than an hour is only accepted once its 50% advance is paid online: until then it is a PENDING
  -- hold on the court that lapses after 30 minutes (release_expired_booking_holds). The payment settles it to CONFIRMED.
  -- A booking made with a payment choice is held for its first payment whatever its length.
  if v_option is not null or booking.end_time - booking.start_time > interval '1 hour' then
    update bookings
      set status = 'pending', hold_expires_at = now() + interval '30 minutes', payment_option = v_option
      where id = booking.id
      returning * into booking;
  end if;

  booking_code := 'GBK' || upper(substr(replace(booking.id::text, '-', ''), 1, 4));

  return jsonb_build_object(
    'bookingId', booking.id,
    'code', booking_code,
    'facilityName', fac.name,
    'sportName', coalesce(sport_name, 'Sport'),
    'courtName', court.name,
    'startTime', booking.start_time,
    'endTime', booking.end_time,
    'guestName', guest.name,
    'guestPhone', guest.phone,
    'amountMinor', coalesce(booking.amount_minor, 0),
    'currency', coalesce(booking.currency, 'INR'),
    'paymentStatus', booking.payment_status,
    'bookingStatus', booking.status,
    'advanceRequired', booking.hold_expires_at is not null,
    'advanceMinor', case when booking.hold_expires_at is not null then booking_due_now_minor(booking) else 0 end,
    'paymentOption', booking.payment_option,
    'holdExpiresAt', booking.hold_expires_at
  );
end;
$$;

grant execute on function public_create_guest_booking(uuid, uuid, timestamptz, timestamptz, text, text, text, text, text, integer, text) to anon, authenticated;

-- ── cash the club still owes back (the Refunds page lists these) ─────────────
create or replace function list_offline_refunds_due(p_facility_id uuid, p_include_settled boolean default false) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform require_page_access_any(p_facility_id, array['BOOKINGS_VIEW', 'GUEST_BOOKINGS_VIEW', 'BOOKINGS_CANCEL', 'GUEST_BOOKINGS_CANCEL']);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'bookingId', c.booking_id,
             'guestName', coalesce(g.name, b.guest_name),
             'guestPhone', coalesce(g.phone, b.guest_phone),
             'startTime', b.start_time,
             'refundDueMinor', c.offline_refund_due_minor,
             'settledAt', c.offline_refund_settled_at,
             'cancelledAt', c.created_at) order by c.created_at desc)
      from booking_cancellations c
      join bookings b on b.id = c.booking_id
      left join guest_players g on g.id = b.guest_player_id
     where c.facility_id = p_facility_id
       and c.offline_refund_due_minor > 0
       and (p_include_settled or c.offline_refund_settled_at is null)
  ), '[]'::jsonb);
end;
$$;
grant execute on function list_offline_refunds_due(uuid, boolean) to authenticated;
