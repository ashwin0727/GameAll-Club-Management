import type { Metadata } from "next";
import { ReportsOverview } from "@/features/reports/components/reports-overview";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Reports & Analytics — ${APP_NAME}` };

export default function ReportsOverviewPage() {
  return <ReportsOverview />;
}
