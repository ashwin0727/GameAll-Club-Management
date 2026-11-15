import type { Metadata } from "next";
import { VendorDetailsPage } from "@/features/inventory/components/vendor-details-page";

export const metadata: Metadata = { title: `Vendor` };

export default async function Page({ params }: { params: Promise<{ vendorId: string }> }) {
  const { vendorId } = await params;
  return <VendorDetailsPage vendorId={vendorId} />;
}
