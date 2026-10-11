-- ═══════════════════════════════════════════════════════════════════════════
-- "Could not choose the best candidate function between: public.list_coaches(...)"
--
-- The live database holds two copies of list_coaches:
--   • (p_facility_id, p_search, p_status, p_specialization, p_limit, p_offset, p_sport_id)            — 7 args, stale
--   • (p_facility_id, p_search, p_status, p_specialization, p_limit, p_offset, p_sport_id, p_sort)    — 8 args, current
-- PostgREST can't pick between them for any call that doesn't pass p_sort, so the Coaches page failed.
--
-- This removes every older copy (the 7-argument one, and the original 6-argument one from 0086 in
-- case it is also still there). The 8-argument version from 0095 is the only list_coaches left.
-- Safe to run repeatedly.
-- ═══════════════════════════════════════════════════════════════════════════
drop function if exists list_coaches(uuid, text, text, text, integer, integer, uuid);
drop function if exists list_coaches(uuid, text, text, text, integer, integer);
