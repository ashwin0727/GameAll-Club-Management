"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function RevenueReport() {
  return (
    <ComingSoonReport
      title="Revenue Report"
      description="Trend, breakdown and payment methods."
      emptyMessage="No revenue data for this period."
    />
  );
}
