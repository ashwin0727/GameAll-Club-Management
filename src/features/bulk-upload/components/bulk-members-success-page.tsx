"use client";

import { useEffect, useState } from "react";
import { BulkSuccessView } from "@/features/bulk-upload/components/bulk-success-view";
import { loadBulkResults, MEMBERS_KEY, type MemberBulkResult } from "@/features/bulk-upload/bulk-run";

export function BulkMembersSuccessPage() {
  const [rows, setRows] = useState<MemberBulkResult[] | null | undefined>(undefined);
  useEffect(() => setRows(loadBulkResults<MemberBulkResult>(MEMBERS_KEY)), []);
  if (rows === undefined) return null;
  return (
    <BulkSuccessView
      title="Members Added Successfully"
      noun="Members"
      rows={rows}
      listHref="/memberships/v1"
      listLabel="View Membership Dashboard"
      addHref="/memberships/v1/new"
      columns={[
        { header: "Member", cell: (r) => <span className="font-medium">{r.name}</span> },
        { header: "Plan", cell: (r) => r.planName },
        { header: "Court", cell: (r) => r.courtName },
        { header: "Timings", cell: (r) => r.timings },
        { header: "Amount", className: "text-right tabular-nums", cell: (r) => `₹${r.amountInr.toLocaleString("en-IN")}` },
      ]}
    />
  );
}
