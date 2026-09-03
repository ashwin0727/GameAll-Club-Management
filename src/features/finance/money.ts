import type { FinanceSummary } from "./types";

/**
 * Finance arithmetic, in one place.
 *
 * The database is authoritative — get_finance_summary computes these same
 * figures server-side over the whole ledger, and the dashboard renders what
 * it returns. These helpers exist so the client can label and check that
 * answer consistently (and so the rules are testable) rather than each
 * screen summing rows itself.
 *
 * Everything is in integer minor units. Money never touches a float here:
 * 0.1 + 0.2 is not 0.3, and a rupee lost to binary rounding in a ledger is
 * a rupee somebody has to explain.
 */

/** Gross takings, less refunds, less what the facility spent. */
export function netRevenueMinor(summary: {
  grossRevenueMinor: number;
  refundsMinor: number;
  expensesMinor: number;
}): number {
  return summary.grossRevenueMinor - summary.refundsMinor - summary.expensesMinor;
}

/** What actually stayed in the account after giving money back. */
export function realisedRevenueMinor(summary: {
  grossRevenueMinor: number;
  refundsMinor: number;
}): number {
  return summary.grossRevenueMinor - summary.refundsMinor;
}

/** A facility can spend more than it takes; the figure is allowed to be negative. */
export function isLoss(summary: Pick<FinanceSummary, "grossRevenueMinor" | "refundsMinor" | "expensesMinor">): boolean {
  return netRevenueMinor(summary) < 0;
}

/**
 * Whether a payment of this size may be recorded against an amount owed.
 *
 * Guards the two mistakes that cost real money: taking more than is owed,
 * and recording a payment against something already settled. The database
 * enforces both as well — this is what lets the form say so before the
 * round trip.
 */
export function canRecordPayment(input: {
  amountMinor: number;
  outstandingMinor: number;
}): { ok: true } | { ok: false; reason: string } {
  if (!Number.isFinite(input.amountMinor) || input.amountMinor <= 0) {
    return { ok: false, reason: "Enter an amount greater than zero." };
  }
  if (input.outstandingMinor <= 0) {
    return { ok: false, reason: "This booking has already been paid." };
  }
  if (input.amountMinor > input.outstandingMinor) {
    return { ok: false, reason: "That's more than the amount outstanding." };
  }
  return { ok: true };
}

/**
 * Whether a refund of this size may be issued.
 *
 * Never more than was actually taken, and never against money that was
 * never collected.
 */
export function canRefund(input: {
  amountMinor: number;
  paidMinor: number;
  alreadyRefundedMinor: number;
}): { ok: true } | { ok: false; reason: string } {
  const refundable = input.paidMinor - input.alreadyRefundedMinor;
  if (!Number.isFinite(input.amountMinor) || input.amountMinor <= 0) {
    return { ok: false, reason: "Enter an amount greater than zero." };
  }
  if (input.paidMinor <= 0) {
    return { ok: false, reason: "There's nothing to refund — no payment was taken." };
  }
  if (refundable <= 0) {
    return { ok: false, reason: "This payment has already been fully refunded." };
  }
  if (input.amountMinor > refundable) {
    return { ok: false, reason: "That's more than the amount available to refund." };
  }
  return { ok: true };
}

/** How a payment reads once part of it has been given back. */
export type SettlementState = "UNPAID" | "PARTIALLY_PAID" | "PAID" | "PARTIALLY_REFUNDED" | "REFUNDED";

export function settlementState(input: {
  totalMinor: number;
  paidMinor: number;
  refundedMinor: number;
}): SettlementState {
  if (input.refundedMinor > 0) {
    return input.refundedMinor >= input.paidMinor ? "REFUNDED" : "PARTIALLY_REFUNDED";
  }
  if (input.paidMinor <= 0) return "UNPAID";
  return input.paidMinor >= input.totalMinor ? "PAID" : "PARTIALLY_PAID";
}

/** Rupees from minor units, for display only — never for arithmetic. */
export function toMajor(amountMinor: number): number {
  return amountMinor / 100;
}
