-- ═══════════════════════════════════════════════════════════════════════════
-- Fix create_facility_with_owner: bootstrap the owner's facility_users row
-- as SECURITY DEFINER instead of relying on RLS during the insert itself.
--
-- This is a genuinely self-referential case: facilities_insert_self_owned's
-- WITH CHECK is a simple `owner_id = auth.uid()`, but facility_users' own
-- self-claim policy checks `exists (select 1 from facilities where id =
-- facility_id and owner_id = auth.uid())` — and that SELECT is itself
-- governed by facilities_select_members (`is_facility_member(id)`), which
-- is false for a facility that has no facility_users row yet. The row you
-- just inserted is invisible to your own self-claim check. SECURITY
-- DEFINER sidesteps this by running both inserts with the function's own
-- privileges (bypassing table RLS for just this function), while an
-- explicit auth.uid() check up front enforces the real invariant: only an
-- authenticated caller can run this, and they always become the owner.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function create_facility_with_owner(
  p_name text,
  p_facility_type facility_type,
  p_custom_facility_type text,
  p_business_email text,
  p_business_phone text,
  p_address_line_1 text,
  p_address_line_2 text,
  p_area text,
  p_city text,
  p_state text,
  p_country text,
  p_postal_code text,
  p_latitude numeric,
  p_longitude numeric,
  p_timezone text,
  p_logo_url text,
  p_description text
) returns facilities
language plpgsql
security definer
set search_path = public
as $$
declare
  result facilities;
  facility_slug text;
  caller uuid;
begin
  caller := auth.uid();
  if caller is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  facility_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(gen_random_uuid()::text, 1, 8);

  insert into facilities (
    name, slug, owner_id, facility_type, custom_facility_type,
    business_email, business_phone,
    address_line_1, address_line_2, area, city, state, country, postal_code,
    latitude, longitude, timezone, logo_url, description
  ) values (
    p_name, facility_slug, caller, p_facility_type, p_custom_facility_type,
    p_business_email, p_business_phone,
    p_address_line_1, p_address_line_2, p_area, p_city, p_state,
    coalesce(p_country, 'India'), p_postal_code,
    p_latitude, p_longitude, coalesce(p_timezone, 'Asia/Kolkata'), p_logo_url, p_description
  ) returning * into result;

  insert into facility_users (facility_id, user_id, role)
  values (result.id, caller, 'owner');

  return result;
end;
$$;

-- Explicit, belt-and-suspenders grant — SECURITY DEFINER functions are
-- worth being certain about, and this project's `public` schema was reset
-- at least once already during setup.
grant execute on function create_facility_with_owner(
  text, facility_type, text, text, text, text, text, text, text, text, text, text, numeric, numeric, text, text, text
) to authenticated;