import type { Metadata } from "next";
import { AdminVenuesPage } from "@/features/admin/components/admin-venues-page";

export const metadata: Metadata = { title: "Admin — Venues" };

export default function Page() {
  return <AdminVenuesPage />;
}
