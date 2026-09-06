import type { Metadata } from "next";
import { MaintenanceOverviewPage } from "@/features/maintenance/components/maintenance-overview-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Maintenance — ${APP_NAME}`,
};

export default function MaintenancePage() {
  return <MaintenanceOverviewPage />;
}
