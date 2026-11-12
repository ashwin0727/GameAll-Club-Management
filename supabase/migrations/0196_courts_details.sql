-- Sports & Courts redesign: per-court lighting and amenities, Basketball, and the venue's indoor/outdoor derived from its courts.
--
--   * courts.surface        (already there) the playing surface: Wooden, Synthetic, Artificial Turf, ...
--   * courts.area_type      (already there) INDOOR | OUTDOOR  - the "Court Type" column
--   * courts.lighting_type  NEW  LED | FLOODLIGHT | NATURAL | NONE
--   * courts.court_amenities NEW text[] of ac | shower | locker
--
-- The Facility Information page no longer asks "indoor or outdoor" for the whole venue: each court says it. facilities.venue_type is
-- kept (the Player app cards, filters and admin screens read it) and is now DERIVED: INDOOR when every live court is indoor, OUTDOOR
-- when every one is outdoor, and empty for a mixed venue (the Player app then shows each court's own type).

-- ── Basketball joins the sport catalogue ─────────────────────────────────
insert into sports (key, name, sort_order, default_playing_area_label)
values ('basketball', 'Basketball', 55, 'COURT')
on conflict (key) do nothing;

-- ── court details ─────────────────────────────────────────────────────────
alter table courts
  add column if not exists lighting_type text,
  add column if not exists court_amenities text[] not null default '{}';

alter table courts drop constraint if exists courts_lighting_type_chk;
alter table courts add constraint courts_lighting_type_chk
  check (lighting_type is null or lighting_type in ('LED', 'FLOODLIGHT', 'NATURAL', 'NONE'));

alter table courts drop constraint if exists courts_court_amenities_chk;
alter table courts add constraint courts_court_amenities_chk
  check (court_amenities <@ array['ac', 'shower', 'locker']::text[]);

-- ── facilities.venue_type follows the courts ──────────────────────────────
create or replace function recompute_facility_venue_type(p_facility_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  total integer;
  indoor integer;
  outdoor integer;
begin
  select count(*), count(*) filter (where area_type = 'INDOOR'), count(*) filter (where area_type = 'OUTDOOR')
    into total, indoor, outdoor
    from courts
   where facility_id = p_facility_id and not archived;
  if total = 0 then
    return;                              -- nothing to derive from; leave whatever the venue already has
  end if;
  update facilities
     set venue_type = case when indoor = total then 'INDOOR' when outdoor = total then 'OUTDOOR' else null end
   where id = p_facility_id
     and venue_type is distinct from (case when indoor = total then 'INDOOR' when outdoor = total then 'OUTDOOR' else null end);
end;
$$;
revoke all on function recompute_facility_venue_type(uuid) from public, anon, authenticated;

create or replace function courts_sync_venue_type()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform recompute_facility_venue_type(old.facility_id);
    return old;
  end if;
  perform recompute_facility_venue_type(new.facility_id);
  return new;
end;
$$;

drop trigger if exists courts_sync_venue_type on courts;
create trigger courts_sync_venue_type
  after insert or delete or update of area_type, archived on courts
  for each row execute function courts_sync_venue_type();

-- existing venues that never chose one get it from their courts
do $$
declare
  f record;
begin
  for f in select id from facilities where venue_type is null loop
    perform recompute_facility_venue_type(f.id);
  end loop;
end;
$$;

-- ── Player app: each court says what it is ────────────────────────────────
-- Same call as 0174, but every court now carries its type, surface, lighting and amenities.
create or replace function get_public_venue(p_facility_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with bookable as (
    select c.id, c.name, c.facility_sport_id, c.hourly_rate_inr, c.area_type, c.surface, c.lighting_type, c.court_amenities
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
    'amenityKeys', to_jsonb(f.amenity_keys),
    'customAmenities', to_jsonb(f.custom_amenities),
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
    'courts', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'facilitySportId', b.facility_sport_id, 'type', b.area_type, 'surface', b.surface, 'lighting', b.lighting_type, 'amenities', to_jsonb(b.court_amenities)) order by b.name) from bookable b), '[]'::jsonb),
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
