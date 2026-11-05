import type { Metadata } from "next";
import { AdminVenueDetailPage } from "@/features/admin/components/admin-venue-detail-page";

export const metadata: Metadata = { title: "Admin — Venue details" };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <AdminVenueDetailPage facilityId={id} />;
}
