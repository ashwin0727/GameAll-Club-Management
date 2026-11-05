-- Player app: everything the venue page shows, in one call.
--
-- Visitors can call it (no sign-in). Only an open venue is returned (ACTIVE, setup finished), and only what a visitor needs:
-- the name and place, the venue's own contact number (already public on the booking page), the owner's description if there is
-- one, the photos GameAll's admin has approved, indoor/outdoor, the amenities, the sports and bookable courts, the opening hours,
-- and the membership plans and coaching programmes on offer. The Google Maps link is returned only once the admin has verified it.
-- Nothing about the owner, the venue's customers or its money crosses this boundary.
--
-- Returns null when the venue does not exist or is not open.
create or replace function get_public_venue(p_facility_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with bookable as (
    select c.id, c.name, c.facility_sport_id, c.hourly_rate_inr
      from courts c
     where c.facility_id = p_facility_id and not c.archived and c.status = 'ACTIVE' and c.booking_enabled
  )
  select jsonb_build_object(
    'id', f.id,
    'name', f.name,
    'city', f.city,
    'state', f.state,
    'area', nullif(trim(coalesce(f.area, '')), ''),
    'address', nullif(concat_ws(', ', nullif(trim(coalesce(f.address_line_1, '')), ''), nullif(trim(coalesce(f.area, '')), ''), nullif(trim(coalesce(f.city, '')), '')), ''),
    'phone', nullif(trim(coalesce(f.business_phone, '')), ''),
    'description', nullif(trim(coalesce(f.description, '')), ''),
    'logoUrl', f.logo_url,
    'heroImageUrl', f.hero_image_url,
    'photos', coalesce((select jsonb_agg(i.url order by i.sort_order, i.created_at) from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED'), '[]'::jsonb),
    'venueType', f.venue_type,
    'amenities', jsonb_build_object('parking', f.has_parking, 'changingRooms', f.has_changing_rooms, 'toilets', f.has_toilets, 'cafeteria', f.has_cafeteria, 'equipmentRental', f.has_equipment_rental),
    'locationVerified', (nullif(btrim(coalesce(f.location_url, '')), '') is not null and f.location_verification_status = 'VERIFIED'),
    'locationUrl', case when f.location_verification_status = 'VERIFIED' then nullif(btrim(coalesce(f.location_url, '')), '') end,
    'courtCount', (select count(*) from bookable),
    'minCourtPriceInr', (select min(b.hourly_rate_inr) from bookable b),
    'sports', coalesce((
      select jsonb_agg(jsonb_build_object('facilitySportId', fs.id, 'name', coalesce(fs.custom_sport_name, sp.name)) order by coalesce(fs.custom_sport_name, sp.name))
        from facility_sports fs
        left join sports sp on sp.id = fs.sport_id
       where fs.facility_id = f.id and fs.id in (select b.facility_sport_id from bookable b)
    ), '[]'::jsonb),
    'courts', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'facilitySportId', b.facility_sport_id) order by b.name) from bookable b), '[]'::jsonb),
    'hours', (
      select jsonb_build_object(
               'opens', to_char(min(t.start_time), 'HH24:MI'),
               'closes', to_char(max(t.end_time), 'HH24:MI'),
               'open24h', coalesce(bool_or(d.is_24_hours), false))
        from operating_schedules s
        join operating_days d on d.schedule_id = s.id and not d.is_closed
        left join operating_time_slots t on t.operating_day_id = d.id
       where s.facility_id = f.id and s.scope_type = 'FACILITY'),
    'memberships', jsonb_build_object(
      'plans', coalesce((select jsonb_agg(jsonb_build_object('name', mp.name, 'priceInr', mp.price_inr, 'durationDays', mp.duration_days) order by mp.price_inr, mp.name)
                           from membership_plans mp where mp.facility_id = f.id and mp.is_active), '[]'::jsonb)),
    'coaching', jsonb_build_object(
      'programs', coalesce((select jsonb_agg(jsonb_build_object('name', cp.name, 'level', cp.level, 'priceInr', case when cp.default_price_minor > 0 then cp.default_price_minor / 100 end) order by cp.name)
                              from coaching_programs cp where cp.facility_id = f.id and cp.status = 'ACTIVE'), '[]'::jsonb))
  )
  from facilities f
  where f.id = p_facility_id and f.status = 'ACTIVE' and f.onboarding_step = 'COMPLETED';
$$;
revoke all on function get_public_venue(uuid) from public;
grant execute on function get_public_venue(uuid) to anon, authenticated;
