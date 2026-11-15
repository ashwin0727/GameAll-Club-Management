import type { Metadata } from "next";
import { ExpenseDetailsPage } from "@/features/finance/components/expense-details-page";

export const metadata: Metadata = {
  title: `Expense`,
};

export default async function FinanceExpensePage({
  params,
}: {
  params: Promise<{ expenseId: string }>;
}) {
  const { expenseId } = await params;
  return <ExpenseDetailsPage expenseId={expenseId} />;
}
