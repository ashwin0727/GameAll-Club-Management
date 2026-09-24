-- ═══════════════════════════════════════════════════════════════════════════
-- Membership plans: description + category — for the new Create Membership
-- Plan page. Both nullable, plain columns (no RPC needed; createPlan/
-- updatePlan already write straight to the table via the normal REST insert/
-- update, governed by the existing RLS policies).
-- ═══════════════════════════════════════════════════════════════════════════

alter table membership_plans
  add column if not exists description text,
  add column if not exists category text;
