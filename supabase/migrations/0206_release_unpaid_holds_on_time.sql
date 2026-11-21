-- 0206: an unpaid hold is given back ON TIME, not "the next time somebody happens to look".
--
-- Migration 0205 made a hold last 5 minutes. But release_expired_booking_holds() only ran inside a few actions (making a booking, opening a
-- receipt), so a hold that nobody touched stayed "pending" past its time. Seen from the Player app that meant:
--   * the court still looked taken to every other player,
--   * the player still saw a "payment pending" prompt on Home and a pending booking in My Bookings.
--
-- Two fixes, either of which is enough on its own:
--   1. A job that runs every minute and releases every hold whose time is up (pg_cron).
--   2. The three player-facing reads (court availability, Home, My Bookings) release expired holds themselves, first thing, so what the player
--      sees is right even if the job is not running yet. They were declared STABLE (read-only); releasing is a write, so they become VOLATILE.
--
-- Safe to run more than once: a function that already releases is left alone, and the job is replaced, not duplicated.

-- ── 2. the player-facing reads release expired holds before they read ────────────────────────────────────────────
do $fix$
declare
  r        record;
  v_def    text;
  v_new    text;
  v_fixed  integer := 0;
begin
  for r in
    select p.oid, p.proname, l.lanname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_language l on l.oid = p.prolang
     where n.nspname = 'public'
       and p.proname in ('get_public_court_availability', 'get_player_dashboard', 'get_my_guest_bookings')
       and p.prosrc not like '%release_expired_booking_holds%'
  loop
    begin
      v_def := pg_get_functiondef(r.oid);
      -- read-only (STABLE) becomes VOLATILE, because releasing a hold is a write
      -- (pg_get_functiondef prints the attribute in the header, e.g. " STABLE SECURITY DEFINER"; the first match is that header)
      v_new := regexp_replace(v_def, E'\\mSTABLE\\M', 'VOLATILE');
      if r.lanname = 'sql' then
        -- a SQL function: a statement in front of the query
        v_new := regexp_replace(v_new, E'(AS \\$[a-z_]*\\$\n)', E'\\1  select release_expired_booking_holds();\n', 'i');
      else
        -- a PL/pgSQL function: right after its first BEGIN
        v_new := regexp_replace(v_new, E'(\\mBEGIN\\M\n)', E'\\1  perform release_expired_booking_holds();\n', 'i');
      end if;
      if v_new <> v_def and v_new like '%release_expired_booking_holds%' then
        execute v_new;
        v_fixed := v_fixed + 1;
      else
        raise notice 'Function % was not changed (its layout was not what this migration expects).', r.proname;
      end if;
    exception when others then
      raise notice 'Could not update function % (%): %', r.proname, r.oid, sqlerrm;
    end;
  end loop;
  raise notice '% player-facing function(s) now release expired holds first.', v_fixed;
end
$fix$;

-- ── 1. the every-minute job ──────────────────────────────────────────────────────────────────────────────────────
do $cron$
begin
  create extension if not exists pg_cron;
  if exists (select 1 from cron.job where jobname = 'release-booking-holds') then
    perform cron.unschedule('release-booking-holds');
  end if;
  perform cron.schedule('release-booking-holds', '* * * * *', 'select public.release_expired_booking_holds()');
  raise notice 'The release job is scheduled to run every minute.';
exception when others then
  raise notice 'Could not schedule the every-minute job (%). Turn on pg_cron under Database > Extensions and run this block again. The reads above already release holds, so players see the right thing meanwhile.', sqlerrm;
end
$cron$;
