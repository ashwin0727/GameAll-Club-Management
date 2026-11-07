-- ═══════════════════════════════════════════════════════════════════════════
-- Player app: the "Guest Booking" page (Home → Guest Bookings).
--
--   get_my_guest_bookings()   signed-in player: their guest court bookings at every club (found by the phone number on the booking, or the
--                             guest record behind it, like Home), grouped for the page's three tabs:
--                               upcoming   confirmed, or a held booking waiting on its advance, that has not ended yet (soonest first)
--                               completed  confirmed bookings whose time has passed (latest first, at most 50)
--                               cancelled  cancelled bookings that were really made (latest first, at most 50)
--                             An advance hold that was never paid and lapsed is cancelled automatically by the database; it is the
--                             player walking away from a checkout, not a booking, so it is not listed.
--
-- Each booking carries what the page and its details panel show: reference ("GBK-CHZ-1A2B3"), sport, court, time, the venue, the amount,
-- what has been paid and the payment state (PAID | PARTIAL | PENDING).
--
-- Nothing is stored; it reads bookings, courts, sports, facilities and payments.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_my_guest_bookings()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (select auth.uid() as uid),
  pl as (select p.id, p.phone from players p, me where p.id = me.uid),
  my_guests as (select g.id from guest_players g, pl where normalize_phone(g.phone) = pl.phone),
  mine as (
    select b.id, b.status::text as raw_status, b.start_time, b.end_time, b.party_size, b.amount_minor, b.created_at,
           (b.hold_expires_at is not null) as was_hold,
           f.id as facility_id, f.name as venue_name, f.area as venue_area, f.city as venue_city, f.business_phone as venue_phone,
           coalesce((select i.url from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED' order by i.sort_order, i.created_at limit 1),
                    f.hero_image_url) as venue_image,
           c.name as court_name, coalesce(fs.custom_sport_name, sp.name) as sport_name,
           coalesce((select sum(py.amount_inr) from payments py where py.booking_id = b.id and py.status = 'paid'), 0) as paid_inr
      from bookings b
      join facilities f on f.id = b.facility_id
      left join courts c on c.id = b.court_id
      left join facility_sports fs on fs.id = c.facility_sport_id
      left join sports sp on sp.id = c.sport_id
     where b.customer_type = 'GUEST'
       and (b.guest_player_id in (select id from my_guests) or normalize_phone(b.guest_phone) = (select phone from pl))
  ),
  shaped as (
    select m.*,
           case
             when m.raw_status = 'cancelled' then 'cancelled'
             when m.end_time <= now() then 'completed'
             else m.raw_status
           end as shown_status,
           jsonb_build_object(
             'id', m.id,
             'ref', 'GBK-' || upper(left(coalesce(nullif(regexp_replace(m.venue_name, '[^A-Za-z]', '', 'g'), ''), 'GAM'), 3)) || '-' || upper(substr(replace(m.id::text, '-', ''), 1, 5)),
             'status', case when m.raw_status = 'cancelled' then 'cancelled' when m.end_time <= now() then 'completed' else m.raw_status end,
             'startTime', m.start_time, 'endTime', m.end_time,
             'sport', m.sport_name, 'court', m.court_name, 'players', m.party_size,
             'totalInr', coalesce(m.amount_minor, 0) / 100, 'paidInr', m.paid_inr,
             'payState', case
                           when coalesce(m.amount_minor, 0) <= 0 then 'PAID'
                           when m.paid_inr * 100 >= m.amount_minor then 'PAID'
                           when m.paid_inr > 0 then 'PARTIAL'
                           else 'PENDING' end,
             'venue', jsonb_build_object('id', m.facility_id, 'name', m.venue_name, 'area', m.venue_area, 'city', m.venue_city,
                                         'phone', nullif(trim(coalesce(m.venue_phone, '')), ''), 'imageUrl', m.venue_image)
           ) as j
      from mine m
  )
  select jsonb_build_object(
    'upcoming', coalesce((select jsonb_agg(s.j order by s.start_time) from shaped s where s.shown_status in ('pending', 'confirmed')), '[]'::jsonb),
    'completed', coalesce((select jsonb_agg(x.j order by x.start_time desc) from (select * from shaped s where s.shown_status = 'completed' order by s.start_time desc limit 50) x), '[]'::jsonb),
    'cancelled', coalesce((select jsonb_agg(x.j order by x.start_time desc) from (select * from shaped s where s.shown_status = 'cancelled' and not (s.was_hold and s.paid_inr = 0) order by s.start_time desc limit 50) x), '[]'::jsonb),
    'completedCount', (select count(*) from shaped s where s.shown_status = 'completed'),
    'cancelledCount', (select count(*) from shaped s where s.shown_status = 'cancelled' and not (s.was_hold and s.paid_inr = 0))
  );
$$;
revoke all on function get_my_guest_bookings() from public, anon;
grant execute on function get_my_guest_bookings() to authenticated;
