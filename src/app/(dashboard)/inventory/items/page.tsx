import type { Metadata } from "next";
import { ItemsPage } from "@/features/inventory/components/items-page";

export const metadata: Metadata = { title: `Items` };

export default function Page() {
  return <ItemsPage />;
}
