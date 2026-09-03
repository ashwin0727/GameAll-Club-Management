import { describe, expect, it } from "vitest";
import {
  canRecordPayment,
  canRefund,
  isLoss,
  netRevenueMinor,
  realisedRevenueMinor,
  settlementState,
} from "./money";

describe("netRevenueMinor", () => {
  it("takes refunds and expenses off the gross", () => {
    expect(
      netRevenueMinor({ grossRevenueMinor: 12450000, refundsMinor: 0, expensesMinor: 3240000 }),
    ).toBe(9210000);
  });

  it("excludes expenses from revenue rather than netting them into it", () => {
    // Spec §13: an expense must never reduce the revenue figure itself.
    const summary = { grossRevenueMinor: 40000, refundsMinor: 0, expensesMinor: 100000 };
    expect(summary.grossRevenueMinor).toBe(40000);
    expect(netRevenueMinor(summary)).toBe(-60000);
  });

  it("reports a loss when a facility spends more than it takes", () => {
    // Spec §45: ₹400 revenue against ₹1,000 maintenance is -₹600.
    expect(isLoss({ grossRevenueMinor: 40000, refundsMinor: 0, expensesMinor: 100000 })).toBe(true);
  });

  it("is not a loss when takings cover the spend", () => {
    expect(isLoss({ grossRevenueMinor: 100000, refundsMinor: 0, expensesMinor: 40000 })).toBe(false);
  });

  it("counts a refund once, not twice", () => {
    // Spec §17/§23: a full refund leaves nothing realised, but the original
    // revenue is not erased.
    const summary = { grossRevenueMinor: 100000, refundsMinor: 100000, expensesMinor: 0 };
    expect(realisedRevenueMinor(summary)).toBe(0);
    expect(summary.grossRevenueMinor).toBe(100000);
  });
});

describe("canRecordPayment", () => {
  it("accepts the full outstanding amount", () => {
    expect(canRecordPayment({ amountMinor: 40000, outstandingMinor: 40000 })).toEqual({ ok: true });
  });

  it("accepts part of it", () => {
    expect(canRecordPayment({ amountMinor: 50000, outstandingMinor: 100000 })).toEqual({ ok: true });
  });

  it("refuses more than is owed", () => {
    const result = canRecordPayment({ amountMinor: 50000, outstandingMinor: 40000 });
    expect(result).toMatchObject({ ok: false });
  });

  it("refuses a second payment on something already settled", () => {
    // Spec §11: the double-click case must not take the money twice.
    const result = canRecordPayment({ amountMinor: 40000, outstandingMinor: 0 });
    expect(result).toMatchObject({ ok: false });
  });

  it("refuses zero and negative amounts", () => {
    expect(canRecordPayment({ amountMinor: 0, outstandingMinor: 40000 }).ok).toBe(false);
    expect(canRecordPayment({ amountMinor: -100, outstandingMinor: 40000 }).ok).toBe(false);
  });
});

describe("canRefund", () => {
  it("allows a full refund of what was taken", () => {
    expect(canRefund({ amountMinor: 100000, paidMinor: 100000, alreadyRefundedMinor: 0 })).toEqual({ ok: true });
  });

  it("allows a partial refund", () => {
    expect(canRefund({ amountMinor: 40000, paidMinor: 100000, alreadyRefundedMinor: 0 })).toEqual({ ok: true });
  });

  it("refuses more than was paid", () => {
    expect(canRefund({ amountMinor: 150000, paidMinor: 100000, alreadyRefundedMinor: 0 }).ok).toBe(false);
  });

  it("counts what has already been given back", () => {
    // ₹1,000 paid, ₹400 already refunded: ₹600 is the most that remains.
    expect(canRefund({ amountMinor: 60000, paidMinor: 100000, alreadyRefundedMinor: 40000 })).toEqual({ ok: true });
    expect(canRefund({ amountMinor: 70000, paidMinor: 100000, alreadyRefundedMinor: 40000 }).ok).toBe(false);
  });

  it("refuses when nothing was ever paid", () => {
    expect(canRefund({ amountMinor: 40000, paidMinor: 0, alreadyRefundedMinor: 0 }).ok).toBe(false);
  });

  it("refuses once fully refunded", () => {
    expect(canRefund({ amountMinor: 100, paidMinor: 100000, alreadyRefundedMinor: 100000 }).ok).toBe(false);
  });
});

describe("settlementState", () => {
  it("is UNPAID before any money arrives", () => {
    expect(settlementState({ totalMinor: 40000, paidMinor: 0, refundedMinor: 0 })).toBe("UNPAID");
  });

  it("is PARTIALLY_PAID part-way", () => {
    expect(settlementState({ totalMinor: 100000, paidMinor: 50000, refundedMinor: 0 })).toBe("PARTIALLY_PAID");
  });

  it("is PAID once the total is covered", () => {
    expect(settlementState({ totalMinor: 100000, paidMinor: 100000, refundedMinor: 0 })).toBe("PAID");
  });

  it("is PARTIALLY_REFUNDED when some is given back", () => {
    expect(settlementState({ totalMinor: 100000, paidMinor: 100000, refundedMinor: 40000 })).toBe(
      "PARTIALLY_REFUNDED",
    );
  });

  it("is REFUNDED when all of it is", () => {
    expect(settlementState({ totalMinor: 100000, paidMinor: 100000, refundedMinor: 100000 })).toBe("REFUNDED");
  });
});

describe("spec §43 — guest booking through to finance", () => {
  const bookingMinor = 40000;

  it("shows nothing earned and the full amount outstanding before payment", () => {
    expect(settlementState({ totalMinor: bookingMinor, paidMinor: 0, refundedMinor: 0 })).toBe("UNPAID");
    expect(netRevenueMinor({ grossRevenueMinor: 0, refundsMinor: 0, expensesMinor: 0 })).toBe(0);
  });

  it("shows the amount earned and nothing outstanding once recorded", () => {
    expect(canRecordPayment({ amountMinor: bookingMinor, outstandingMinor: bookingMinor })).toEqual({ ok: true });
    expect(settlementState({ totalMinor: bookingMinor, paidMinor: bookingMinor, refundedMinor: 0 })).toBe("PAID");
    expect(netRevenueMinor({ grossRevenueMinor: bookingMinor, refundsMinor: 0, expensesMinor: 0 })).toBe(40000);
  });

  it("nets a ₹1,000 maintenance expense against that ₹400 to -₹600", () => {
    expect(
      netRevenueMinor({ grossRevenueMinor: bookingMinor, refundsMinor: 0, expensesMinor: 100000 }),
    ).toBe(-60000);
  });
});
