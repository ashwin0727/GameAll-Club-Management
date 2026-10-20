import { toCsv } from "@/features/reports/aggregation";
import type { FinanceSummary, LedgerEntry } from "@/features/finance/types";

const rupees = (minor: number) => (minor / 100).toFixed(2);

/**
 * The Finance export: the period, the headline figures for it, then every ledger row (payments, refunds and — when all
 * sports are in view — expenses) that falls inside it. Built from exactly what the page is showing, so the file always
 * matches the dates that were applied.
 */
export function buildFinanceCsv(input: {
  from: string;
  to: string;
  summary: FinanceSummary | null;
  entries: LedgerEntry[];
  /** Said in the file when a sport selection narrowed the figures. */
  scopeNote?: string | null;
}): string {
  const head: string[] = ["GameAll Finance export", `Period,${input.from} to ${input.to}`];
  if (input.scopeNote) head.push(`Scope,"${input.scopeNote.replace(/"/g, '""')}"`);
  if (input.summary) {
    head.push(
      `Total revenue (INR),${rupees(input.summary.grossRevenueMinor)}`,
      `Refunds (INR),${rupees(input.summary.refundsMinor)}`,
      `Total expenses (INR),${rupees(input.summary.expensesMinor)}`,
      `Net revenue (INR),${rupees(input.summary.netRevenueMinor)}`,
      `Pending payments (INR),${rupees(input.summary.outstandingMinor)}`,
    );
  }

  const table = toCsv(
    input.entries.map((e) => ({
      Date: new Date(e.occurredAt).toLocaleString("en-IN", { day: "2-digit", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", hour12: true }),
      Reference: e.reference,
      Description: e.description,
      Category: e.category,
      Type: e.txnType,
      "Payment method": e.paymentMethod,
      "Amount (INR)": rupees(e.amountMinor),
      Status: e.status,
    })),
  );

  // The BOM makes Excel read the file as UTF-8 (the rupee sign and customer names survive).
  return "﻿" + [...head, "", table || "No transactions in this period."].join("\r\n");
}

/** Saves text as a file through the browser. */
export function downloadCsv(filename: string, csv: string): void {
  const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
