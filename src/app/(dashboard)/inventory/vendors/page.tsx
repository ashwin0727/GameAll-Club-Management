import type { Metadata } from "next";
import { VendorsPage } from "@/features/inventory/components/vendors-page";

export const metadata: Metadata = { title: `Vendors` };

export default function Page() {
  return <VendorsPage />;
}
