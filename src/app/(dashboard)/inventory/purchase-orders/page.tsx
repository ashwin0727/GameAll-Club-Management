import type { Metadata } from "next";
import { PurchaseOrdersPage } from "@/features/inventory/components/purchase-orders-page";

export const metadata: Metadata = { title: `Purchase Orders` };

export default function Page() {
  return <PurchaseOrdersPage />;
}
