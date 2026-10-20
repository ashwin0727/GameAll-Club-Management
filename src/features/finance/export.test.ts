import { describe, expect, it } from "vitest";
import { buildFinanceCsv } from "@/features/finance/export";
import type { FinanceSummary, LedgerEntry } from "@/features/finance/types";

const summary = { grossRevenueMinor: 1300000, refundsMinor: 50000, expensesMinor: 635000, netRevenueMinor: 615000, outstandingMinor: 600000 } as FinanceSummary;
const entry = (over: Partial<LedgerEntry>): LedgerEntry => ({
  id: "1", reference: "TXN-1", occurredAt: "2026-10-12T10:00:00.000Z", description: "Guest Booking — Asha, Rao", category: "Guest Booking Revenue",
  txnType: "INCOME", paymentMethod: "UPI", amountMinor: 40000, currency: "INR", status: "paid", sourceType: "GUEST_BOOKING",
  bookingId: null, membershipId: null, expenseId: null, ...over,
});

describe("buildFinanceCsv", () => {
  it("states the period, the headline figures, then one row per entry", () => {
    const csv = buildFinanceCsv({ from: "2026-10-01", to: "2026-10-31", summary, entries: [entry({}), entry({ id: "2", reference: "EXP-1", txnType: "EXPENSE", amountMinor: 250000 })] });
    const lines = csv.replace("\uFEFF", "").split("\r\n");
    expect(lines[0]).toBe("GameAll Finance export");
    expect(lines[1]).toBe("Period,2026-10-01 to 2026-10-31");
    expect(lines).toContain("Total revenue (INR),13000.00");
    expect(lines).toContain("Net revenue (INR),6150.00");
    expect(csv).toContain("Date,Reference,Description,Category,Type,Payment method,Amount (INR),Status");
    expect(csv).toContain('"Guest Booking — Asha, Rao"');
    expect(csv).toContain("EXP-1");
    expect(csv).toContain("2500.00");
  });

  it("says so when there is nothing in the period, and notes a sport scope", () => {
    const csv = buildFinanceCsv({ from: "2026-10-01", to: "2026-10-31", summary: null, entries: [], scopeNote: "Badminton" });
    expect(csv).toContain("No transactions in this period.");
    expect(csv).toContain("Scope,");
  });
});
