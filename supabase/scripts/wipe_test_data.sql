-- ═══════════════════════════════════════════════════════════════════════════
-- FULL RESET: delete every club, every record and every login EXCEPT the platform admin (admin@gameall.co).
--                         !!  DELETES EVERYTHING - READ BEFORE RUNNING  !!
--
-- DELETES   all clubs and everything under them (courts, bookings, payments, refunds, members, memberships, coaching, finance,
--           inventory, maintenance, staff, custom roles, club plan subscriptions...), all Player-app players, and EVERY login
--           (auth.users) except admin@gameall.co. Club owners lose their accounts too and must sign up again.
-- KEEPS     the admin login + its profile, and the platform's own setup: sports, plans, plan pages, permissions, system roles,
--           access pages, platform settings, the default expense / maintenance categories.
-- NOT TOUCHED  files in Supabase Storage (club photos): empty those in Storage -> Buckets if you want them gone.
--              Razorpay: nothing is deleted there (payments, refunds, subscriptions and links stay in your Razorpay dashboard;
--              cancel live AutoPay subscriptions in Razorpay if any are still active).
--
-- HOW TO USE (Supabase -> SQL editor, as the postgres role):
--   1. Run it as it is. It stops with an error if admin@gameall.co does not exist, deletes inside ONE transaction, prints what is
--      left, and then ROLLS BACK. Nothing really changes. Check the numbers at the end.
--   2. Take a backup (Database -> Backups). 3. Change the last line  rollback;  to  commit;  and run again.  NO UNDO AFTER COMMIT.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- safety: never run this if the admin login is missing, or you would lock yourself out
do $$
begin
  if not exists (select 1 from auth.users where lower(email) = 'admin@gameall.co') then
    raise exception 'admin@gameall.co was not found in auth.users - nothing was deleted.';
  end if;
end $$;

-- 1) the few club-scoped rows that live in tables we keep
delete from role_permissions where role_id in (select id from roles where facility_id is not null);
delete from roles where facility_id is not null;
delete from expense_categories where facility_id is not null;
delete from maintenance_issue_categories where facility_id is not null;

-- 2) every other table in the public schema (all club data), in one statement so the foreign keys between them are fine
do $$
declare
  t text;
begin
  select string_agg(format('%I.%I', schemaname, tablename), ', ')
    into t
    from pg_tables
   where schemaname = 'public'
     and tablename not in (
       -- kept: the platform's own setup
       'sports', 'plans', 'plan_pages', 'platform_settings', 'permissions', 'role_permissions', 'roles', 'access_pages',
       'expense_categories', 'maintenance_issue_categories',
       -- kept: the admin's profile (the others go with their login below); facilities are deleted in step 3
       'profiles', 'facilities'
     );
  execute 'truncate table ' || t || ' restart identity';
end $$;

-- 3) the clubs themselves
delete from facilities;

-- 4) every login except the admin (their profile / player row goes with them)
delete from auth.users where lower(coalesce(email, '')) <> 'admin@gameall.co';
delete from profiles where id not in (select id from auth.users);

-- what is left
select 'auth.users (should be 1: the admin)' as what, count(*) from auth.users
union all select 'profiles', count(*) from profiles
union all select 'facilities', count(*) from facilities
union all select 'bookings', count(*) from bookings
union all select 'payments', count(*) from payments
union all select 'members', count(*) from members
union all select 'players', count(*) from players
union all select 'sports (kept)', count(*) from sports
union all select 'plans (kept)', count(*) from plans;

rollback;   -- DRY RUN. Change this word to  commit;  to really delete.
