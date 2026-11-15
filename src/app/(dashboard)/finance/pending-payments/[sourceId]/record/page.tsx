import type { Metadata } from "next";
import { RecordPaymentPage } from "@/features/finance/components/record-payment-page";

export const metadata: Metadata = {
  title: `Record Payment`,
};

export default async function FinanceRecordPaymentPage({
  params,
}: {
  params: Promise<{ sourceId: string }>;
}) {
  const { sourceId } = await params;
  return <RecordPaymentPage sourceId={sourceId} />;
}
