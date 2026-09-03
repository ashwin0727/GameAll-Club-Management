import type { ObligationStatus } from "./types";

/**
 * How an obligation's settle status is derived from its amounts.
 *
 * The database computes this over the whole ledger; this mirrors the same
 * rule so the client can label a row it already holds without another round
 * trip, and so the rule itself is testable. Amounts are integer minor units.
 */
export function obligationStatus(input: {
  totalMinor: number;
  paidMinor: number;
  dueOn?: string | null;
  today?: Date;
}): ObligationStatus {
  const outstanding = input.totalMinor - input.paidMinor;
  if (outstanding <= 0) return "PAID";

  // Overdue is a view of unpaid debt, not a state of its own: still owed,
  // and the date it was owed by has passed.
  if (input.dueOn) {
    const now = input.today ?? new Date();
    const due = new Date(`${input.dueOn}T00:00:00`);
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    if (due < startOfToday) return "OVERDUE";
  }

  return input.paidMinor > 0 ? "PARTIALLY_PAID" : "PENDING";
}

export function outstandingMinor(totalMinor: number, paidMinor: number): number {
  return Math.max(0, totalMinor - paidMinor);
}

/** Settled obligations leave the default view; they belong to history. */
export function isOutstanding(input: { totalMinor: number; paidMinor: number }): boolean {
  return input.totalMinor - input.paidMinor > 0;
}
