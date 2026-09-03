import { describe, expect, it } from "vitest";
import { isOutstanding, obligationStatus, outstandingMinor } from "./obligation";
import { canRecordPayment } from "./money";

const TODAY = new Date(2026, 8, 3); // 03 Sep 2026

describe("obligationStatus", () => {
  it("is PENDING when nothing has been collected", () => {
    expect(obligationStatus({ totalMinor: 500000, paidMinor: 0 })).toBe("PENDING");
  });

  it("is PARTIALLY_PAID once some of it has", () => {
    expect(obligationStatus({ totalMinor: 500000, paidMinor: 200000 })).toBe("PARTIALLY_PAID");
  });

  it("is PAID once the total is covered", () => {
    expect(obligationStatus({ totalMinor: 500000, paidMinor: 500000 })).toBe("PAID");
  });

  it("is PAID when more was collected than owed, rather than going negative", () => {
    expect(obligationStatus({ totalMinor: 500000, paidMinor: 600000 })).toBe("PAID");
  });

  it("is OVERDUE when the due date has passed and money is still owed", () => {
    expect(obligationStatus({ totalMinor: 300000, paidMinor: 0, dueOn: "2026-09-01", today: TODAY })).toBe(
      "OVERDUE",
    );
  });

  it("is not overdue on the due date itself", () => {
    expect(obligationStatus({ totalMinor: 300000, paidMinor: 0, dueOn: "2026-09-03", today: TODAY })).toBe(
      "PENDING",
    );
  });

  it("is never overdue once settled, however old", () => {
    expect(obligationStatus({ totalMinor: 300000, paidMinor: 300000, dueOn: "2020-01-01", today: TODAY })).toBe(
      "PAID",
    );
  });
});

describe("outstandingMinor", () => {
  it("is the gap between what is owed and what was collected", () => {
    expect(outstandingMinor(80000, 0)).toBe(80000);
    expect(outstandingMinor(1000000, 300000)).toBe(700000);
  });

  it("never goes negative on an overpayment", () => {
    expect(outstandingMinor(50000, 60000)).toBe(0);
  });
});

describe("isOutstanding", () => {
  it("keeps unsettled obligations in the default view", () => {
    expect(isOutstanding({ totalMinor: 80000, paidMinor: 0 })).toBe(true);
    expect(isOutstanding({ totalMinor: 80000, paidMinor: 40000 })).toBe(true);
  });

  it("drops settled ones — they belong to payment history", () => {
    expect(isOutstanding({ totalMinor: 80000, paidMinor: 80000 })).toBe(false);
  });
});

describe("spec §50 record 1 — John Doe, guest booking ₹800", () => {
  const total = 80000;

  it("appears as pending with the full amount outstanding", () => {
    expect(obligationStatus({ totalMinor: total, paidMinor: 0 })).toBe("PENDING");
    expect(outstandingMinor(total, 0)).toBe(80000);
    expect(isOutstanding({ totalMinor: total, paidMinor: 0 })).toBe(true);
  });

  it("settles and leaves the outstanding view once ₹800 is collected", () => {
    expect(canRecordPayment({ amountMinor: 80000, outstandingMinor: 80000 })).toEqual({ ok: true });
    expect(obligationStatus({ totalMinor: total, paidMinor: 80000 })).toBe("PAID");
    expect(isOutstanding({ totalMinor: total, paidMinor: 80000 })).toBe(false);
  });
});

describe("spec §50 record 2 — Sarah Kumar, membership ₹10,000", () => {
  const total = 1000000;

  it("starts partially paid with ₹7,000 outstanding", () => {
    expect(obligationStatus({ totalMinor: total, paidMinor: 300000 })).toBe("PARTIALLY_PAID");
    expect(outstandingMinor(total, 300000)).toBe(700000);
  });

  it("stays in the list after a ₹4,000 part payment", () => {
    expect(canRecordPayment({ amountMinor: 400000, outstandingMinor: 700000 })).toEqual({ ok: true });
    expect(obligationStatus({ totalMinor: total, paidMinor: 700000 })).toBe("PARTIALLY_PAID");
    expect(outstandingMinor(total, 700000)).toBe(300000);
    expect(isOutstanding({ totalMinor: total, paidMinor: 700000 })).toBe(true);
  });

  it("leaves the list once the final ₹3,000 is collected", () => {
    expect(canRecordPayment({ amountMinor: 300000, outstandingMinor: 300000 })).toEqual({ ok: true });
    expect(obligationStatus({ totalMinor: total, paidMinor: total })).toBe("PAID");
    expect(isOutstanding({ totalMinor: total, paidMinor: total })).toBe(false);
  });

  it("refuses a payment larger than what remains", () => {
    // The stale-balance case: someone else collected first, so ₹7,000
    // against a ₹3,000 balance must not go through.
    expect(canRecordPayment({ amountMinor: 700000, outstandingMinor: 300000 }).ok).toBe(false);
  });
});
