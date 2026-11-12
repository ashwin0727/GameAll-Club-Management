-- Facility onboarding redesign: ownership, WhatsApp, a facility contact person, booking policies and the 12-item amenity list.
--
--   * ownership_type          OWNED | LEASED
--   * whatsapp_number         optional, 10 digits starting 6-9
--   * contact_person_*        who the bookings / operations contact is (name + role required by the app, alternate number optional)
--   * five policy switches    online booking, walk-in booking, advance payment required, cancellations, player details required
--   * amenity_keys            the amenities a venue offers, from a fixed list of 12
--   * custom_amenities        free-text extras the owner added ("Add Custom Amenity")
--
-- The five legacy amenity flags (has_parking, has_changing_rooms, has_toilets, has_cafeteria, has_equipment_rental) stay: the Player app,
-- the venue-card RPCs and the admin screens still read them. A trigger derives them from amenity_keys whenever the list changes, so every
-- client (web, Flutter) only has to write the list.

alter table facilities
  add column if not exists ownership_type text not null default 'OWNED' check (ownership_type in ('OWNED', 'LEASED')),
  add column if not exists whatsapp_number text,
  add column if not exists contact_person_name text,
  add column if not exists contact_person_role text,
  add column if not exists contact_person_alt_phone text,
  add column if not exists allow_online_booking boolean not null default true,
  add column if not exists allow_walk_in_booking boolean not null default true,
  add column if not exists advance_payment_required boolean not null default false,
  add column if not exists allow_cancellations boolean not null default true,
  add column if not exists require_player_details boolean not null default true,
  add column if not exists amenity_keys text[] not null default '{}',
  add column if not exists custom_amenities text[] not null default '{}';

alter table facilities drop constraint if exists facilities_whatsapp_number_chk;
alter table facilities add constraint facilities_whatsapp_number_chk
  check (whatsapp_number is null or whatsapp_number ~ '^[6-9][0-9]{9}$');

alter table facilities drop constraint if exists facilities_contact_alt_phone_chk;
alter table facilities add constraint facilities_contact_alt_phone_chk
  check (contact_person_alt_phone is null or contact_person_alt_phone ~ '^[6-9][0-9]{9}$');

alter table facilities drop constraint if exists facilities_amenity_keys_chk;
alter table facilities add constraint facilities_amenity_keys_chk
  check (amenity_keys <@ array['car_parking', 'two_wheeler_parking', 'restroom', 'changing_room', 'shower', 'drinking_water',
                               'seating_area', 'cafeteria', 'wifi', 'lockers', 'equipment_rental', 'first_aid']::text[]);

alter table facilities drop constraint if exists facilities_custom_amenities_chk;
alter table facilities add constraint facilities_custom_amenities_chk
  check (coalesce(array_length(custom_amenities, 1), 0) <= 10);

-- Existing venues: carry their five flags into the new list so nothing disappears from the edit screens.
update facilities
set amenity_keys = array_remove(array[
      case when has_parking then 'car_parking' end,
      case when has_changing_rooms then 'changing_room' end,
      case when has_toilets then 'restroom' end,
      case when has_cafeteria then 'cafeteria' end,
      case when has_equipment_rental then 'equipment_rental' end
    ]::text[], null)
where amenity_keys = '{}';

-- amenity_keys is the source of truth for new writes; the legacy flags follow it.
create or replace function sync_facility_amenity_flags()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and new.amenity_keys = '{}' then
    return new;                      -- a row created with only the legacy flags keeps them
  end if;
  if tg_op = 'UPDATE' and new.amenity_keys is not distinct from old.amenity_keys then
    return new;                      -- the list did not change, so leave the flags as the caller set them
  end if;
  new.has_parking := new.amenity_keys && array['car_parking', 'two_wheeler_parking']::text[];
  new.has_changing_rooms := 'changing_room' = any (new.amenity_keys);
  new.has_toilets := 'restroom' = any (new.amenity_keys);
  new.has_cafeteria := 'cafeteria' = any (new.amenity_keys);
  new.has_equipment_rental := 'equipment_rental' = any (new.amenity_keys);
  return new;
