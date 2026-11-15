import type { Metadata } from "next";
import { AddStaffPage } from "@/features/staff/components/add-staff-page";

export const metadata: Metadata = { title: `Add Staff` };

export default function Page() {
  return <AddStaffPage />;
}
