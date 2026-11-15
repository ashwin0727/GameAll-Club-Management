import type { Metadata } from "next";
import { PurchaseOrderWizardPage } from "@/features/inventory/components/purchase-order-wizard-page";

export const metadata: Metadata = { title: `New Purchase Order` };

export default function Page() {
  return <PurchaseOrderWizardPage />;
}
