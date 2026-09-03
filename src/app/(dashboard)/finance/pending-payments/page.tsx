import type { Metadata } from "next";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { PendingPaymentsPage } from "@/features/finance/components/pending-payments-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Pending Payments — ${APP_NAME}`,
};

export default function FinancePendingPaymentsPage() {
  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/finance" className="hover:text-foreground">
          Finance
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Pending Payments</span>
      </nav>

      <PendingPaymentsPage />
    </div>
  );
}
