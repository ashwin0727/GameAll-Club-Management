-- ═══════════════════════════════════════════════════════════════════════════
-- Razorpay Payment Verification — Phase 4 (enum extension).
--
-- ALTER TYPE ... ADD VALUE cannot be used in the same transaction as
-- statements that reference the new value, so this is a standalone
-- migration — 0019_payment_verification.sql (which defines the state
-- machine that uses these values) depends on this one having committed
-- first.
-- ═══════════════════════════════════════════════════════════════════════════

alter type payment_order_status add value 'PAYMENT_VERIFICATION_PENDING' after 'PAYMENT_ATTEMPTED';
alter type payment_order_status add value 'PAYMENT_VERIFIED' after 'PAYMENT_VERIFICATION_PENDING';