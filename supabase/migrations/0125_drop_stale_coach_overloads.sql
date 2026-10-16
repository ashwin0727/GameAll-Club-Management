-- ═══════════════════════════════════════════════════════════════════════════
-- add_coach / update_coach were each redefined with extra defaulted parameters (0095, 0099) under a NEW
-- signature, which left the original shorter version alive next to it. PostgREST then cannot choose between
-- the two for a named-argument call and fails with "Could not choose the best candidate function" — the
-- Flutter Add Coach error. The longer versions accept every call the shorter ones did (the extra params have
-- defaults), so the stale ones are simply dropped. Same fix 0114 made for list_coaches.
-- ═══════════════════════════════════════════════════════════════════════════
drop function if exists add_coach(uuid, uuid, text, numeric, text, text, integer, text, date);
drop function if exists update_coach(uuid, text, numeric, text, text, integer, text, date);
