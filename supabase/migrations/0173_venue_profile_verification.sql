-- Venue profile: map link verification, photos, indoor/outdoor and amenities.
--
-- What a new facility now has to provide, and what GameAll's admin checks:
--   * Google Maps location link (facilities.location_url, from 0056)    -> admin verifies it points at the right place
--   * at least one facility photo (facility_images)                    -> admin verifies each photo
--   * venue type: INDOOR or OUTDOOR
--   * five amenities, each on or off: free parking, changing rooms, toilets / rest room, cafeteria, equipment rental
-- Both checks sit next to the payout checks in the admin's verification queue. Nothing is shown to players as verified until the admin
-- says so: the Player app uses a facility's photos only once they are VERIFIED.
--
-- Existing, already-completed facilities are untouched: the new requirements apply while a facility is being set up
-- (complete_facility_setup), never to one that is already COMPLETED.

-- ── facility columns ───────────────────────────────────────────────────────
alter table facilities
  add column if not exists venue_type text check (venue_type in ('INDOOR', 'OUTDOOR')),
  add column if not exists has_parking boolean not null default false,
  add column if not exists has_changing_rooms boolean not null default false,
  add column if not exists has_toilets boolean not null default false,
  add column if not exists has_cafeteria boolean not null default false,
  add column if not exists has_equipment_rental boolean not null default false,
  add column if not exists location_verification_status text not null default 'PENDING'
    check (location_verification_status in ('PENDING', 'VERIFIED', 'REJECTED')),
  add column if not exists location_verified_at timestamptz,
  add column if not exists location_verified_by uuid references auth.users (id),
  add column if not exists location_verification_note text;

-- Only the platform admin (or the service role) may change the verdict; an owner changing the link puts it back to PENDING.
create or replace function guard_facility_location_verification()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null or is_platform_admin() then
    if new.location_verification_status = 'VERIFIED' then
      new.location_verified_at := coalesce(new.location_verified_at, now());
      new.location_verified_by := coalesce(new.location_verified_by, auth.uid());
    else
      new.location_verified_at := null;
      new.location_verified_by := null;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.location_verification_status := 'PENDING';
    new.location_verified_at := null;
    new.location_verified_by := null;
    new.location_verification_note := null;
    return new;
  end if;

  if new.location_verification_status is distinct from old.location_verification_status
     or new.location_verified_at is distinct from old.location_verified_at
     or new.location_verified_by is distinct from old.location_verified_by
     or new.location_verification_note is distinct from old.location_verification_note then
    raise exception 'Verification is managed by GameAll' using errcode = '42501';
  end if;
  if new.location_url is distinct from old.location_url then
    new.location_verification_status := 'PENDING';
    new.location_verified_at := null;
    new.location_verified_by := null;
    new.location_verification_note := null;
  end if;
  return new;
end;
$$;
drop trigger if exists facilities_location_verification_guard on facilities;
create trigger facilities_location_verification_guard
  before insert or update on facilities
  for each row execute function guard_facility_location_verification();

-- ── facility photos ────────────────────────────────────────────────────────
create table if not exists facility_images (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  url text not null check (trim(url) <> ''),
  sort_order integer not null default 0,
  verification_status text not null default 'PENDING' check (verification_status in ('PENDING', 'VERIFIED', 'REJECTED')),
  verification_note text,
  verified_at timestamptz,
  verified_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists facility_images_facility_idx on facility_images (facility_id, sort_order, created_at);

alter table facility_images enable row level security;
drop policy if exists "facility_images_select_members" on facility_images;
create policy "facility_images_select_members" on facility_images for select using (is_facility_member(facility_id));
drop policy if exists "facility_images_insert_managers" on facility_images;
create policy "facility_images_insert_managers" on facility_images for insert
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));
drop policy if exists "facility_images_update_managers" on facility_images;
create policy "facility_images_update_managers" on facility_images for update
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));
drop policy if exists "facility_images_delete_managers" on facility_images;
create policy "facility_images_delete_managers" on facility_images for delete
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

