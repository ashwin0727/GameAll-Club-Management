-- ═══════════════════════════════════════════════════════════════════════════
-- Released-capacity guest bookings: visible to admin, and payable.
--
-- A guest who takes a seat the owner released from a membership session is
-- recorded in membership_session_bookings, not in bookings — a bookings row
-- cannot represent shared capacity, because bookings_no_overlap forbids two
-- live rows on the same court and time. That is correct, but it left two
-- holes once the public flow could create such bookings:
--
--   1. they never appeared on the admin Guest Bookings page
--   2. there was no way to record the cash taken at the venue, so they
--      never reached Finance
--
-- This closes both, and fixes a defect that would have stopped an anonymous
-- guest booking a released seat at all.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- created_by was NOT NULL on both booking tables, but a public booking has
-- no signed-in user: create_booking and book_guest_slot both stamp
-- auth.uid(), which is null for anon, so every public booking would have
-- failed on the insert. NULL now means self-registered, the same convention
-- public membership sign-up already uses (0026).
-- ─────────────────────────────────────────────────────────────────────────
alter table bookings
  alter column created_by drop not null;

alter table membership_session_bookings
  alter column created_by drop not null;


-- ─────────────────────────────────────────────────────────────────────────
-- Payment state, kept separate from booking state exactly as bookings does:
-- a confirmed seat with money still owed is the normal case here.
-- ─────────────────────────────────────────────────────────────────────────
alter table membership_session_bookings
  add column if not exists payment_status text not null default 'PENDING'
    check (payment_status in ('PENDING', 'PAID', 'REFUNDED')),
  add column if not exists payment_method text;

-- Lets a payment point at a session seat, the way it already points at a
-- court booking. Nullable, like booking_id — a payment references one or
-- the other, or neither for membership dues.
alter table payments
  add column if not exists membership_session_booking_id uuid
    references membership_session_bookings (id) on delete set null;

create index if not exists payments_session_booking_idx
  on payments (membership_session_booking_id);


-- ─────────────────────────────────────────────────────────────────────────
-- Record cash taken at the venue for a released-capacity seat.
--
-- Deliberately mirrors record_guest_booking_payment: same authorisation
-- check, same insert into payments, so Finance picks it up through the
-- existing reader rather than a parallel path.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function record_session_guest_payment(
  p_session_booking_id uuid,
  p_method text,
  p_amount_minor integer
) returns membership_session_bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  sb membership_session_bookings;
  amt integer;
