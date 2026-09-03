import type { Metadata } from "next";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { TransactionsList } from "@/features/finance/components/transactions-list";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Transactions — ${APP_NAME}`,
};

export default function FinanceTransactionsPage() {
  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/finance" className="hover:text-foreground">
          Finance
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Transactions</span>
      </nav>

      <TransactionsList />
    </div>
  );
}
