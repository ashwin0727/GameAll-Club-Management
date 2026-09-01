-- ═══════════════════════════════════════════════════════════════════════════
-- Guest Bookings dashboard — a dedicated page listing every GUEST court
-- booking with KPI tiles, status/payment filters, a booking-status donut and
-- a revenue trend. Adds:
--   • bookings.party_size / bookings.payment_method
--   • create_booking gains p_party_size / p_payment_method
--   • get_guest_bookings_summary  — KPI tiles + donut + trend
--   • list_guest_bookings_admin   — the filterable, paginated table
-- ═══════════════════════════════════════════════════════════════════════════

alter table bookings add column if not exists party_size integer not null default 1 check (party_size >= 1);
alter table bookings add column if not exists payment_method text;

-- ─────────────────────────────────────────────────────────────────────────
-- create_booking — carry party size + payment method through.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists create_booking(uuid, uuid, timestamptz, timestamptz, text, uuid, text, text, text);
drop function if exists create_booking(uuid, uuid, timestamptz, timestamptz, text, uuid, text, text, text, text, uuid);

create function create_booking(
  p_facility_id uuid,
  p_court_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_customer_type text,
  p_member_id uuid,
  p_guest_name text,
  p_guest_phone text,
  p_notes text,
  p_payment_status text default 'PENDING',
  p_guest_player_id uuid default null,
  p_party_size integer default 1,
  p_payment_method text default null
) returns bookings
language plpgsql
as $$
declare
  result bookings;
  fac facilities;
  court courts;
  price integer;
  guest guest_players;
  v_guest_name text := p_guest_name;
  v_guest_phone text := p_guest_phone;
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

  if p_guest_player_id is not null then
    select * into guest from guest_players where id = p_guest_player_id and facility_id = p_facility_id;
    if guest.id is null then
      raise exception 'guest % does not exist for this facility', p_guest_player_id using errcode = '23503';
    end if;
    v_guest_name := guest.name;
    v_guest_phone := guest.phone;
  end if;

  if not booking_window_fits_operating_hours(p_facility_id, p_court_id, p_start_time, p_end_time) then
    raise exception 'Selected time is outside this court''s operating hours.' using errcode = '23514';
  end if;

  if court_has_active_membership_window(p_court_id, p_start_time, p_end_time, fac.timezone) then
    raise exception 'This time is reserved for a membership session. Use guest slot booking for this court/time instead.' using errcode = '23514';
  end if;

  price := resolve_booking_price(court.facility_sport_id, p_court_id, p_start_time, p_end_time, fac.timezone);

  insert into bookings (
    facility_id, court_id, member_id, start_time, end_time, status,
    customer_type, guest_name, guest_phone, guest_player_id,
    amount_minor, currency, notes, created_by, payment_status,
    party_size, payment_method
  ) values (
    p_facility_id, p_court_id, p_member_id, p_start_time, p_end_time, 'confirmed',
    coalesce(p_customer_type, 'MEMBER'), v_guest_name, v_guest_phone, p_guest_player_id,
    price, fac.currency, p_notes, auth.uid(), coalesce(p_payment_status, 'PENDING'),
    greatest(coalesce(p_party_size, 1), 1), nullif(trim(p_payment_method), '')
  ) returning * into result;

  return result;
end;
$$;
grant execute on function create_booking(uuid, uuid, timestamptz, timestamptz, text, uuid, text, text, text, text, uuid, integer, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- get_guest_bookings_summary — KPI tiles, donut, revenue trend. Change % is
-- vs the immediately-preceding window of equal length.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_guest_bookings_summary(p_facility_id uuid, p_from date, p_to date)
returns jsonb
language sql
stable
as $$
  with span as (select (p_to - p_from) as days),
  gb as (
    select b.* from bookings b, span
    where b.facility_id = p_facility_id and b.customer_type = 'GUEST'
      and b.start_time::date between p_from and p_to
  ),
  prev as (
    select b.* from bookings b, span
    where b.facility_id = p_facility_id and b.customer_type = 'GUEST'
      and b.start_time::date between (p_from - span.days - 1) and (p_from - 1)
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
        select start_time::date as d,
               coalesce(sum(amount_minor) filter (where payment_status = 'PAID'), 0)::bigint as amt
        from gb group by start_time::date
      ) t
    ), '[]'::jsonb)
  );
$$;
grant execute on function get_guest_bookings_summary(uuid, date, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_guest_bookings_admin — the table.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_guest_bookings_admin(
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
      b.currency,
      b.payment_status,
      b.payment_method,
      b.status::text as status
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
  )
  select r.*, count(*) over () as total_count
  from rows r
  order by r.start_time desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
$$;
grant execute on function list_guest_bookings_admin(uuid, text, uuid, uuid, text, text, date, date, integer, integer) to authenticated;