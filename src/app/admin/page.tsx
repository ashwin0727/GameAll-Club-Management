import type { Metadata } from "next";
import { AdminHomePage } from "@/features/admin/components/admin-home-page";

export const metadata: Metadata = { title: "Admin — Facilities" };

export default function Page() {
  return <AdminHomePage />;
}
