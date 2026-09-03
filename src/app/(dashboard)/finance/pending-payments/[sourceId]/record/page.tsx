import type { Metadata } from "next";
import { RecordPaymentPage } from "@/features/finance/components/record-payment-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: `Record Payment — ${APP_NAME}`,
};

export default async function FinanceRecordPaymentPage({
  params,
}: {
  params: Promise<{ sourceId: string }>;
}) {
  const { sourceId } = await params;
  return <RecordPaymentPage sourceId={sourceId} />;
}
