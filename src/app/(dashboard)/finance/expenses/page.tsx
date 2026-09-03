import type { Metadata } from "next";
import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { ExpensesPage } from "@/features/finance/components/expenses-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Expenses — ${APP_NAME}`,
};

export default function FinanceExpensesPage() {
  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/finance" className="hover:text-foreground">
          Finance
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Expenses</span>
      </nav>

      <ExpensesPage />
    </div>
  );
}
