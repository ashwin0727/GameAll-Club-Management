import type { Metadata } from "next";
import { ItemsPage } from "@/features/inventory/components/items-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Items — ${APP_NAME}` };

export default function Page() {
  return <ItemsPage />;
}
