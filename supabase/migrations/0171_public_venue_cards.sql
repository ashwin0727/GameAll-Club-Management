-- Player app: the venue cards of the Venues, Memberships and Coaching pages.
--
--   p_kind = 'venues'       every open venue that can take bookings (what list_public_venues returns), with a picture and a price
--   p_kind = 'memberships'  only venues that have created a membership plan (an active plan, or an active membership batch)
--   p_kind = 'coaching'     only venues that have created a coaching programme (an ACTIVE one)
--
-- Per venue: id, name, city, state, area, logoUrl, heroImageUrl, courtCount, sports[], minCourtPriceInr (cheapest court per hour),
-- memberships { count, names[], minPriceInr }, coaching { count, names[], minPriceInr }.
-- Visitors can call it (no sign-in). Nothing about owners or customers is returned. Same city matching as list_public_venues.
create or replace function list_public_venue_cards(p_city text, p_state text default null, p_kind text default 'venues')
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
    select c.facility_id, c.facility_sport_id, c.hourly_rate_inr
      from courts c
     where not c.archived and c.status = 'ACTIVE' and c.booking_enabled
  ),
  venues as (
    select f.id, f.name, f.city, f.state, f.area, f.logo_url, f.hero_image_url,
           (select count(*) from bookable b where b.facility_id = f.id) as court_count,
           (select min(b.hourly_rate_inr) from bookable b where b.facility_id = f.id) as min_price,
           coalesce((
             select jsonb_agg(distinct coalesce(fs.custom_sport_name, sp.name))
               from facility_sports fs
               left join sports sp on sp.id = fs.sport_id
              where fs.facility_id = f.id
                and fs.id in (select b.facility_sport_id from bookable b where b.facility_id = f.id)
           ), '[]'::jsonb) as sports,
           -- membership plans
           (select count(*) from membership_plans mp where mp.facility_id = f.id and mp.is_active) as plan_count,
           (select count(*) from membership_batches mb where mb.facility_id = f.id and mb.is_active) as batch_count,
           coalesce((select jsonb_agg(x.name order by x.name) from (select mp.name from membership_plans mp where mp.facility_id = f.id and mp.is_active order by mp.name limit 4) x), '[]'::jsonb) as plan_names,
           (select min(mp.price_inr) from membership_plans mp where mp.facility_id = f.id and mp.is_active) as min_plan_price,
           -- coaching programmes
           (select count(*) from coaching_programs cp where cp.facility_id = f.id and cp.status = 'ACTIVE') as program_count,
           coalesce((select jsonb_agg(x.name order by x.name) from (select cp.name from coaching_programs cp where cp.facility_id = f.id and cp.status = 'ACTIVE' order by cp.name limit 4) x), '[]'::jsonb) as program_names,
           (select min(cp.default_price_minor) from coaching_programs cp where cp.facility_id = f.id and cp.status = 'ACTIVE' and cp.default_price_minor > 0) as min_program_minor
      from facilities f, want w
     where f.status = 'ACTIVE'
       and f.onboarding_step = 'COMPLETED'
       and w.city <> ''
       and (case when lower(trim(coalesce(f.city, ''))) in ('bengaluru', 'bangalore') then 'bangalore' else lower(trim(coalesce(f.city, ''))) end) = w.city
       and (w.state = '' or lower(trim(coalesce(f.state, ''))) in ('', w.state))
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', v.id, 'name', v.name, 'city', v.city, 'state', v.state, 'area', v.area,
      'logoUrl', v.logo_url, 'heroImageUrl', v.hero_image_url,
      'courtCount', v.court_count, 'sports', v.sports, 'minCourtPriceInr', v.min_price,
      'memberships', jsonb_build_object('count', v.plan_count + case when v.plan_count = 0 then v.batch_count else 0 end, 'names', v.plan_names, 'minPriceInr', v.min_plan_price),
      'coaching', jsonb_build_object('count', v.program_count, 'names', v.program_names, 'minPriceInr', case when v.min_program_minor is null then null else v.min_program_minor / 100 end)
    ) order by v.name
  ), '[]'::jsonb)
  from venues v
  where case lower(coalesce(p_kind, 'venues'))
          when 'memberships' then (v.plan_count > 0 or v.batch_count > 0)
          when 'coaching' then v.program_count > 0
          else v.court_count > 0
        end;
$$;
revoke all on function list_public_venue_cards(text, text, text) from public;
grant execute on function list_public_venue_cards(text, text, text) to anon, authenticated;
