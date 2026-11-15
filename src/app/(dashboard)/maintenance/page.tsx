import type { Metadata } from "next";
import { MaintenanceOverviewPage } from "@/features/maintenance/components/maintenance-overview-page";

export const metadata: Metadata = {
  title: `Maintenance`,
};

export default function MaintenancePage() {
  return <MaintenanceOverviewPage />;
}
