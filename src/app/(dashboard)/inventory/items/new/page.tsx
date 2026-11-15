import type { Metadata } from "next";
import { ItemWizardPage } from "@/features/inventory/components/item-wizard-page";

export const metadata: Metadata = { title: `Add Item` };

export default function Page() {
  return <ItemWizardPage />;
}
