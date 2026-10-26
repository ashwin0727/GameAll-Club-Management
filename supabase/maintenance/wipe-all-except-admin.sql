-- ═══════════════════════════════════════════════════════════════════════════
-- WIPE EVERYTHING EXCEPT THE ADMIN ACCOUNT.   *** IRREVERSIBLE ***
--
-- Deletes every facility and everything under it (courts, sports, bookings, memberships, members, coaching, payments,
-- settlements, payout details, staff, plans/subscriptions, inventory, maintenance ...), every user account except
-- admin@gameall.co, and the leftover OTP / webhook / support / security logs.
--
-- Kept: admin@gameall.co (auth user + profile), and the platform's own reference data — sports catalogue, permissions,
-- role templates, access pages, plans and plan pages, and the schema itself.
--
-- This file is NOT a migration. Run it by hand in the Supabase SQL editor, in two steps:
--   STEP 1  run the PREVIEW block alone and read the numbers.
--   STEP 2  run the WIPE block. It is one transaction: if anything fails, nothing is deleted. It also refuses to run unless
--           admin@gameall.co exists, and it aborts (rolls back) if the admin account is not still there at the end.
--
-- BEFORE YOU RUN IT
--   • Take a backup (Dashboard → Database → Backups, or pg_dump). There is no undo.
--   • Cancel the live Razorpay subscriptions (membership AutoPay, coaching AutoPay, GameAll plan subscriptions) in the
--     Razorpay dashboard — deleting rows here does NOT stop Razorpay from charging those customers.
--   • Uploaded files (facility logos etc.) live in Storage, not here; empty those buckets from the dashboard if you want them gone.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── STEP 1 · PREVIEW (read-only) ──────────────────────────────────────────────
select
  (select count(*) from auth.users where lower(email) = 'admin@gameall.co')              as admin_accounts_kept,
  (select count(*) from auth.users where lower(email) is distinct from 'admin@gameall.co') as users_to_delete,
  (select count(*) from facilities)                                                       as facilities_to_delete,
  (select count(*) from courts)                                                           as courts_to_delete,
  (select count(*) from memberships)                                                      as memberships_to_delete,
  (select count(*) from members)                                                          as members_to_delete,
  (select count(*) from payments)                                                         as payments_to_delete,
  (select count(*) from bookings)                                                         as bookings_to_delete;


-- ── STEP 2 · WIPE ─────────────────────────────────────────────────────────────
do $$
declare
  v_admin uuid;
begin
  select id into v_admin from auth.users where lower(email) = 'admin@gameall.co';
  if v_admin is null then
    raise exception 'admin@gameall.co does not exist — refusing to wipe anything.';
  end if;

  -- Every facility, and (through ON DELETE CASCADE) everything that belongs to one.
  delete from facilities;

  -- Logs and one-time codes that are not tied to a facility.
  delete from razorpay_webhook_events;
  delete from mobile_otp_sends;
  delete from mobile_otps;
  delete from signup_otps;
  delete from support_tickets;
  delete from security_events;

  -- Every account except the admin. Profiles, identities, sessions and verified phones go with them.
  delete from auth.users where id <> v_admin;

  -- Last line of defence: the admin must still be here, with its profile.
  if not exists (select 1 from auth.users where id = v_admin) or not exists (select 1 from profiles where id = v_admin) then
    raise exception 'The admin account would have been removed — rolled back.';
  end if;
end;
$$;

-- Afterwards, this should show exactly one user and nothing else:
select
  (select count(*) from auth.users)  as users_left,
  (select count(*) from profiles)    as profiles_left,
  (select count(*) from facilities)  as facilities_left,
  (select count(*) from payments)    as payments_left;
