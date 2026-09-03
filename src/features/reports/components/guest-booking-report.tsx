"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function GuestBookingReport() {
  return (
    <ComingSoonReport
      title="Guest Booking Report"
      description="Guest volume, value and collection."
      emptyMessage="No guest bookings for this period."
    />
  );
}
