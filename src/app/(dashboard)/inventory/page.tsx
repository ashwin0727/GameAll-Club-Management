import type { Metadata } from "next";
import { InventoryOverviewPage } from "@/features/inventory/components/overview-page";

export const metadata: Metadata = { title: `Inventory` };

export default function Page() {
  return <InventoryOverviewPage />;
}
