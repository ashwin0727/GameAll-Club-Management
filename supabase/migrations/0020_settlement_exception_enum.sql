-- ═══════════════════════════════════════════════════════════════════════════
-- Payment Settlement & Business Confirmation — Phase 5 (enum extension).
--
-- ALTER TYPE ... ADD VALUE cannot be used in the same transaction as
-- statements that reference the new value, so this is a standalone
-- migration — 0021_payment_settlement.sql depends on this one having
-- committed first.
--
-- SETTLEMENT_EXCEPTION is distinct from FAILED: FAILED means the PAYMENT
-- itself failed (never captured). SETTLEMENT_EXCEPTION means the payment
-- WAS captured — money changed hands — but the business operation it was
-- for (confirm a booking, activate a membership) could not be completed at
-- settlement time (e.g. the booking was cancelled in the meantime). The
-- payment and its Finance transaction are never lost in that case; a
-- settlement_exceptions row records why, for the facility to resolve.
-- ═══════════════════════════════════════════════════════════════════════════

alter type payment_order_status add value 'SETTLEMENT_EXCEPTION' after 'CAPTURED';