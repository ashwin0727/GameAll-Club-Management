import type { Metadata } from "next";
import { AdminTransactionDetailPage } from "@/features/admin/components/admin-transaction-detail-page";

export const metadata: Metadata = { title: "Admin — Facility transactions" };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <AdminTransactionDetailPage facilityId={id} />;
}
