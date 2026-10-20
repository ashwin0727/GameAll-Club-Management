-- ═══════════════════════════════════════════════════════════════════════════
-- CLEANUP for seed_2y_facility_dataset.sql — removes exactly what the seed added.
--
-- It works from the log table seed2y_log (every id the seed created), plus the rows the
-- app generated on its own from seeded data (future coaching sessions, audit events).
--
--   * If the seed CREATED the facility, the facility itself is deleted too.
--   * If the seed used your existing (empty) facility, the facility, its owner link and its
--     sports are kept; only the demo rows go.
--   * The two extra coach logins the seed may have created are deleted.
--
-- Run the whole file once. Safe to run twice (the second run finds nothing).
-- ═══════════════════════════════════════════════════════════════════════════

do $clean$
declare
  v_fac uuid;
  v_before bigint;
begin
  if to_regclass('public.seed2y_log') is null then
    raise notice 'Nothing to clean: seed2y_log does not exist.';
    return;
  end if;
  select count(*) into v_before from seed2y_log;
  select id into v_fac from seed2y_log where tbl = 'facility' limit 1;

  -- audit rows and sessions the app generated itself from seeded programs / enrollments
  delete from coaching_events
   where program_id in (select id from seed2y_log where tbl = 'coaching_programs')
      or enrollment_id in (select id from seed2y_log where tbl = 'coaching_enrollments')
      or coach_id in (select id from seed2y_log where tbl = 'coaches');
  delete from coaching_session_students
   where session_id in (select id from coaching_sessions where program_id in (select id from seed2y_log where tbl = 'coaching_programs'));
  delete from coaching_session_students where id in (select id from seed2y_log where tbl = 'coaching_session_students');
  delete from coaching_sessions where program_id in (select id from seed2y_log where tbl = 'coaching_programs');
  delete from coaching_sessions where id in (select id from seed2y_log where tbl = 'coaching_sessions');

  -- money first (payments point at bookings / memberships / enrollments / orders)
  delete from refunds where id in (select id from seed2y_log where tbl = 'refunds');
  delete from payments
   where id in (select id from seed2y_log where tbl = 'payments')
      or booking_id in (select id from seed2y_log where tbl = 'bookings')
      or membership_id in (select id from seed2y_log where tbl = 'memberships')
      or coaching_enrollment_id in (select id from seed2y_log where tbl = 'coaching_enrollments')
      or membership_session_booking_id in (select id from seed2y_log where tbl = 'membership_session_bookings');
  delete from payment_orders where id in (select id from seed2y_log where tbl = 'payment_orders')
                                or booking_id in (select id from seed2y_log where tbl = 'bookings');

  delete from membership_session_bookings where id in (select id from seed2y_log where tbl = 'membership_session_bookings');
  delete from membership_sessions where id in (select id from seed2y_log where tbl = 'membership_sessions');
  delete from bookings where id in (select id from seed2y_log where tbl = 'bookings');

  -- coaching
  delete from coaching_enrollment_billing where id in (select id from seed2y_log where tbl = 'coaching_enrollment_billing')
                                             or enrollment_id in (select id from seed2y_log where tbl = 'coaching_enrollments');
  delete from coaching_enrollments where id in (select id from seed2y_log where tbl = 'coaching_enrollments');
  delete from coaching_program_batches where id in (select id from seed2y_log where tbl = 'coaching_program_batches');
  delete from coaching_programs where id in (select id from seed2y_log where tbl = 'coaching_programs');
  delete from coach_sports where coach_id in (select id from seed2y_log where tbl = 'coaches');
  delete from coaches where id in (select id from seed2y_log where tbl = 'coaches');

  -- memberships
  delete from membership_subscriptions where id in (select id from seed2y_log where tbl = 'membership_subscriptions');
  delete from membership_batch_members where id in (select id from seed2y_log where tbl = 'membership_batch_members');
  delete from memberships where id in (select id from seed2y_log where tbl = 'memberships');
  delete from membership_batches where id in (select id from seed2y_log where tbl = 'membership_batches');
  delete from membership_plans where id in (select id from seed2y_log where tbl = 'membership_plans');

  -- finance
  delete from expense_payments where id in (select id from seed2y_log where tbl = 'expense_payments')
                                  or expense_id in (select id from seed2y_log where tbl = 'expenses');
  delete from expenses where id in (select id from seed2y_log where tbl = 'expenses');
  delete from daily_closing_events where closing_id in (select id from seed2y_log where tbl = 'daily_closings');
  delete from daily_closings where id in (select id from seed2y_log where tbl = 'daily_closings');

  -- people
  delete from members where id in (select id from seed2y_log where tbl = 'members');
  delete from guest_players where id in (select id from seed2y_log where tbl = 'guest_players');

  -- courts the seed added
  delete from courts where id in (select id from seed2y_log where tbl = 'courts');

  -- the facility, if the seed made it (everything left under it cascades)
  if v_fac is not null then
    delete from facilities where id = v_fac;
  end if;

  -- extra coach logins
  delete from auth.users where id in (select id from seed2y_log where tbl = 'auth_users');

  raise notice 'Removed % logged rows%.', v_before, case when v_fac is not null then ' and the facility' else '' end;
end
$clean$;

drop table if exists seed2y_log;
drop function if exists seed2y_h(text);
