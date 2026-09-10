import type { Metadata } from "next";
import { PurchaseOrderWizardPage } from "@/features/inventory/components/purchase-order-wizard-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `New Purchase Order — ${APP_NAME}` };

export default function Page() {
  return <PurchaseOrderWizardPage />;
}
