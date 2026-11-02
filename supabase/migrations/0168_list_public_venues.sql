-- Player app: the venues a player can see for the city they picked.
--
-- A venue is listed when it is open for business (ACTIVE, onboarding finished) and has at least one court that can take bookings
-- (not archived, ACTIVE, booking enabled): the same test the public booking page applies. Only what a visitor needs is returned
-- (name, place, logo, sports, number of courts); nothing about the owner or the club's customers.
--
-- p_city is the city as the player picked it, e.g. 'Bangalore' (the app passes the part before the comma; p_state the part after).
-- Matching ignores case and spaces, and treats Bengaluru and Bangalore as the same city. When no venue matches the answer is an
-- empty list: the app then tells the player there are no venues in that city yet.
create or replace function list_public_venues(p_city text, p_state text default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with want as (
    select
      case when lower(trim(coalesce(p_city, ''))) in ('bengaluru', 'bangalore') then 'bangalore' else lower(trim(coalesce(p_city, ''))) end as city,
      lower(trim(coalesce(p_state, ''))) as state
  ),
  bookable as (
    select c.facility_id, c.facility_sport_id
      from courts c
     where not c.archived and c.status = 'ACTIVE' and c.booking_enabled
  ),
  venues as (
    select f.id, f.name, f.city, f.state, f.area, f.logo_url,
           (select count(*) from bookable b where b.facility_id = f.id) as court_count,
           coalesce((
             select jsonb_agg(distinct coalesce(fs.custom_sport_name, sp.name))
               from facility_sports fs
               left join sports sp on sp.id = fs.sport_id
              where fs.facility_id = f.id
                and fs.id in (select b.facility_sport_id from bookable b where b.facility_id = f.id)
           ), '[]'::jsonb) as sports
      from facilities f, want w
     where f.status = 'ACTIVE'
       and f.onboarding_step = 'COMPLETED'
       and w.city <> ''
       and (case when lower(trim(coalesce(f.city, ''))) in ('bengaluru', 'bangalore') then 'bangalore' else lower(trim(coalesce(f.city, ''))) end) = w.city
       and (w.state = '' or lower(trim(coalesce(f.state, ''))) in ('', w.state))
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', v.id, 'name', v.name, 'city', v.city, 'state', v.state, 'area', v.area, 'logoUrl', v.logo_url,
      'courtCount', v.court_count, 'sports', v.sports
    ) order by v.name
  ), '[]'::jsonb)
  from venues v
  where v.court_count > 0;
$$;
revoke all on function list_public_venues(text, text) from public;
grant execute on function list_public_venues(text, text) to anon, authenticated;
