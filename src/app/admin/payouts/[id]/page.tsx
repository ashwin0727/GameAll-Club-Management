import type { Metadata } from "next";
import { AdminPayoutDetailPage } from "@/features/admin/components/admin-payout-detail-page";

export const metadata: Metadata = { title: "Admin — Payout details" };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <AdminPayoutDetailPage facilityId={id} />;
}
