-- ═══════════════════════════════════════════════════════════════════════════
-- Onboarding redesign — foundation
--
-- The redesigned Facility Details screen replaces the "drop a map pin"
-- affordance with a field where the owner pastes a Google Maps location
-- link. Stored verbatim; latitude/longitude (added in 0002) stay unused.
--
-- The step restructure (merging Sports + Courts into one "Sports & Courts"
-- step, moving Pricing ahead of Operating Hours) needs no schema change:
-- the mobile client maps the existing SPORTS/COURTS enum values onto the
-- single merged step and writes COURTS when it completes.
-- ═══════════════════════════════════════════════════════════════════════════

alter table facilities add column if not exists location_url text;