end;
$$;

drop trigger if exists facilities_sync_amenity_flags on facilities;
create trigger facilities_sync_amenity_flags
  before insert or update on facilities
  for each row execute function sync_facility_amenity_flags();

-- ── setup no longer needs a facility-level venue type ──────────────────────
-- Indoor / outdoor is no longer asked on the Facility Information page; it moves to the Sports & Courts step (per sport / court).
-- facilities.venue_type stays (nullable) for the Player app and admin screens that already read it, but finishing setup no longer
-- requires it. The rest of the function is unchanged from 0173 (map link, a photo, sports, courts, hours, prices, payout).
create or replace function complete_facility_setup(p_facility_id uuid) returns facilities
language plpgsql
as $$
declare
  result facilities;
  sport_count integer;
  area_count integer;
  schedule_count integer;
  unpriced_sport_count integer;
  payout_count integer;
  image_count integer;
begin
  select * into result from facilities where id = p_facility_id;
  if result.id is null then
    raise exception 'Facility not found' using errcode = 'P0002';
  end if;

  if result.onboarding_step = 'COMPLETED' then
    update profiles set onboarding_completed = true where id = auth.uid() and onboarding_completed = false;
    return result;
  end if;

  if nullif(btrim(coalesce(result.location_url, '')), '') is null then
    raise exception 'The Google Maps location link is required.' using errcode = '23514';
  end if;
  select count(*) into image_count from facility_images where facility_id = p_facility_id;
  if image_count = 0 then
    raise exception 'At least one facility photo is required.' using errcode = '23514';
  end if;

  select count(*) into sport_count from facility_sports where facility_id = p_facility_id and is_active;
  if sport_count = 0 then
    raise exception 'At least one sport is required.' using errcode = '23514';
  end if;

  select count(*) into area_count from courts where facility_id = p_facility_id and not archived;
  if area_count = 0 then
    raise exception 'At least one playing area is required.' using errcode = '23514';
  end if;

  select count(*) into schedule_count from operating_schedules
    where facility_id = p_facility_id and scope_type = 'FACILITY';
  if schedule_count = 0 then
    raise exception 'Operating hours are required.' using errcode = '23514';
  end if;

  select count(*) into unpriced_sport_count
  from facility_sports fs
  where fs.facility_id = p_facility_id
    and fs.is_active
    and not exists (
      select 1 from pricing_rules pr
      join pricing_plans pp on pp.id = pr.pricing_plan_id
      where pp.facility_id = p_facility_id
        and pp.status = 'ACTIVE'
        and pr.facility_sport_id = fs.id
        and pr.playing_area_id is null
        and pr.is_active
    )
    and not (
      exists (select 1 from courts c where c.facility_sport_id = fs.id and not c.archived)
      and not exists (
        select 1 from courts c
        where c.facility_sport_id = fs.id
          and not c.archived
          and not exists (
            select 1 from pricing_rules pr
            join pricing_plans pp on pp.id = pr.pricing_plan_id
            where pp.facility_id = p_facility_id
              and pp.status = 'ACTIVE'
              and pr.playing_area_id = c.id
              and pr.is_active
          )
      )
    );
  if unpriced_sport_count > 0 then
    raise exception 'Pricing is required for every sport.' using errcode = '23514';
  end if;

  select count(*) into payout_count from facility_payout_methods where facility_id = p_facility_id;
  if payout_count = 0 then
    raise exception 'A payout method is required.' using errcode = '23514';
  end if;

  update facilities
  set onboarding_step = 'COMPLETED', onboarding_completed_at = now()
  where id = p_facility_id
  returning * into result;

  update profiles set onboarding_completed = true where id = auth.uid();

  return result;
end;
$$;
