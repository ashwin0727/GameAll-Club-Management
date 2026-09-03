-- ═══════════════════════════════════════════════════════════════════════════
-- Guest Bookings shows what was actually collected.
--
-- The page read bookings.payment_status, a three-value flag — PENDING, PAID,
-- REFUNDED — and revenue was the sum of booking *amounts* whose flag said
-- PAID. That was true while every booking was paid in one go. Pending
-- Payments can now take part of a balance, and the flag has nowhere to say
-- so: a booking with ₹100 of ₹300 collected still reads PENDING, and its
-- ₹100 never reaches the revenue total.
--
-- The money is not in the flag, it is in the payments rows. Both functions
-- now count those:
--
--   revenue        = what was actually collected, part payments included
--   payment status = derived from collected against owed, so PARTIALLY_PAID
--                    can exist without widening any enum
--
-- The flag is left alone. It is still written when a booking is settled in
-- full, and other code reads it; this stops treating it as the authority on
-- how much money arrived.
-- ═══════════════════════════════════════════════════════════════════════════

drop function if exists list_guest_bookings_admin(uuid, text, uuid, uuid, text, text, date, date, integer, integer);

create function list_guest_bookings_admin(
  p_facility_id uuid,
  p_search text default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_status text default null,
  p_payment_status text default null,
  p_from date default null,
  p_to date default null,
  p_limit integer default 10,
  p_offset integer default 0
)
returns table (
  booking_id uuid,
  code text,
  guest_name text,
  guest_phone text,
  sport_name text,
  court_name text,
  start_time timestamptz,
  end_time timestamptz,
  party_size integer,
  amount_minor integer,
  paid_minor bigint,
  outstanding_minor bigint,
  currency text,
  payment_status text,
  payment_method text,
  status text,
  source text,
  total_count bigint
)
language sql
stable
as $$
  with rows as (
    select
      b.id,
      'GBK' || upper(substr(replace(b.id::text, '-', ''), 1, 4)) as code,
      coalesce(b.guest_name, 'Guest') as guest_name,
      b.guest_phone,
      coalesce(fs.custom_sport_name, sp.name) as sport_name,
      c.name as court_name,
      b.start_time,
      b.end_time,
      b.party_size,
      b.amount_minor,
      -- What actually arrived. A booking flagged PAID with no payments row
      -- behind it (create_booking accepts p_payment_status) still counts as
      -- settled, so historical rows are not reported as owing.
      greatest(
        coalesce((
          select sum(p.amount_inr) * 100 from payments p
          where p.booking_id = b.id and p.status = 'paid'
        ), 0),
        case when b.payment_status = 'PAID' then coalesce(b.amount_minor, 0) else 0 end
      )::bigint as paid_minor,
      b.currency,
      b.payment_method,
      b.status::text as status,
      'COURT'::text as source
    from bookings b
    join courts c on c.id = b.court_id
    left join facility_sports fs on fs.id = c.facility_sport_id
    left join sports sp on sp.id = fs.sport_id
    where b.facility_id = p_facility_id
      and b.customer_type = 'GUEST'
      and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or b.court_id = p_court_id)
      and (p_status is null or b.status::text = p_status)
      and (p_from is null or b.start_time::date >= p_from)
      and (p_to is null or b.start_time::date <= p_to)
      and (
        p_search is null or trim(p_search) = '' or
        b.guest_name ilike '%' || trim(p_search) || '%' or
        b.guest_phone ilike '%' || trim(p_search) || '%' or
        ('GBK' || upper(substr(replace(b.id::text, '-', ''), 1, 4))) ilike '%' || trim(p_search) || '%'
      )

    union all

    select
      msb.id,
      'GSB' || upper(substr(replace(msb.id::text, '-', ''), 1, 4)),
      coalesce(gp.name, 'Guest'),
      gp.phone,
      coalesce(fs.custom_sport_name, sp.name),
      c.name,
      (ms.session_date::text || ' ' || ms.start_time::text)::timestamp
        at time zone coalesce(f.timezone, 'Asia/Kolkata'),
      (ms.session_date::text || ' ' || ms.end_time::text)::timestamp
        at time zone coalesce(f.timezone, 'Asia/Kolkata'),
      1,
      msb.amount_minor,
      greatest(
        coalesce((
          select sum(p.amount_inr) * 100 from payments p
          where p.membership_session_booking_id = msb.id and p.status = 'paid'
        ), 0),
        case when msb.payment_status = 'PAID' then coalesce(msb.amount_minor, 0) else 0 end
      )::bigint,
      msb.currency,
      msb.payment_method,
      case when msb.status = 'CANCELLED' then 'cancelled' else 'confirmed' end,
      'SESSION'::text
    from membership_session_bookings msb
    join membership_sessions ms on ms.id = msb.session_id
    join facilities f on f.id = msb.facility_id
    join courts c on c.id = ms.court_id
    left join guest_players gp on gp.id = msb.guest_player_id
    left join facility_sports fs on fs.id = ms.facility_sport_id
    left join sports sp on sp.id = fs.sport_id
    where msb.facility_id = p_facility_id
      and msb.participant_type = 'GUEST'
      and msb.slot_source = 'RELEASED'
      and (p_facility_sport_id is null or ms.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or ms.court_id = p_court_id)
      and (
        p_status is null
        or p_status = (case when msb.status = 'CANCELLED' then 'cancelled' else 'confirmed' end)
      )
      and (p_from is null or ms.session_date >= p_from)
      and (p_to is null or ms.session_date <= p_to)
      and (
        p_search is null or trim(p_search) = '' or
        gp.name ilike '%' || trim(p_search) || '%' or
        gp.phone ilike '%' || trim(p_search) || '%' or
        ('GSB' || upper(substr(replace(msb.id::text, '-', ''), 1, 4))) ilike '%' || trim(p_search) || '%'
      )
  ),
  settled as (
    select
      r.*,
      greatest(coalesce(r.amount_minor, 0) - r.paid_minor, 0)::bigint as outstanding_minor,
      -- Derived, so a part payment has somewhere to be reported without
      -- widening the stored flag.
      case
        when r.paid_minor >= coalesce(r.amount_minor, 0) and coalesce(r.amount_minor, 0) > 0 then 'PAID'
        when r.paid_minor > 0 then 'PARTIALLY_PAID'
        else 'PENDING'
      end as derived_payment_status
    from rows r
  ),
  filtered as (
    select * from settled s
    where p_payment_status is null or s.derived_payment_status = p_payment_status
  )
  select
    f.id, f.code, f.guest_name, f.guest_phone, f.sport_name, f.court_name,
    f.start_time, f.end_time, f.party_size, f.amount_minor,
    f.paid_minor, f.outstanding_minor, f.currency,
    f.derived_payment_status, f.payment_method, f.status, f.source,
    count(*) over () as total_count
  from filtered f
  order by f.start_time desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
