import type { Metadata } from "next";
import { AdminReviewsPage } from "@/features/admin/components/admin-reviews-page";

export const metadata: Metadata = { title: "Admin — Approvals" };

export default function Page() {
  return <AdminReviewsPage />;
}
