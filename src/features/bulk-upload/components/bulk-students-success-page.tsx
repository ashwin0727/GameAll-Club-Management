"use client";

import { useEffect, useState } from "react";
import { BulkSuccessView } from "@/features/bulk-upload/components/bulk-success-view";
import { loadBulkResults, STUDENTS_KEY, type StudentBulkResult } from "@/features/bulk-upload/bulk-run";

export function BulkStudentsSuccessPage() {
  const [rows, setRows] = useState<StudentBulkResult[] | null | undefined>(undefined);
  useEffect(() => setRows(loadBulkResults<StudentBulkResult>(STUDENTS_KEY)), []);
  if (rows === undefined) return null;
  return (
    <BulkSuccessView
      title="Students Added Successfully"
      noun="Students"
      rows={rows}
      listHref="/coaching/students"
      listLabel="View Students"
      addHref="/coaching/students/new"
      columns={[
        { header: "Student", cell: (r) => <span className="font-medium">{r.name}</span> },
        { header: "Program", cell: (r) => r.programName },
        { header: "Total Sessions", className: "text-right tabular-nums", cell: (r) => r.totalSessions ?? "—" },
        {
          header: "Total Amount",
          className: "text-right tabular-nums",
          cell: (r) => (r.totalMinor > 0 ? `₹${(r.totalMinor / 100).toLocaleString("en-IN")}` : "—"),
        },
      ]}
    />
  );
}
