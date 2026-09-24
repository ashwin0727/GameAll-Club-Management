-- The Create Plan wizard's own "Plan Badge" toggle (Plan Details step): an owner-set label like
-- "Popular" or "Best Deal" shown on the plan card. Null/empty means no badge — the Plans page
-- falls back to its existing computed "Most Popular" / "Best Value" badges in that case.
alter table public.membership_plans
  add column if not exists badge_text text;