drop trigger if exists facility_images_set_updated_at on facility_images;
create trigger facility_images_set_updated_at before update on facility_images for each row execute function set_updated_at();

create or replace function guard_facility_image_verification()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null or is_platform_admin() then
    if new.verification_status = 'VERIFIED' then
      new.verified_at := coalesce(new.verified_at, now());
      new.verified_by := coalesce(new.verified_by, auth.uid());
    else
      new.verified_at := null;
      new.verified_by := null;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.verification_status := 'PENDING';
    new.verification_note := null;
    new.verified_at := null;
    new.verified_by := null;
  else
    if new.verification_status is distinct from old.verification_status
       or new.verification_note is distinct from old.verification_note
       or new.verified_at is distinct from old.verified_at
       or new.verified_by is distinct from old.verified_by then
      raise exception 'Verification is managed by GameAll' using errcode = '42501';
    end if;
    -- a replaced picture is a new picture: it has to be checked again
    if new.url is distinct from old.url then
      new.verification_status := 'PENDING';
      new.verification_note := null;
      new.verified_at := null;
      new.verified_by := null;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists facility_images_verification_guard on facility_images;
create trigger facility_images_verification_guard
  before insert or update on facility_images
  for each row execute function guard_facility_image_verification();

-- Public bucket (the photos are shown to players); an owner writes only inside a folder named after their own user id.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('facility-photos', 'facility-photos', true, 8388608, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "facility photos are publicly readable" on storage.objects;
create policy "facility photos are publicly readable" on storage.objects for select using (bucket_id = 'facility-photos');
drop policy if exists "owners upload their own facility photos" on storage.objects;
create policy "owners upload their own facility photos" on storage.objects for insert to authenticated
  with check (bucket_id = 'facility-photos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "owners remove their own facility photos" on storage.objects;
create policy "owners remove their own facility photos" on storage.objects for delete to authenticated
  using (bucket_id = 'facility-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ── setup now needs the map link, a photo and the venue type (new facilities only) ──
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
  if result.venue_type is null then
    raise exception 'Choose whether the venue is indoor or outdoor.' using errcode = '23514';
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

-- ── the admin's verification queue ─────────────────────────────────────────
-- One row per facility that has something waiting: its map link, its photos, or its payout details.
create or replace function admin_list_venue_verifications()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  return coalesce((
    select jsonb_agg(x.row order by x.pending desc, x.row->>'name') from (
      select jsonb_build_object(
        'id', f.id, 'name', f.name, 'city', f.city, 'ownerName', o.full_name, 'ownerEmail', o.email,
        'locationUrl', f.location_url, 'locationStatus', case when nullif(btrim(coalesce(f.location_url, '')), '') is null then null else f.location_verification_status end,
        'imagesTotal', (select count(*) from facility_images i where i.facility_id = f.id),
        'imagesPending', (select count(*) from facility_images i where i.facility_id = f.id and i.verification_status = 'PENDING'),
        'imagesVerified', (select count(*) from facility_images i where i.facility_id = f.id and i.verification_status = 'VERIFIED'),
        'imagesRejected', (select count(*) from facility_images i where i.facility_id = f.id and i.verification_status = 'REJECTED'),
        'payoutsPending', (select count(*) from facility_payout_methods pm where pm.facility_id = f.id and pm.verification_status = 'PENDING'),
        'venueType', f.venue_type, 'onboardingStep', f.onboarding_step
      ) as row,
      ( (case when nullif(btrim(coalesce(f.location_url, '')), '') is not null and f.location_verification_status = 'PENDING' then 1 else 0 end)
        + (select count(*) from facility_images i where i.facility_id = f.id and i.verification_status = 'PENDING')
        + (select count(*) from facility_payout_methods pm where pm.facility_id = f.id and pm.verification_status = 'PENDING') ) as pending
      from facilities f left join profiles o on o.id = f.owner_id
      where nullif(btrim(coalesce(f.location_url, '')), '') is not null
         or exists (select 1 from facility_images i where i.facility_id = f.id)
         or exists (select 1 from facility_payout_methods pm where pm.facility_id = f.id)
    ) x), '[]'::jsonb);
end;
$$;
grant execute on function admin_list_venue_verifications() to authenticated;

-- Everything the admin needs to judge one facility: the link, the address (to compare it with the map), the photos, the payout methods.
create or replace function admin_get_venue_verification(p_facility_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  return jsonb_build_object(
    'facility', (select jsonb_build_object(
        'id', f.id, 'name', f.name, 'city', f.city, 'state', f.state, 'area', f.area,
        'address', concat_ws(', ', nullif(f.address_line_1, ''), nullif(f.area, ''), nullif(f.city, ''), nullif(f.state, ''), nullif(f.postal_code, '')),
        'ownerName', o.full_name, 'ownerEmail', o.email, 'ownerPhone', coalesce(f.business_phone, o.phone),
        'venueType', f.venue_type,
        'amenities', jsonb_build_object('parking', f.has_parking, 'changingRooms', f.has_changing_rooms, 'toilets', f.has_toilets, 'cafeteria', f.has_cafeteria, 'equipmentRental', f.has_equipment_rental),
        'location', jsonb_build_object('url', f.location_url, 'status', f.location_verification_status, 'note', f.location_verification_note, 'verifiedAt', f.location_verified_at)
      ) from facilities f left join profiles o on o.id = f.owner_id where f.id = p_facility_id),
    'images', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'url', i.url, 'status', i.verification_status, 'note', i.verification_note, 'createdAt', i.created_at) order by i.sort_order, i.created_at)
      from facility_images i where i.facility_id = p_facility_id), '[]'::jsonb),
    'payoutMethods', coalesce((
      select jsonb_agg(jsonb_build_object('id', pm.id, 'type', pm.method_type, 'verification', pm.verification_status, 'primary', pm.is_primary) order by pm.is_primary desc, pm.created_at)
      from facility_payout_methods pm where pm.facility_id = p_facility_id), '[]'::jsonb)
  );
