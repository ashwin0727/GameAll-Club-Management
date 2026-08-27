-- ═══════════════════════════════════════════════════════════════════════════
-- Cancellation, Refund & Payment Recovery — Phase 6 (enum extension).
--
-- ALTER TYPE ... ADD VALUE cannot be used in the same transaction as
-- statements that reference the new value, so this is a standalone
-- migration — 0023_cancellation_refunds.sql (which defines the refund
-- state machine that uses it) depends on this one having committed first.
--
-- payment_orders.status already has REFUND_REQUESTED/REFUNDED (0016) but
-- they were never wired up — Phase 6 uses REFUNDED as the terminal "fully
-- refunded" state and adds PARTIALLY_REFUNDED for the multi-partial-refund
-- case; REFUND_REQUESTED is deliberately left unused at the order level
-- (a refund being merely *requested* must never imply the whole order is
-- refunded — see 0023's refunds.status, which tracks that lifecycle
-- instead, spec §39/§25).
-- ═══════════════════════════════════════════════════════════════════════════

alter type payment_order_status add value 'PARTIALLY_REFUNDED' after 'REFUND_REQUESTED';

-- The refund's own lifecycle — deliberately separate from payment_orders.status
-- (spec §39: "Payment and Refund are separate lifecycle concepts").
create type refund_status as enum ('REQUESTED', 'PROCESSING', 'PENDING', 'PROCESSED', 'FAILED', 'CANCELLED');

create type refund_reason as enum (
  'CUSTOMER_CANCELLATION',
  'FACILITY_CANCELLATION',
  'COURT_UNAVAILABLE',
  'SETTLEMENT_EXCEPTION',
  'DUPLICATE_PAYMENT',
  'OWNER_OVERRIDE',
  'OTHER'
);