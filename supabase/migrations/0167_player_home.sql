-- Player app: everything the Home page needs about the signed-in player, in one call.
--
-- A player can read their own memberships and bookings through row-level security, but NOT their coaching enrolments (that policy is
-- staff-only), so "do I have active coaching?" cannot be answered with a plain query. This function answers it for the caller only:
-- it looks up the people records linked to auth.uid() and returns nothing about anyone else.
--
-- Returns:
--   fullName, unreadNotifications,
--   hasActiveMembership   an 'active' membership whose end date has not passed
--   hasActiveCoaching     an ACTIVE enrolment that has not ended
--   hasBookingHistory     any booking at all (cancelled ones count: the player has played or tried before)
--   upcomingBookings      up to 5 confirmed bookings that have not finished, soonest first
create or replace function get_my_player_home()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (select auth.uid() as uid),
  my_people as (
    select m.id from members m, me where m.user_id = me.uid
    union
    select me.uid from me where me.uid is not null
  ),
  upcoming as (
    select b.id, b.start_time, b.end_time, b.status,
           f.name as venue_name, f.logo_url as venue_logo,
           c.name as court_name, s.name as sport_name
      from bookings b
      join facilities f on f.id = b.facility_id
      left join courts c on c.id = b.court_id
      left join sports s on s.id = c.sport_id
     where b.member_id in (select id from my_people)
       and b.status = 'confirmed'
       and b.end_time > now()
     order by b.start_time
     limit 5
  )
  select jsonb_build_object(
    'fullName', (select p.full_name from profiles p, me where p.id = me.uid),
    'unreadNotifications', (select count(*) from notifications n, me where n.user_id = me.uid and n.read_at is null),
    'hasActiveMembership', exists (
      select 1 from memberships ms
       where ms.member_id in (select id from my_people)
         and ms.status::text = 'active' and ms.end_date >= current_date),
    'hasActiveCoaching', exists (
      select 1 from coaching_enrollments e
       where e.member_id in (select id from my_people)
         and e.status = 'ACTIVE' and (e.end_date is null or e.end_date >= current_date)),
    'hasBookingHistory', exists (select 1 from bookings b where b.member_id in (select id from my_people)),
    'upcomingBookings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'startTime', u.start_time, 'endTime', u.end_time, 'status', u.status,
        'venueName', u.venue_name, 'venueLogo', u.venue_logo, 'courtName', u.court_name, 'sportName', u.sport_name
      ) order by u.start_time) from upcoming u), '[]'::jsonb)
  );
$$;
revoke all on function get_my_player_home() from public, anon;
grant execute on function get_my_player_home() to authenticated;
