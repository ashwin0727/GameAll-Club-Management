import type { Metadata } from "next";
import { FinanceDashboard } from "@/features/finance/components/finance-dashboard";

export const metadata: Metadata = {
  title: `Finance`,
};

export default function FinancePage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Finance Dashboard</h1>
        <p className="text-sm text-muted-foreground">Manage your revenue, payments and expenses.</p>
      </div>
      <FinanceDashboard />
    </div>
  );
}