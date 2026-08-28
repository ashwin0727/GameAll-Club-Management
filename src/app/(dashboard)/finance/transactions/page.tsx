import type { Metadata } from "next";
import Link from "next/link";
import { TransactionsList } from "@/features/finance/components/transactions-list";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Transactions — ${APP_NAME}`,
};

export default function FinanceTransactionsPage() {
  return (
    <div className="space-y-6">
      <div>
        <Link href="/finance" className="text-xs font-medium text-primary hover:underline">
          ← Finance
        </Link>
        <h1 className="text-xl font-semibold">Transactions</h1>
        <p className="text-sm text-muted-foreground">Every captured payment, searchable and filterable.</p>
      </div>
      <TransactionsList />
    </div>
  );
}