$$;

grant execute on function list_guest_bookings_admin(uuid, text, uuid, uuid, text, text, date, date, integer, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_guest_bookings_summary — revenue is money collected, not the value of
-- bookings whose flag says paid. Same keys as before.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_guest_bookings_summary(p_facility_id uuid, p_from date, p_to date)
returns jsonb
language sql
stable
as $$
  with span as (select (p_to - p_from) as days),
  all_rows as (
    select
      b.start_time::date as on_date,
      b.status::text as status,
      b.amount_minor,
      greatest(
        coalesce((
          select sum(p.amount_inr) * 100 from payments p
          where p.booking_id = b.id and p.status = 'paid'
        ), 0),
        case when b.payment_status = 'PAID' then coalesce(b.amount_minor, 0) else 0 end
      )::bigint as paid_minor
    from bookings b
    where b.facility_id = p_facility_id and b.customer_type = 'GUEST'
    union all
    select
      ms.session_date,
      case when msb.status = 'CANCELLED' then 'cancelled' else 'confirmed' end,
      msb.amount_minor,
      greatest(
        coalesce((
          select sum(p.amount_inr) * 100 from payments p
          where p.membership_session_booking_id = msb.id and p.status = 'paid'
        ), 0),
        case when msb.payment_status = 'PAID' then coalesce(msb.amount_minor, 0) else 0 end
      )::bigint
    from membership_session_bookings msb
    join membership_sessions ms on ms.id = msb.session_id
    where msb.facility_id = p_facility_id
      and msb.participant_type = 'GUEST'
      and msb.slot_source = 'RELEASED'
  ),
  gb as (select r.* from all_rows r, span where r.on_date between p_from and p_to),
  prev as (
    select r.* from all_rows r, span
    where r.on_date between (p_from - span.days - 1) and (p_from - 1)
  ),
  cur as (select count(*)::int as cnt, coalesce(sum(paid_minor), 0)::bigint as rev from gb),
  pre as (select count(*)::int as cnt, coalesce(sum(paid_minor), 0)::bigint as rev from prev)
  select jsonb_build_object(
    'total', (select cnt from cur),
    'confirmed', (select count(*) from gb where status = 'confirmed'),
    'completed', (select count(*) from gb where status = 'completed'),
    'cancelled', (select count(*) from gb where status = 'cancelled'),
    'pending', (select count(*) from gb where status = 'pending'),
    'totalRevenueMinor', (select rev from cur),
    'avgPerBookingMinor', coalesce((select round(avg(paid_minor)) from gb where paid_minor > 0), 0),
    'highestBookingMinor', coalesce((select max(paid_minor) from gb), 0),
    'totalChangePct', (select case when pre.cnt = 0 then null else round((cur.cnt - pre.cnt) * 100.0 / pre.cnt) end from cur, pre),
    'revenueChangePct', (select case when pre.rev = 0 then null else round((cur.rev - pre.rev) * 100.0 / pre.rev) end from cur, pre),
    'trend', coalesce((
      select jsonb_agg(jsonb_build_object('date', d, 'amountMinor', amt) order by d)
      from (
        select on_date as d, coalesce(sum(paid_minor), 0)::bigint as amt
        from gb group by on_date
      ) t
    ), '[]'::jsonb)
  );
$$;

grant execute on function get_guest_bookings_summary(uuid, date, date) to authenticated;
