import type { Metadata } from "next";
import { AdminReviewDetailPage } from "@/features/admin/components/admin-review-detail-page";

export const metadata: Metadata = { title: "Admin — Review setup" };

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <AdminReviewDetailPage facilityId={id} />;
}
