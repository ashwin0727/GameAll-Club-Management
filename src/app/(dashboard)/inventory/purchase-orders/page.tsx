import type { Metadata } from "next";
import { PurchaseOrdersPage } from "@/features/inventory/components/purchase-orders-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Purchase Orders — ${APP_NAME}` };

export default function Page() {
  return <PurchaseOrdersPage />;
}
