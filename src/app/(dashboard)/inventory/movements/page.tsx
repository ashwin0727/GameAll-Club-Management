import type { Metadata } from "next";
import { StockMovementsPage } from "@/features/inventory/components/stock-movements-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Stock Movements — ${APP_NAME}` };

export default function Page() {
  return <StockMovementsPage />;
}
