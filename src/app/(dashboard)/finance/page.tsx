import type { Metadata } from "next";
import { FinanceDashboard } from "@/features/finance/components/finance-dashboard";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Finance — ${APP_NAME}`,
};

export default function FinancePage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Finance</h1>
        <p className="text-sm text-muted-foreground">Revenue, transactions, and refunds — backed by your real payment data.</p>
      </div>
      <FinanceDashboard />
    </div>
  );
}