"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function BookingReport() {
  return (
    <ComingSoonReport
      title="Booking Report"
      description="Volume, status mix and demand by sport."
      emptyMessage="No booking data for this period."
    />
  );
}
