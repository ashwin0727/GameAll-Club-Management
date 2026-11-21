-- 0207: the three player-facing reads release expired unpaid holds before they answer.
--
-- 0206 tried to do this by editing the text of each function; on this database that did not take effect (the functions stayed as they were).
-- This version does not touch the functions' text at all. Each original is renamed to <name>_core (unchanged, and no longer callable from the
-- app), and a thin wrapper with the ORIGINAL name takes its place:
--
--     wrapper:  release_expired_booking_holds();  return <name>_core(...);
--
-- so the app calls exactly the same names with exactly the same arguments and gets exactly the same answers, but a hold whose 5 minutes are up
-- is given back first. The wrapper is VOLATILE (releasing is a write); the original stays as it was.
--
-- The wrappers keep the query time limits that 0185 put on these reads (8 s for the player reads, 5 s for the public availability).
--
-- The every-minute job from 0206 stays: it frees holds nobody looks at. This makes what a player SEES exact at the moment they look.
--
-- Safe to run more than once. NOTE for later work: if a future migration re-creates get_player_dashboard, get_my_guest_bookings or
-- get_public_court_availability with CREATE OR REPLACE, it replaces the wrapper; change the <name>_core function instead.

do $wrap$
begin
  -- Home (payment prompts, bookings with money owed)
  if to_regprocedure('public.get_player_dashboard_core()') is null then
    alter function public.get_player_dashboard() rename to get_player_dashboard_core;
    create function public.get_player_dashboard() returns jsonb
      language plpgsql volatile security definer set search_path = public set statement_timeout = '8s'
      as $f$
      begin
        perform release_expired_booking_holds();
        return get_player_dashboard_core();
      end
      $f$;
    revoke all on function public.get_player_dashboard() from public, anon;
    grant execute on function public.get_player_dashboard() to authenticated;
    revoke all on function public.get_player_dashboard_core() from public, anon, authenticated;
  end if;

  -- My Bookings
  if to_regprocedure('public.get_my_guest_bookings_core()') is null then
    alter function public.get_my_guest_bookings() rename to get_my_guest_bookings_core;
    create function public.get_my_guest_bookings() returns jsonb
      language plpgsql volatile security definer set search_path = public set statement_timeout = '8s'
      as $f$
      begin
        perform release_expired_booking_holds();
        return get_my_guest_bookings_core();
      end
      $f$;
    revoke all on function public.get_my_guest_bookings() from public, anon;
    grant execute on function public.get_my_guest_bookings() to authenticated;
    revoke all on function public.get_my_guest_bookings_core() from public, anon, authenticated;
  end if;

  -- free and busy slots (what every other player sees)
  if to_regprocedure('public.get_public_court_availability_core(uuid, uuid, date)') is null then
    alter function public.get_public_court_availability(uuid, uuid, date) rename to get_public_court_availability_core;
    create function public.get_public_court_availability(p_facility_id uuid, p_facility_sport_id uuid, p_date date) returns jsonb
      language plpgsql volatile security definer set search_path = public set statement_timeout = '5s'
      as $f$
      begin
        perform release_expired_booking_holds();
        return get_public_court_availability_core(p_facility_id, p_facility_sport_id, p_date);
      end
      $f$;
    revoke all on function public.get_public_court_availability(uuid, uuid, date) from public;
    grant execute on function public.get_public_court_availability(uuid, uuid, date) to anon, authenticated;
    revoke all on function public.get_public_court_availability_core(uuid, uuid, date) from public, anon, authenticated;
  end if;
end
$wrap$;
