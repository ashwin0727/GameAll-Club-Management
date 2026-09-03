"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function ReportsOverview() {
  return (
    <ComingSoonReport
      title="Reports & Analytics"
      description="Business performance at a glance."
      emptyMessage="No activity for this period yet."
    />
  );
}