begin
  select * into sb from membership_session_bookings where id = p_session_booking_id;
  if sb.id is null then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;

  if not has_facility_role(sb.facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized.' using errcode = '42501';
  end if;

  if sb.participant_type <> 'GUEST' then
    raise exception 'Only guest seats are paid for this way.' using errcode = '23514';
  end if;

  if sb.payment_status = 'PAID' then
    raise exception 'This booking is already paid.' using errcode = '23514';
  end if;

  amt := greatest(coalesce(nullif(p_amount_minor, 0), sb.amount_minor, 0), 0);

  insert into payments (
    facility_id, member_id, booking_id, membership_session_booking_id,
    amount_inr, status, payment_method, paid_at
  ) values (
    sb.facility_id, null, null, sb.id,
    round(amt / 100.0), 'paid'::payment_status, nullif(trim(p_method), ''), now()
  );

  update membership_session_bookings
  set payment_status = 'PAID',
      payment_method = coalesce(nullif(trim(p_method), ''), payment_method)
  where id = p_session_booking_id
  returning * into sb;

  return sb;
end;
$$;

grant execute on function record_session_guest_payment(uuid, text, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- list_guest_bookings_admin — court bookings and released-capacity seats in
-- one list.
--
-- Gains a `source` column so the page can tell them apart: a session seat
-- has no court booking behind it, so row actions that operate on a bookings
-- row (reschedule, duplicate, complete) do not apply to it.
--
-- Session seats are matched by the session's own date and court, so every
-- existing filter keeps working across both kinds.
-- ─────────────────────────────────────────────────────────────────────────
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
    -- Ordinary guest court bookings.
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
      b.currency,
      b.payment_status,
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
      and (p_payment_status is null or b.payment_status = p_payment_status)
      and (p_from is null or b.start_time::date >= p_from)
      and (p_to is null or b.start_time::date <= p_to)
      and (
        p_search is null or trim(p_search) = '' or
        b.guest_name ilike '%' || trim(p_search) || '%' or
        b.guest_phone ilike '%' || trim(p_search) || '%' or
        ('GBK' || upper(substr(replace(b.id::text, '-', ''), 1, 4))) ilike '%' || trim(p_search) || '%'
      )

    union all

    -- Guests occupying capacity the owner released from a membership
    -- session. Same shape, so the page renders them without special-casing.
    select
      msb.id,
      'GSB' || upper(substr(replace(msb.id::text, '-', ''), 1, 4)) as code,
      coalesce(gp.name, 'Guest') as guest_name,
      gp.phone as guest_phone,
      coalesce(fs.custom_sport_name, sp.name) as sport_name,
      c.name as court_name,
      (ms.session_date::text || ' ' || ms.start_time::text)::timestamp
        at time zone coalesce(f.timezone, 'Asia/Kolkata') as start_time,
      (ms.session_date::text || ' ' || ms.end_time::text)::timestamp
        at time zone coalesce(f.timezone, 'Asia/Kolkata') as end_time,
      1 as party_size,
      msb.amount_minor,
      msb.currency,
      msb.payment_status,
      msb.payment_method,
      case when msb.status = 'CANCELLED' then 'cancelled' else 'confirmed' end as status,
      'SESSION'::text as source
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
      and (p_payment_status is null or msb.payment_status = p_payment_status)
      and (p_from is null or ms.session_date >= p_from)
      and (p_to is null or ms.session_date <= p_to)
      and (
        p_search is null or trim(p_search) = '' or
        gp.name ilike '%' || trim(p_search) || '%' or
        gp.phone ilike '%' || trim(p_search) || '%' or
        ('GSB' || upper(substr(replace(msb.id::text, '-', ''), 1, 4))) ilike '%' || trim(p_search) || '%'
      )
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by r.start_time desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
$$;

grant execute on function list_guest_bookings_admin(uuid, text, uuid, uuid, text, text, date, date, integer, integer) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_guest_bookings_summary — count released-capacity seats too, so the
-- KPI tiles and the list below them cannot disagree.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_guest_bookings_summary(p_facility_id uuid, p_from date, p_to date)
returns jsonb
language sql
stable
as $$
  with span as (select (p_to - p_from) as days),
  all_rows as (
    select b.start_time::date as on_date, b.status::text as status,
           b.payment_status, b.amount_minor
    from bookings b
    where b.facility_id = p_facility_id and b.customer_type = 'GUEST'
    union all
    select ms.session_date,
           case when msb.status = 'CANCELLED' then 'cancelled' else 'confirmed' end,
           msb.payment_status, msb.amount_minor
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
  cur as (
    select count(*)::int as cnt,
           coalesce(sum(amount_minor) filter (where payment_status = 'PAID'), 0)::bigint as rev
    from gb
  ),
  pre as (
    select count(*)::int as cnt,
           coalesce(sum(amount_minor) filter (where payment_status = 'PAID'), 0)::bigint as rev
    from prev
  )
  -- Same keys the Guest Bookings dashboard already reads — only the source
  -- of `gb`/`prev` changed.
  select jsonb_build_object(
    'total', (select cnt from cur),
    'confirmed', (select count(*) from gb where status = 'confirmed'),
    'completed', (select count(*) from gb where status = 'completed'),
    'cancelled', (select count(*) from gb where status = 'cancelled'),
    'pending', (select count(*) from gb where status = 'pending'),
    'totalRevenueMinor', (select rev from cur),
    'avgPerBookingMinor', coalesce((select round(avg(amount_minor)) from gb where payment_status = 'PAID'), 0),
    'highestBookingMinor', coalesce((select max(amount_minor) from gb where payment_status = 'PAID'), 0),
    'totalChangePct', (select case when pre.cnt = 0 then null else round((cur.cnt - pre.cnt) * 100.0 / pre.cnt) end from cur, pre),
    'revenueChangePct', (select case when pre.rev = 0 then null else round((cur.rev - pre.rev) * 100.0 / pre.rev) end from cur, pre),
    'trend', coalesce((
      select jsonb_agg(jsonb_build_object('date', d, 'amountMinor', amt) order by d)
      from (
        select on_date as d,
               coalesce(sum(amount_minor) filter (where payment_status = 'PAID'), 0)::bigint as amt
        from gb group by on_date
      ) t
    ), '[]'::jsonb)
  );
$$;

grant execute on function get_guest_bookings_summary(uuid, date, date) to authenticated;
