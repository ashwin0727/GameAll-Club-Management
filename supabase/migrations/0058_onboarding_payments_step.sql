-- ═══════════════════════════════════════════════════════════════════════════
-- Onboarding redesign — Screen 5 "Connect payments"
--
-- A new step between Operating Hours and completion. Full Razorpay Route /
-- linked-account onboarding is a separate future project; for now the step
-- shows the connect UI and can be skipped ("Do this later"), so we only
-- need somewhere to remember whether it was connected.
-- ═══════════════════════════════════════════════════════════════════════════

alter type onboarding_step add value if not exists 'PAYMENTS';

alter table facilities
  add column if not exists payments_connected boolean not null default false;
