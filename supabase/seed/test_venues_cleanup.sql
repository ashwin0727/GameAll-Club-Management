-- ═══════════════════════════════════════════════════════════════════════════
-- GameAll — REMOVE THE TEST VENUES loaded by test_venues_seed.sql
--
-- Deletes everything the seed script created and nothing else. It finds the data by its markers:
--   * facilities whose slug starts with "seed-"          (and everything under them: courts, photos, rates, hours, plans, programmes,
--                                                         members, memberships, enrolments, bookings)
--   * the owner account seed.owner@gameall.test
--   * players created by logging in with the test numbers 9000000001 - 9000000003
--
-- Run it in the Supabase SQL editor. It is safe to run twice. At the end it prints how many seed rows are left (all zeros = clean).
-- Nothing here touches real venues: a real facility never has a "seed-" slug or the seed owner.
-- ═══════════════════════════════════════════════════════════════════════════

do $cleanup$
declare
  ids uuid[] := array(select id from facilities where slug like 'seed-%');
  owner_ids uuid[] := array(select id from auth.users where lower(email) = 'seed.owner@gameall.test');
  test_player_ids uuid[] := array(
    select u.id from auth.users u
     where right(regexp_replace(coalesce(u.phone, ''), '\D', '', 'g'), 10) in ('9000000001', '9000000002', '9000000003'));
begin
  -- children that other tables protect with RESTRICT go first, in dependency order
  delete from coaching_session_students where facility_id = any(ids);
  delete from coaching_sessions where facility_id = any(ids);
  delete from coaching_enrollments where facility_id = any(ids);
  delete from membership_session_bookings where facility_id = any(ids);
  delete from bookings where facility_id = any(ids);
  delete from payments where facility_id = any(ids);
  delete from memberships where facility_id = any(ids);
  delete from members where facility_id = any(ids);
  delete from guest_players where facility_id = any(ids);
  delete from coaching_programs where facility_id = any(ids);

  -- the venues themselves (courts, sports, rates, hours, photos, plans and the owner's staff link go with them)
  delete from facilities where id = any(ids);

  -- the owner account (its profile goes with it)
  delete from facility_users where user_id = any(owner_ids);
  delete from auth.users where id = any(owner_ids);

  -- test players who signed in with a test number
  delete from players where id = any(test_player_ids);
  delete from auth.users where id = any(test_player_ids);
  delete from player_login_attempts where right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 10) in ('9000000001', '9000000002', '9000000003');
end
$cleanup$;

-- What is left (every number should be 0):
select
  (select count(*) from facilities where slug like 'seed-%') as venues,
  (select count(*) from auth.users where lower(email) = 'seed.owner@gameall.test') as owner_accounts,
  (select count(*) from members where phone in ('9000000001', '9000000002', '9000000003') or phone = '+91 90000 00001') as members,
  (select count(*) from bookings where right(regexp_replace(coalesce(guest_phone, ''), '\D', '', 'g'), 10) in ('9000000001', '9000000002', '9000000003')) as test_bookings,
  (select count(*) from auth.users where right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 10) in ('9000000001', '9000000002', '9000000003')) as test_logins;
