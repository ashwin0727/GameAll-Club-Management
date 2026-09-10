import type { Metadata } from "next";
import { InventoryOverviewPage } from "@/features/inventory/components/overview-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Inventory — ${APP_NAME}` };

export default function Page() {
  return <InventoryOverviewPage />;
}
