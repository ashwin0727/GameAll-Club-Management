-- ═══════════════════════════════════════════════════════════════════════════
-- CLEANUP for seed_qa_edge_cases.sql — removes exactly the QA venues and everything that hangs off them.
--
-- Scope: every facility whose slug starts with "qa-" and that is listed in qa_seed_log, the QA coach logins ("coach.qa.….@example.invalid")
-- and the player-state rows the seed made for your test player. Real venues, members and payments are never touched.
--
-- Run the whole file once. Safe to run twice (the second run finds nothing).
-- ═══════════════════════════════════════════════════════════════════════════

do $clean$
declare
  v_ids uuid[];
  v_before bigint;
begin
  if to_regclass('public.qa_seed_log') is null then
    raise notice 'Nothing to clean: qa_seed_log does not exist.';
    return;
  end if;

  select array_agg(f.id) into v_ids
    from facilities f
   where f.slug like 'qa-%' and f.id in (select id from qa_seed_log where tbl = 'facilities');
  select count(*) into v_before from qa_seed_log;
  if v_ids is null then
    raise notice 'No QA venues found (log has % rows).', v_before;
  else
    raise notice 'Removing % QA venues…', array_length(v_ids, 1);

    -- money and bookings first (they point at courts, members, memberships)
    delete from refunds where facility_id = any (v_ids);
    delete from payments where facility_id = any (v_ids);
    delete from payment_orders where facility_id = any (v_ids);
    delete from bookings where facility_id = any (v_ids);

    -- maintenance
    delete from maintenance_blocks where facility_id = any (v_ids);
    delete from maintenance_tickets where facility_id = any (v_ids);

    -- memberships and their batches
    delete from membership_session_bookings where facility_id = any (v_ids);
    delete from membership_batch_members where batch_id in (select id from membership_batches where facility_id = any (v_ids));
    delete from membership_subscriptions where facility_id = any (v_ids);
    delete from memberships where facility_id = any (v_ids);
    delete from membership_batches where facility_id = any (v_ids);
    delete from membership_plans where facility_id = any (v_ids);

    -- coaching (events and sessions the app generated, then enrolments, batches, programmes, coaches)
    delete from coaching_events where facility_id = any (v_ids);
    delete from coaching_session_students where session_id in (select id from coaching_sessions where facility_id = any (v_ids));
    delete from coaching_sessions where facility_id = any (v_ids);
    delete from coaching_enrollments where facility_id = any (v_ids);
    delete from coaching_program_batches where facility_id = any (v_ids);
    delete from coaching_programs where facility_id = any (v_ids);
    delete from coach_sports where facility_id = any (v_ids);
    delete from coaches where facility_id = any (v_ids);

    -- people and venue set-up
    delete from guest_players where facility_id = any (v_ids);
    delete from members where facility_id = any (v_ids);
    delete from courts where facility_id = any (v_ids);
    delete from facility_images where facility_id = any (v_ids);
    delete from facility_sports where facility_id = any (v_ids);
    delete from facility_users where facility_id = any (v_ids);
    delete from facilities where id = any (v_ids);   -- hours, pricing and the rest cascade
  end if;

  -- the QA coach logins
  delete from profiles where id in (select id from qa_seed_log where tbl = 'auth_users');
  delete from auth.users where id in (select id from qa_seed_log where tbl = 'auth_users');

  delete from qa_seed_log;
  drop table if exists qa_seed_log;
  raise notice 'QA data removed.';
end
$clean$;
