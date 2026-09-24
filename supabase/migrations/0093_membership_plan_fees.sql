-- ═══════════════════════════════════════════════════════════════════════════
-- Membership plans: optional Joining Fee / Security Deposit — the plan-level
-- defaults for the Create Plan wizard's Plan Configuration step. Distinct
-- from a membership's own registration_fee_inr (already collected per
-- member in the Add Member wizard's Select Plan step) — these are what a
-- plan *suggests* by default; choosePlan() carries them over as that
-- membership's starting registration fee, which the owner can still edit.
-- ═══════════════════════════════════════════════════════════════════════════

alter table membership_plans
  add column if not exists joining_fee_inr integer,
  add column if not exists security_deposit_inr integer;

alter table membership_plans
  drop constraint if exists membership_plans_joining_fee_inr_check,
  drop constraint if exists membership_plans_security_deposit_inr_check;

alter table membership_plans
  add constraint membership_plans_joining_fee_inr_check check (joining_fee_inr is null or joining_fee_inr >= 0),
  add constraint membership_plans_security_deposit_inr_check check (security_deposit_inr is null or security_deposit_inr >= 0);
