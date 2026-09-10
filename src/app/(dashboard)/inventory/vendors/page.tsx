import type { Metadata } from "next";
import { VendorsPage } from "@/features/inventory/components/vendors-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Vendors — ${APP_NAME}` };

export default function Page() {
  return <VendorsPage />;
}
