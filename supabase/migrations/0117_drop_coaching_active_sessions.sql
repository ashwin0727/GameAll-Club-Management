-- ═══════════════════════════════════════════════════════════════════════════
-- Active Sessions is now the current day's session count (taken from the session list by the app), so the
-- pending-sessions function added in 0116 is unused. Safe to run repeatedly.
-- ═══════════════════════════════════════════════════════════════════════════
drop function if exists get_coaching_active_sessions(uuid);
