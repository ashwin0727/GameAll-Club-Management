"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function CourtUtilizationReport() {
  return (
    <ComingSoonReport
      title="Court Utilization"
      description="How hard each court and sport is working."
      emptyMessage="No court activity for this period."
    />
  );
}
