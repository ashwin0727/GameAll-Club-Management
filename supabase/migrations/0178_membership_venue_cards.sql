-- The Player app's Memberships page: each venue row shows the lowest price of each duration (Monthly / 3 Months / 6 Months /
-- Yearly), the venue's opening hours, and the days its membership batches run on (for the Days filter).
--
-- Same function as 0173 (list_public_venue_cards) with three more fields; nothing is removed or renamed, so the Venues and
-- Coaching pages keep working whether or not this has been applied. Re-runnable (create or replace).
--
--   memberships.plans : [{ durationDays, priceInr }, ...]   every active plan (the app picks the lowest per duration)
--   memberships.days  : [0..6]                              days any active batch runs on (0 = Sunday ... 6 = Saturday)
--   memberships.bySport : [{ sport, plans: [{ durationDays, priceInr }] }]   the plans each sport has batches for (a plan belongs to a sport through its batches), so a venue with several sports can show each sport's prices
--   hours             : { opens, closes, open24h }          as in get_public_venue (0174)
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
    select c.facility_id, c.facility_sport_id, c.hourly_rate_inr, c.surface
      from courts c
     where not c.archived and c.status = 'ACTIVE' and c.booking_enabled
  ),
  venues as (
    select f.id, f.name, f.city, f.state, f.area, f.logo_url,
           coalesce(
             (select i.url from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED' order by i.sort_order, i.created_at limit 1),
             f.hero_image_url) as hero_image_url,
           coalesce((select jsonb_agg(i.url order by i.sort_order, i.created_at) from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED'), '[]'::jsonb) as photos,
           f.venue_type,
           jsonb_build_object('parking', f.has_parking, 'changingRooms', f.has_changing_rooms, 'toilets', f.has_toilets, 'cafeteria', f.has_cafeteria, 'equipmentRental', f.has_equipment_rental) as amenities,
           (select count(*) from bookable b where b.facility_id = f.id) as court_count,
           (select min(b.hourly_rate_inr) from bookable b where b.facility_id = f.id) as min_price,
           coalesce((select jsonb_agg(distinct lower(trim(b.surface))) from bookable b where b.facility_id = f.id and nullif(trim(b.surface), '') is not null), '[]'::jsonb) as surfaces,
           coalesce((
             select jsonb_agg(distinct coalesce(fs.custom_sport_name, sp.name))
               from facility_sports fs
               left join sports sp on sp.id = fs.sport_id
              where fs.facility_id = f.id
                and fs.id in (select b.facility_sport_id from bookable b where b.facility_id = f.id)
           ), '[]'::jsonb) as sports,
           (select count(*) from membership_plans mp where mp.facility_id = f.id and mp.is_active) as plan_count,
           (select count(*) from membership_batches mb where mb.facility_id = f.id and mb.is_active) as batch_count,
           coalesce((select jsonb_agg(x.name order by x.name) from (select mp.name from membership_plans mp where mp.facility_id = f.id and mp.is_active order by mp.name limit 4) x), '[]'::jsonb) as plan_names,
           (select min(mp.price_inr) from membership_plans mp where mp.facility_id = f.id and mp.is_active) as min_plan_price,
           coalesce((select jsonb_agg(jsonb_build_object('durationDays', mp.duration_days, 'priceInr', mp.price_inr) order by mp.duration_days, mp.price_inr)
                       from membership_plans mp where mp.facility_id = f.id and mp.is_active), '[]'::jsonb) as plan_prices,
           coalesce((
             select jsonb_agg(jsonb_build_object('sport', s.sport, 'plans', s.plans) order by s.sport)
               from (
                 select coalesce(fs.custom_sport_name, sp.name) as sport,
                        jsonb_agg(distinct jsonb_build_object('durationDays', mp.duration_days, 'priceInr', mp.price_inr)) as plans
                   from membership_batches mb
                   join membership_plans mp on mp.id = mb.plan_id and mp.is_active
                   join facility_sports fs on fs.id = mb.facility_sport_id
                   left join sports sp on sp.id = fs.sport_id
                  where mb.facility_id = f.id and mb.is_active
                  group by coalesce(fs.custom_sport_name, sp.name)
               ) s), '[]'::jsonb) as sport_plans,
           coalesce((select jsonb_agg(distinct d.day order by d.day)
                       from membership_batches mb, unnest(mb.days_of_week) as d(day)
                      where mb.facility_id = f.id and mb.is_active), '[]'::jsonb) as batch_days,
           (select jsonb_build_object(
                     'opens', to_char(min(t.start_time), 'HH24:MI'),
                     'closes', to_char(max(t.end_time), 'HH24:MI'),
                     'open24h', coalesce(bool_or(d.is_24_hours), false))
              from operating_schedules s
              join operating_days d on d.schedule_id = s.id and not d.is_closed
              left join operating_time_slots t on t.operating_day_id = d.id
             where s.facility_id = f.id and s.scope_type = 'FACILITY') as hours,
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
      'logoUrl', v.logo_url, 'heroImageUrl', v.hero_image_url, 'photos', v.photos,
      'venueType', v.venue_type, 'amenities', v.amenities,
      'courtCount', v.court_count, 'sports', v.sports, 'surfaces', v.surfaces, 'minCourtPriceInr', v.min_price,
      'hours', v.hours,
      'memberships', jsonb_build_object(
        'count', v.plan_count + case when v.plan_count = 0 then v.batch_count else 0 end,
        'names', v.plan_names, 'minPriceInr', v.min_plan_price,
        'plans', v.plan_prices, 'days', v.batch_days, 'bySport', v.sport_plans),
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
