import type { Metadata } from "next";
import { AdminPayoutsPage } from "@/features/admin/components/admin-payouts-page";

export const metadata: Metadata = { title: "Admin — Payouts" };

export default function Page() {
  return <AdminPayoutsPage />;
}
