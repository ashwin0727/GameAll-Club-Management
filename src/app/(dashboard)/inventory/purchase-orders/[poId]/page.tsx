import type { Metadata } from "next";
import { PurchaseOrderDetailsPage } from "@/features/inventory/components/purchase-order-details-page";

export const metadata: Metadata = { title: `Purchase Order` };

export default async function Page({ params }: { params: Promise<{ poId: string }> }) {
  const { poId } = await params;
  return <PurchaseOrderDetailsPage poId={poId} />;
}
