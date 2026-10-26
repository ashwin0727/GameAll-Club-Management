import type { Metadata } from "next";
import { AdminFacilityPage } from "@/features/admin/components/admin-facility-page";

export const metadata: Metadata = { title: "Admin — Facility" };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <AdminFacilityPage facilityId={id} />;
}
