import type { Metadata } from "next";
import { StatCards } from "@/features/dashboard/components/stat-cards";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Dashboard — ${APP_NAME}`,
};

export default function DashboardPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Dashboard</h1>
        <p className="text-sm text-muted-foreground">
          Overview of memberships, bookings, and revenue.
        </p>
      </div>
      <StatCards />
    </div>
  );
}