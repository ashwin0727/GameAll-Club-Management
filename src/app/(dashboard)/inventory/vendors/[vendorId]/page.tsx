import type { Metadata } from "next";
import { VendorDetailsPage } from "@/features/inventory/components/vendor-details-page";
import { APP_NAME } from "@/lib/constants";

export const metadata: Metadata = { title: `Vendor — ${APP_NAME}` };

export default async function Page({ params }: { params: Promise<{ vendorId: string }> }) {
  const { vendorId } = await params;
  return <VendorDetailsPage vendorId={vendorId} />;
}
