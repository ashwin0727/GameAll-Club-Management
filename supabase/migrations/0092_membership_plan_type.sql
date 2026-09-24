-- ═══════════════════════════════════════════════════════════════════════════
-- Membership plan type — TIME_BASED (fixed duration, one-time payment) vs
-- RECURRING (auto-renewing, billed on a recurring interval).
--
-- Deliberately reuses what already exists rather than adding a parallel
-- duration model:
--   • duration_days already means two different things depending on intent —
--     for a TIME_BASED plan it's the fixed membership length; for a
--     RECURRING plan it's the billing interval. Both are "how many days
--     until the next thing happens", and create-membership-subscription's
--     own billingCycle() function already derives the Razorpay plan period
--     (monthly/yearly) from duration_days. Adding separate duration_value/
--     duration_unit/billing_interval columns would just be two names for
--     the same number — plan_type is the only genuinely new fact.
--   • Recurring billing itself already has full infrastructure:
--     membership_subscriptions, create/cancel-membership-subscription edge
--     functions, and razorpay-webhook's subscription.* handling. This
--     migration only lets a *plan* declare which of those paths its
--     memberships are meant to use — it adds no new payment machinery.
-- ═══════════════════════════════════════════════════════════════════════════

do $$ begin
  create type membership_plan_type as enum ('TIME_BASED', 'RECURRING');
exception
  when duplicate_object then null;
end $$;

alter table membership_plans
  add column if not exists plan_type membership_plan_type not null default 'TIME_BASED';
