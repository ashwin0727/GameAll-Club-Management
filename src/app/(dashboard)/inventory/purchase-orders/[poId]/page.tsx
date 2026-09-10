import type { Metadata } from "next";
import { PurchaseOrderDetailsPage } from "@/features/inventory/components/purchase-order-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Purchase Order — ${APP_NAME}` };

export default async function Page({ params }: { params: Promise<{ poId: string }> }) {
  const { poId } = await params;
  return <PurchaseOrderDetailsPage poId={poId} />;
}