end;
$$;
grant execute on function admin_get_venue_verification(uuid) to authenticated;

create or replace function admin_review_location(p_facility_id uuid, p_status text, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  if p_status not in ('VERIFIED', 'REJECTED', 'PENDING') then
    raise exception 'Choose Verified, Rejected or Pending.' using errcode = '22023';
  end if;
  if p_status = 'REJECTED' and nullif(btrim(coalesce(p_note, '')), '') is null then
    raise exception 'Say why it was rejected so the owner can fix it.' using errcode = '22023';
  end if;
  update facilities
     set location_verification_status = p_status, location_verification_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_facility_id;
  if not found then
    raise exception 'Facility not found.' using errcode = 'P0002';
  end if;
end;
$$;
grant execute on function admin_review_location(uuid, text, text) to authenticated;

create or replace function admin_review_facility_image(p_image_id uuid, p_status text, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform require_platform_admin();
  if p_status not in ('VERIFIED', 'REJECTED', 'PENDING') then
    raise exception 'Choose Verified, Rejected or Pending.' using errcode = '22023';
  end if;
  if p_status = 'REJECTED' and nullif(btrim(coalesce(p_note, '')), '') is null then
    raise exception 'Say why it was rejected so the owner can fix it.' using errcode = '22023';
  end if;
  update facility_images
     set verification_status = p_status, verification_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_image_id;
  if not found then
    raise exception 'Photo not found.' using errcode = 'P0002';
  end if;
end;
$$;
grant execute on function admin_review_facility_image(uuid, text, text) to authenticated;

-- ── the Player app's venue cards: approved photos, indoor/outdoor, amenities ──
-- Same function as 0172 with three more fields. heroImageUrl is the first VERIFIED photo (the owner's own hero image, as before, when
-- there is none yet); photos are the whole approved set, for a detail page later.
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
