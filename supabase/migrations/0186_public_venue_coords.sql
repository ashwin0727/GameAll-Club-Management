-- Distances in the Player app: "nearest venue first".
--
-- A venue's position is not on its card (list_public_venue_cards is unchanged). This adds one small, separate function that returns
-- a position per venue, so the app can sort by distance from the player's device. If this migration is not applied the app simply
-- lists venues in its usual order.
--
-- Where the position comes from, in order:
--   1. facilities.latitude / longitude (columns exist since 0002), when filled in;
--   2. the coordinates inside the owner's Google Maps link (facilities.location_url): a full link such as
--      https://www.google.com/maps/place/Name/@13.0827,80.2707,17z/... or ...?q=13.0827,80.2707 or ...!3d13.0827!4d80.2707.
-- A short link (maps.app.goo.gl/...) carries no coordinates and cannot be opened from the database, so such a venue has no position
-- and is listed after the ones that do.
--
-- Re-runnable (create or replace).

create or replace function parse_map_coords(p_url text)
returns numeric[]
language plpgsql
immutable
set search_path = public
as $$
declare
  m text[];
begin
  if p_url is null or btrim(p_url) = '' then
    return null;
  end if;
  m := regexp_match(p_url, '@(-?[0-9]{1,2}\.[0-9]+),(-?[0-9]{1,3}\.[0-9]+)');
  if m is null then
    m := regexp_match(p_url, '!3d(-?[0-9]{1,2}\.[0-9]+)!4d(-?[0-9]{1,3}\.[0-9]+)');
  end if;
  if m is null then
    m := regexp_match(p_url, '[?&](?:q|ll|query|destination|center)=(-?[0-9]{1,2}\.[0-9]+)(?:,|%2C)(-?[0-9]{1,3}\.[0-9]+)');
  end if;
  if m is null then
    return null;
  end if;
  -- a latitude is within +-90 and a longitude within +-180; anything else is not a position
  if abs(m[1]::numeric) > 90 or abs(m[2]::numeric) > 180 then
    return null;
  end if;
  return array[m[1]::numeric, m[2]::numeric];
end;
$$;

create or replace function list_public_venue_coords(p_city text, p_state text default null)
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
  pos as (
    select f.id,
           coalesce(f.latitude, (parse_map_coords(f.location_url))[1]) as lat,
           coalesce(f.longitude, (parse_map_coords(f.location_url))[2]) as lng
      from facilities f, want w
     where f.status = 'ACTIVE'
       and f.onboarding_step = 'COMPLETED'
       and w.city <> ''
       and (case when lower(trim(coalesce(f.city, ''))) in ('bengaluru', 'bangalore') then 'bangalore' else lower(trim(coalesce(f.city, ''))) end) = w.city
       and (w.state = '' or lower(trim(coalesce(f.state, ''))) in ('', w.state))
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'lat', lat, 'lng', lng)), '[]'::jsonb)
    from pos
   where lat is not null and lng is not null;
$$;

revoke all on function list_public_venue_coords(text, text) from public;
grant execute on function list_public_venue_coords(text, text) to anon, authenticated;
revoke all on function parse_map_coords(text) from public;
grant execute on function parse_map_coords(text) to anon, authenticated;
