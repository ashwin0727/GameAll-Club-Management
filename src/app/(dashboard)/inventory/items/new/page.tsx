import type { Metadata } from "next";
import { ItemWizardPage } from "@/features/inventory/components/item-wizard-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Add Item — ${APP_NAME}` };

export default function Page() {
  return <ItemWizardPage />;
}
