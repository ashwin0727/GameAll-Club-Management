-- ============================================================================
-- Reset the database for fresh testing.
--
-- DESTRUCTIVE AND IRREVERSIBLE. Take a backup first (Supabase Dashboard →
-- Database → Backups) — there is no undo.
--
-- Run ONE of the three options below. They are mutually exclusive; do not
-- run more than one. Each is wrapped in a transaction, so a failure part-way
-- rolls the whole thing back rather than leaving half-cleared tables.
--
-- `public.sports` is NEVER cleared by any option: it is the global sport
-- catalogue (no facility_id), seeded by migration and referenced by every
-- facility. Wiping it would break onboarding for every new facility.
-- ============================================================================


-- ============================================================================
-- OPTION A — Full reset, keep your login.  ← the usual choice
--
-- Clears every facility, court, booking, member, payment and setting, but
-- leaves auth.users and public.profiles intact. You sign in with the same
-- credentials and land back at onboarding Step 1 with an empty slate.
-- ============================================================================

begin;

truncate table
  public.bookings,
  public.cancellation_policies,
  public.courts,
  public.facilities,
  public.facility_sports,
  public.facility_users,
  public.guest_players,
  public.inventory_items,
  public.inventory_transactions,
  public.members,
  public.membership_batch_blocked_dates,
  public.membership_batch_members,
  public.membership_batches,
  public.membership_plans,
  public.membership_session_bookings,
  public.membership_sessions,
  public.membership_subscriptions,
  public.memberships,
  public.operating_days,
  public.operating_schedules,
  public.operating_time_slots,
  public.payment_orders,
  public.payments,
  public.pricing_plans,
  public.pricing_rules,
  public.razorpay_webhook_events,
  public.refunds,
  public.settlement_exceptions
restart identity cascade;

commit;


-- ============================================================================
-- OPTION B — Keep the facility setup, clear only the activity.
--
-- Keeps facilities, courts, sports config, operating hours and pricing, so
-- you skip onboarding. Clears bookings, members, memberships, payments and
-- inventory movements. Use this when you want to re-test the booking and
-- membership flows against a facility you've already configured.
-- ============================================================================

-- begin;
--
-- truncate table
--   public.bookings,
--   public.guest_players,
--   public.inventory_transactions,
--   public.members,
--   public.membership_batch_blocked_dates,
--   public.membership_batch_members,
--   public.membership_batches,
--   public.membership_session_bookings,
--   public.membership_sessions,
--   public.membership_subscriptions,
--   public.memberships,
--   public.payment_orders,
--   public.payments,
--   public.razorpay_webhook_events,
--   public.refunds,
--   public.settlement_exceptions
-- restart identity cascade;
--
-- commit;


-- ============================================================================
-- OPTION C — Total wipe, including user accounts.
--
-- Everything in Option A, plus every auth user. You will have to register a
-- brand-new account afterwards; your current credentials stop working.
-- Deleting from auth.users cascades to public.profiles.
--
-- Run the Option A block above FIRST, then uncomment and run this.
-- ============================================================================

-- begin;
--
-- delete from auth.users;
--
-- commit;


-- ============================================================================
-- Verify — run after whichever option you chose. Every listed table should
-- read 0 (except the ones that option deliberately preserves), and `sports`
-- should still hold the seeded catalogue.
-- ============================================================================

select 'sports (preserved)' as table_name, count(*) from public.sports
union all select 'profiles',            count(*) from public.profiles
union all select 'facilities',          count(*) from public.facilities
union all select 'courts',              count(*) from public.courts
union all select 'bookings',            count(*) from public.bookings
union all select 'members',             count(*) from public.members
union all select 'memberships',         count(*) from public.memberships
union all select 'payments',            count(*) from public.payments
order by table_name;
