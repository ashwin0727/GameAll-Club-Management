import type { Metadata } from "next";
import { StockMovementsPage } from "@/features/inventory/components/stock-movements-page";

export const metadata: Metadata = { title: `Stock Movements` };

export default function Page() {
  return <StockMovementsPage />;
}
