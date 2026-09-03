"use client";

import { ComingSoonReport } from "./coming-soon-report";

export function MembershipReport() {
  return (
    <ComingSoonReport
      title="Membership Report"
      description="Members, renewals, sessions and released capacity."
      emptyMessage="No membership activity for this period."
    />
  );
}
