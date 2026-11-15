import type { Metadata } from "next";
import { TransactionDetailsPage } from "@/features/finance/components/transaction-details-page";

export const metadata: Metadata = {
  title: `Transaction`,
};

export default async function FinanceTransactionPage({
  params,
}: {
  params: Promise<{ transactionId: string }>;
}) {
  const { transactionId } = await params;
  return <TransactionDetailsPage transactionId={transactionId} />;
}
