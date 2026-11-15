import type { Metadata } from "next";
import { ReportsOverview } from "@/features/reports/components/reports-overview";

export const metadata: Metadata = { title: `Reports & Analytics` };

export default function ReportsOverviewPage() {
  return <ReportsOverview />;
}
