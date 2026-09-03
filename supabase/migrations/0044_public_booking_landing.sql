-- ═══════════════════════════════════════════════════════════════════════════
-- Public booking landing page (/book/<facilityId>).
--
-- The landing page needs three things the booking flow never asked for: the
-- venue's own hero image, a help number, and the sport's identity so a
-- sport-appropriate image can be chosen when the owner has not supplied one.
--
-- No new image infrastructure: facilities already carries logo_url as a
-- plain text URL, so the hero follows the same pattern rather than
-- introducing a storage bucket and an upload path for one field.
-- ═══════════════════════════════════════════════════════════════════════════

alter table facilities
  add column if not exists hero_image_url text;


-- ─────────────────────────────────────────────────────────────────────────
-- get_public_booking_facility — same contract, plus what the landing page
-- renders. Still deliberately narrow: a name, a city, a help number, two
-- image URLs and the sports on offer. Nothing about owners, members,
-- capacity, finance or settings crosses this boundary.
--
-- `sportKey` is the stable slug from the sports catalogue ('badminton',
-- 'football', …), which is what lets the client pick a sport-appropriate
-- hero image without the server knowing anything about assets.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_public_booking_facility(p_facility_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'facilityId', f.id,
    'facilityName', f.name,
    'city', coalesce(f.city, ''),
    'currency', coalesce(f.currency, 'INR'),
    -- Published so a player can call the venue for help; it is the business
    -- line the owner entered during onboarding, not a personal number.
    'helpPhone', coalesce(nullif(trim(f.business_phone), ''), null),
    'logoUrl', f.logo_url,
    'heroImageUrl', f.hero_image_url,
    'sports', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'facilitySportId', fs.id,
          'name', coalesce(fs.custom_sport_name, sp.name),
          'sportKey', sp.key
        ) order by coalesce(fs.custom_sport_name, sp.name)
      )
      from facility_sports fs
      left join sports sp on sp.id = fs.sport_id
      where fs.facility_id = f.id
        and exists (
          select 1 from courts c
          where c.facility_sport_id = fs.id and not c.archived
        )
    ), '[]'::jsonb)
  )
  from facilities f
  where f.id = p_facility_id;
$$;

grant execute on function get_public_booking_facility(uuid) to anon, authenticated;
