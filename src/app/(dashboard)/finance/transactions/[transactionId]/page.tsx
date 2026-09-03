import type { Metadata } from "next";
import { TransactionDetailsPage } from "@/features/finance/components/transaction-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Transaction — ${APP_NAME}`,
};

export default async function FinanceTransactionPage({
  params,
}: {
  params: Promise<{ transactionId: string }>;
}) {
  const { transactionId } = await params;
  return <TransactionDetailsPage transactionId={transactionId} />;
}
