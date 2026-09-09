import type { Metadata } from "next";
import { ExpenseDetailsPage } from "@/features/finance/components/expense-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Expense — ${APP_NAME}`,
};

export default async function FinanceExpensePage({
  params,
}: {
  params: Promise<{ expenseId: string }>;
}) {
  const { expenseId } = await params;
  return <ExpenseDetailsPage expenseId={expenseId} />;
}
